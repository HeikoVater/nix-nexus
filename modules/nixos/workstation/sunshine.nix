{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.workstation.sunshine;
  audioSinkName = "sunshine-game";
  disconnectMarker = "sunshine-client-disconnected";
  outerWidth = 3840;
  outerHeight = 2160;
  pegasusEnvironmentFile = "sunshine-pegasus-session.env";
  pegasusUnit = "sunshine-pegasus-session.service";
  steamUnit = "sunshine-steam.service";
  steamPackage = config.programs.steam.package;
  systemctl = lib.getExe' pkgs.systemd "systemctl";
  workspaceSelector =
    if builtins.match "[0-9]+" cfg.display.workspace != null then
      cfg.display.workspace
    else
      "name:${cfg.display.workspace}";
  streamEnvironment = {
    PIPEWIRE_PROPS = "{sunshine.audio-route=${audioSinkName}}";
    PULSE_PROP = "sunshine.audio-route=${audioSinkName}";
    PULSE_SINK = audioSinkName;
    SDL_AUDIODRIVER = "pulseaudio";
  };
  explicitSinkInitialization = lib.concatStringsSep "\n" [
    "        sink.host = sink_name;"
    ""
    "        if (!config::audio.sink.empty()) {"
    "          return std::make_optional(std::move(sink));"
    "        }"
  ];

  sunshinePackage = (pkgs.sunshine.override { cudaSupport = true; }).overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      # Application audio is routed explicitly, so changing the session-wide
      # default sink would only disrupt unrelated local applications.
      substituteInPlace src/audio.cpp \
        --replace-fail \
          'ref->restore_sink = ref->sink.host != *sink;' \
          'ref->restore_sink = config::audio.sink.empty() && ref->sink.host != *sink;'

      # Sunshine's automatically-created null sinks are unused when an explicit
      # capture sink is configured and would become extra default candidates.
      substituteInPlace src/platform/linux/audio.cpp \
        --replace-fail \
          ${lib.escapeShellArg "        sink.host = sink_name;"} \
          ${lib.escapeShellArg explicitSinkInitialization}

      # Notify the foreground app when its final client disconnects. The app
      # then exits through Sunshine's normal serialized process lifecycle.
      substituteInPlace src/stream.cpp \
        --replace-fail \
          '#include <fstream>' \
          ${lib.escapeShellArg "#include <cstdlib>\n#include <fstream>"} \
        --replace-fail \
          ${lib.escapeShellArg "        platf::streaming_will_stop();\n      }"} \
          ${lib.escapeShellArg ''
              platf::streaming_will_stop();
              if (const auto runtime_dir = std::getenv("XDG_RUNTIME_DIR")) {
                std::ofstream {std::string {runtime_dir} + "/${disconnectMarker}"}.put('\n');
              }
            }''}
    '';
  });

  streamAudioRouter = pkgs.writeShellApplication {
    name = "sunshine-stream-audio-router";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.jq
      pkgs.pulseaudio
      pkgs.systemd
    ];
    text = ''
      if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        printf 'Usage: sunshine-stream-audio-router UNIT [PID-FILE]\n' >&2
        exit 2
      fi

      readonly session_unit="$1"
      readonly additional_pids_file="''${2:-}"
      readonly sink_name=${lib.escapeShellArg audioSinkName}
      session_cgroup=""

      process_belongs_to_session() {
        local cgroup_file="$1"
        local controllers hierarchy path

        [ -n "$session_cgroup" ] && [ -r "$cgroup_file" ] || return 1
        while IFS=: read -r hierarchy controllers path; do
          if [ "$hierarchy" = 0 ] && [ -z "$controllers" ]; then
            case "$path" in
              "$session_cgroup"|"$session_cgroup"/*) return 0 ;;
            esac
          fi
        done <"$cgroup_file"
        return 1
      }

      process_is_listed() {
        [ -n "$additional_pids_file" ] \
          && [ -r "$additional_pids_file" ] \
          && grep --fixed-strings --line-regexp --quiet "$1" "$additional_pids_file"
      }

      route_streams() {
        local sink_index

        session_cgroup="$(
          systemctl --user show --property=ControlGroup --value "$session_unit" 2>/dev/null
        )"
        [ -n "$session_cgroup" ] || return

        sink_index="$(
          pactl --format=json list sinks \
            | jq --raw-output --arg sink "$sink_name" \
              'first(.[] | select(.name == $sink) | .index) // empty'
        )"
        if [ -z "$sink_index" ]; then
          return
        fi

        pactl --format=json list sink-inputs \
          | jq --raw-output \
            '.[] | [.index, .sink, (.properties["application.process.id"] // "")] | @tsv' \
          | while IFS=$'\t' read -r input_index current_sink process_id; do
              if [ -z "$process_id" ] || [ "$current_sink" = "$sink_index" ]; then
                continue
              fi

              if process_belongs_to_session "/proc/$process_id/cgroup" \
                || process_is_listed "$process_id"; then
                pactl move-sink-input "$input_index" "$sink_name" >/dev/null 2>&1 || true
              fi
            done
      }

      export LC_ALL=C
      trap 'exit 0' INT TERM HUP
      while true; do
        route_streams || true
        sleep 0.5
      done
    '';
  };

  pegasusSession = pkgs.writeShellApplication {
    name = "sunshine-pegasus-session";
    runtimeInputs = [
      pkgs.hyprland
      pkgs.jq
      pkgs.lutris
      pkgs.procps
      pkgs.xdg-utils
    ];
    text = ''
      readonly stream_output=${lib.escapeShellArg cfg.display.connector}
      readonly client_width="$SUNSHINE_CLIENT_WIDTH"
      readonly client_height="$SUNSHINE_CLIENT_HEIGHT"
      readonly client_fps="$SUNSHINE_CLIENT_FPS"

      if ! hyprctl monitors all -j \
        | jq --exit-status \
          --arg output "$stream_output" \
          --argjson width ${toString outerWidth} \
          --argjson height ${toString outerHeight} \
          --argjson refresh ${toString cfg.display.refreshRate} \
          'any(.[];
            .name == $output
            and (.disabled | not)
            and .width == $width
            and .height == $height
            and (((.refreshRate - $refresh) | if . < 0 then -. else . end) < 0.001)
          )' >/dev/null; then
        printf 'Sunshine output %s is not active at %sx%s@%s Hz.\n' \
          "$stream_output" \
          ${toString outerWidth} \
          ${toString outerHeight} \
          ${lib.escapeShellArg (toString cfg.display.refreshRate)} >&2
        exit 1
      fi

      # A pre-existing singleton would keep its desktop display and audio
      # environment instead of inheriting the streaming session's environment.
      if pgrep --uid "$UID" --full -- ${lib.escapeShellArg "${lib.getExe pkgs.pegasus-frontend}.*"} \
        >/dev/null; then
        printf 'Sunshine session refused: an existing Pegasus process is already running.\n' >&2
        exit 1
      fi

      for process in steam steamwebhelper lutris; do
        if pgrep --uid "$UID" --exact "$process" >/dev/null; then
          printf 'Sunshine session refused: an existing %s process is already running.\n' \
            "$process" >&2
          exit 1
        fi
      done

      hyprctl dispatch moveworkspacetomonitor \
        ${lib.escapeShellArg workspaceSelector} "$stream_output" >/dev/null

      router_pid=""
      session_pid=""

      cleanup() {
        if [ -n "$session_pid" ]; then
          kill "$session_pid" >/dev/null 2>&1 || true
          wait "$session_pid" >/dev/null 2>&1 || true
        fi
        if [ -n "$router_pid" ]; then
          kill "$router_pid" >/dev/null 2>&1 || true
          wait "$router_pid" >/dev/null 2>&1 || true
        fi
      }

      trap cleanup EXIT
      trap 'exit 0' INT TERM HUP

      ${lib.getExe streamAudioRouter} ${lib.escapeShellArg pegasusUnit} &
      router_pid=$!

      ${config.security.wrapperDir}/gamescope \
        --backend wayland \
        --fullscreen \
        --output-width ${toString outerWidth} \
        --output-height ${toString outerHeight} \
        --nested-width "$client_width" \
        --nested-height "$client_height" \
        --nested-refresh "$client_fps" \
        --nested-unfocused-refresh "$client_fps" \
        --scaler fit \
        --hide-cursor-delay 1000 \
        --rt \
        -- ${
          lib.escapeShellArgs [
            (lib.getExe pkgs.pegasus-frontend)
            "--disable-menu-reboot"
            "--disable-menu-shutdown"
            "--disable-menu-suspend"
          ]
        } &
      session_pid=$!
      wait "$session_pid"
    '';
  };

  steamStreamSession = pkgs.writeShellApplication {
    name = "sunshine-steam-stream-session";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
      pkgs.jq
      pkgs.pulseaudio
      pkgs.procps
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      readonly steam_unit=${lib.escapeShellArg steamUnit}
      readonly pegasus_unit=${lib.escapeShellArg pegasusUnit}
      readonly big_picture_title="Steam Big Picture Mode"
      readonly stream_output=${lib.escapeShellArg cfg.display.connector}
      readonly stream_workspace=${lib.escapeShellArg cfg.display.workspace}
      readonly stream_workspace_selector=${lib.escapeShellArg workspaceSelector}
      readonly disconnect_marker="$XDG_RUNTIME_DIR/${disconnectMarker}"
      readonly game_process_registry="$XDG_RUNTIME_DIR/sunshine-steam-game-processes"
      readonly session_lock="$XDG_RUNTIME_DIR/sunshine-streaming-session.lock"
      readonly steam_command=${lib.escapeShellArg (lib.getExe steamPackage)}
      readonly stream_pids_file="$XDG_RUNTIME_DIR/sunshine-steam-stream-pids"
      audio_snapshot_file=""
      cleaned_up=false
      default_sink=""
      lease_active=false
      router_pid=""
      snapshot_file=""
      steam_cgroup=""

      process_belongs_to_steam() {
        local cgroup_file="$1"
        local controllers hierarchy path

        [ -n "$steam_cgroup" ] && [ -r "$cgroup_file" ] || return 1
        while IFS=: read -r hierarchy controllers path; do
          if [ "$hierarchy" = 0 ] && [ -z "$controllers" ]; then
            case "$path" in
              "$steam_cgroup"|"$steam_cgroup"/*) return 0 ;;
            esac
          fi
        done <"$cgroup_file"
        return 1
      }

      steam_pids() {
        local cgroup_file pid

        for cgroup_file in /proc/[0-9]*/cgroup; do
          [ -r "$cgroup_file" ] || continue
          if process_belongs_to_steam "$cgroup_file"; then
            pid="''${cgroup_file#/proc/}"
            printf '%s\n' "''${pid%/cgroup}"
          fi
        done
      }

      steam_pids_json() {
        steam_pids \
          | jq --raw-input --slurp 'split("\n") | map(select(length > 0) | tonumber)'
      }

      steam_game_roots() {
        local entry environ_file pid value

        for environ_file in /proc/[0-9]*/environ; do
          [ -r "$environ_file" ] || continue
          pid="''${environ_file#/proc/}"
          pid="''${pid%/environ}"
          [ "$(stat --format=%u "/proc/$pid" 2>/dev/null || true)" = "$UID" ] || continue
          while IFS= read -r -d $'\0' entry; do
            case "$entry" in
              SteamAppId=*|SteamGameId=*)
                value="''${entry#*=}"
                if [[ "$value" =~ ^[0-9]+$ && ! "$value" =~ ^0+$ ]]; then
                  printf '%s\n' "$pid"
                  break
                fi
                ;;
            esac
          done <"$environ_file"
        done
      }

      process_starttime() {
        local pid="$1"
        local stat_line stat_tail
        local -a stat_fields=()

        [ -r "/proc/$pid/stat" ] || return 1
        IFS= read -r stat_line <"/proc/$pid/stat" || return 1
        stat_tail="''${stat_line##*) }"
        read -r -a stat_fields <<<"$stat_tail"
        [ "''${#stat_fields[@]}" -gt 19 ] || return 1
        [[ "''${stat_fields[19]}" =~ ^[0-9]+$ ]] || return 1
        printf '%s\n' "''${stat_fields[19]}"
      }

      refresh_steam_game_registry() {
        local changed child_pid child_starttime child_uid parent_pid pid recorded_starttime
        local root_pid root_starttime temporary_file
        local -A game_process_set=()

        if [ -r "$game_process_registry" ]; then
          while read -r pid recorded_starttime; do
            [[ "$pid" =~ ^[0-9]+$ && "$recorded_starttime" =~ ^[0-9]+$ ]] || continue
            if [ "$(process_starttime "$pid" 2>/dev/null || true)" = "$recorded_starttime" ]; then
              game_process_set["$pid"]="$recorded_starttime"
            fi
          done <"$game_process_registry"
        fi

        while IFS= read -r root_pid; do
          [ -n "$root_pid" ] || continue
          root_starttime="$(process_starttime "$root_pid" 2>/dev/null || true)"
          [ -n "$root_starttime" ] && game_process_set["$root_pid"]="$root_starttime"
        done < <(steam_game_roots)

        changed=true
        while [ "$changed" = true ]; do
          changed=false
          while read -r child_pid parent_pid; do
            [ -n "''${game_process_set[$parent_pid]+x}" ] || continue
            [ -z "''${game_process_set[$child_pid]+x}" ] || continue
            child_uid="$(stat --format=%u "/proc/$child_pid" 2>/dev/null || true)"
            [ "$child_uid" = "$UID" ] || continue
            child_starttime="$(process_starttime "$child_pid" 2>/dev/null || true)"
            [ -n "$child_starttime" ] || continue
            game_process_set["$child_pid"]="$child_starttime"
            changed=true
          done < <(ps -e -o pid=,ppid=)
        done

        temporary_file="$game_process_registry.$$"
        if [ "''${#game_process_set[@]}" -gt 0 ]; then
          for pid in "''${!game_process_set[@]}"; do
            printf '%s %s\n' "$pid" "''${game_process_set[$pid]}"
          done | sort --numeric-sort >"$temporary_file"
        else
          : >"$temporary_file"
        fi
        mv "$temporary_file" "$game_process_registry"
      }

      steam_game_pids() {
        local pid recorded_starttime

        [ -r "$game_process_registry" ] || return 0
        while read -r pid recorded_starttime; do
          [[ "$pid" =~ ^[0-9]+$ && "$recorded_starttime" =~ ^[0-9]+$ ]] || continue
          if [ "$(process_starttime "$pid" 2>/dev/null || true)" = "$recorded_starttime" ]; then
            printf '%s\n' "$pid"
          fi
        done <"$game_process_registry"
      }

      steam_game_pids_json() {
        steam_game_pids \
          | jq --raw-input --slurp 'split("\n") | map(select(length > 0) | tonumber)'
      }

      # shellcheck disable=SC2329 # Invoked by the EXIT trap through cleanup.
      signal_steam_game_pids() {
        local signal="$1"
        local game_pid

        while IFS= read -r game_pid; do
          [ -n "$game_pid" ] || continue
          kill "-$signal" "$game_pid" >/dev/null 2>&1 || true
        done < <(steam_game_pids)
      }

      # shellcheck disable=SC2329 # Invoked by the EXIT trap through cleanup.
      refresh_and_signal_steam_games() {
        local signal="$1"

        refresh_steam_game_registry
        signal_steam_game_pids "$signal"
      }

      steam_games_are_running() {
        local game_pid

        while IFS= read -r game_pid; do
          if [ -n "$game_pid" ]; then
            return 0
          fi
        done < <(steam_game_pids)
        return 1
      }

      # shellcheck disable=SC2329 # Invoked by the EXIT trap through cleanup.
      remove_process_files() {
        rm -f \
          "$game_process_registry" \
          "$game_process_registry.$$" \
          "$stream_pids_file" \
          "$stream_pids_file.$$"
      }

      clear_game_registry() {
        rm -f "$game_process_registry" "$game_process_registry.$$"
      }

      initialize_game_registry() {
        clear_game_registry
        refresh_steam_game_registry
      }

      # shellcheck disable=SC2329 # Invoked by the EXIT trap through cleanup.
      terminate_steam_games() {
        refresh_and_signal_steam_games TERM
        for _ in {1..30}; do
          sleep 0.1
          refresh_steam_game_registry
          if ! steam_games_are_running; then
            return
          fi
          signal_steam_game_pids TERM
        done

        refresh_and_signal_steam_games KILL
      }

      steam_game_registry_is_empty() {
        if steam_games_are_running; then
          return 1
        fi
        return 0
      }

      write_stream_pids() {
        local temporary_file

        refresh_steam_game_registry
        temporary_file="$stream_pids_file.$$"
        {
          steam_pids
          steam_game_pids
        } | sort --numeric-sort --unique >"$temporary_file"
        mv "$temporary_file" "$stream_pids_file"
      }

      steam_ready() {
        # shellcheck disable=SC2016 # The nested shell expands its positional argument.
        [ -p "$HOME/.steam/steam.pipe" ] \
          && timeout --signal=KILL 0.25 \
            ${lib.getExe pkgs.bash} -c 'exec 3>"$1"' bash "$HOME/.steam/steam.pipe"
      }

      stream_workspace_is_active() {
        hyprctl monitors -j \
          | jq --exit-status \
            --arg output "$stream_output" \
            --arg workspace "$stream_workspace" \
            'any(.[]; .name == $output and .activeWorkspace.name == $workspace)' \
            >/dev/null
      }

      activate_stream_workspace() {
        local cursor cursor_x cursor_y local_monitor

        local_monitor="$(hyprctl activeworkspace -j | jq --raw-output '.monitor // empty')"
        cursor="$(hyprctl cursorpos -j)"
        cursor_x="$(printf '%s' "$cursor" | jq --raw-output '.x')"
        cursor_y="$(printf '%s' "$cursor" | jq --raw-output '.y')"
        [ -n "$local_monitor" ] || return 1

        hyprctl dispatch moveworkspacetomonitor \
          "$stream_workspace_selector" "$stream_output" >/dev/null
        hyprctl --batch \
          "dispatch workspace $stream_workspace_selector ; dispatch focusmonitor $local_monitor ; dispatch movecursor $cursor_x $cursor_y" \
          >/dev/null
        stream_workspace_is_active
      }

      steam_big_picture_is_open() {
        hyprctl clients -j \
          | jq --exit-status \
            --arg title "$big_picture_title" \
            'any(.[]; .class == "steam" and .title == $title)' \
            >/dev/null
      }

      move_stream_windows() {
        local address

        hyprctl clients -j \
          | jq --raw-output \
            --arg title "$big_picture_title" \
            --argjson game_pids "$(steam_game_pids_json)" \
            '.[]
              | select(
                  (.class == "steam" and .title == $title)
                  or (.pid as $pid | $game_pids | index($pid))
                )
              | .address' \
          | while IFS= read -r address; do
              [ -n "$address" ] || continue
              hyprctl dispatch movetoworkspacesilent \
                "$stream_workspace_selector,address:$address" >/dev/null 2>&1 || true
            done
      }

      # shellcheck disable=SC2329 # Invoked by the EXIT trap through cleanup.
      restore_windows() {
        local address workspace

        [ -n "$snapshot_file" ] && [ -s "$snapshot_file" ] || return
        jq --raw-output '.[] | [.address, .workspace] | @tsv' "$snapshot_file" \
          | while IFS=$'\t' read -r address workspace; do
              if hyprctl clients -j \
                | jq --exit-status --arg address "$address" \
                  'any(.[]; .address == $address)' >/dev/null; then
                hyprctl dispatch movetoworkspacesilent \
                  "$workspace,address:$address" >/dev/null 2>&1 || true
              fi
            done
      }

      # shellcheck disable=SC2329 # Invoked by the EXIT trap through cleanup.
      close_stream_windows() {
        local address

        hyprctl clients -j \
          | jq --raw-output \
            --arg title "$big_picture_title" \
            --argjson game_pids "$(steam_game_pids_json)" \
            '.[]
              | select(
                  (.class == "steam" and .title == $title)
                  or (.pid as $pid | $game_pids | index($pid))
                )
              | .address' \
          | while IFS= read -r address; do
              [ -n "$address" ] || continue
              hyprctl dispatch closewindow "address:$address" >/dev/null 2>&1 || true
            done
      }

      # shellcheck disable=SC2329 # Invoked by the EXIT trap through cleanup.
      restore_audio() {
        local input_index original_sink process_id target_sink

        [ -n "$default_sink" ] || return
        pactl --format=json list sink-inputs \
          | jq --raw-output \
            '.[] | [.index, (.properties["application.process.id"] // "")] | @tsv' \
          | while IFS=$'\t' read -r input_index process_id; do
              if [[ "$process_id" =~ ^[0-9]+$ ]] \
                && process_belongs_to_steam "/proc/$process_id/cgroup"; then
                original_sink="$(
                  jq --raw-output \
                    --argjson index "$input_index" \
                    --argjson pid "$process_id" \
                    'first(.[] | select(.index == $index and .pid == $pid) | .sink) // empty' \
                    "$audio_snapshot_file"
                )"
                target_sink="''${original_sink:-$default_sink}"
                pactl move-sink-input "$input_index" "$target_sink" \
                  >/dev/null 2>&1 || true
              fi
            done
      }

      # shellcheck disable=SC2329 # Registered below as the EXIT trap.
      cleanup() {
        trap - EXIT
        trap "" INT TERM HUP
        if [ "$cleaned_up" = true ]; then
          return
        fi
        cleaned_up=true

        if [ "$lease_active" = true ]; then
          if [ -n "$router_pid" ]; then
            kill "$router_pid" >/dev/null 2>&1 || true
            wait "$router_pid" >/dev/null 2>&1 || true
            router_pid=""
          fi

          terminate_steam_games

          timeout --kill-after=1s 3s \
            "$steam_command" steam://close/bigpicture >/dev/null 2>&1 || true
          sleep 0.5
          close_stream_windows || true
          restore_windows || true
          restore_audio || true
        fi

        rm -f \
          "$disconnect_marker" \
          "$audio_snapshot_file" \
          "$snapshot_file"
        remove_process_files
        flock --unlock 9 >/dev/null 2>&1 || true
        exec 9>&-
      }

      exec 9>"$session_lock"
      if ! flock --nonblock 9; then
        printf 'Sunshine session refused: another streaming session owns the session lock.\n' >&2
        exit 1
      fi
      trap cleanup EXIT
      trap 'exit 0' INT TERM HUP
      rm -f "$disconnect_marker"
      umask 077

      if systemctl --user --quiet is-active "$pegasus_unit"; then
        printf 'Sunshine session refused: %s is already active.\n' "$pegasus_unit" >&2
        exit 1
      fi

      case "$SUNSHINE_CLIENT_WIDTH"x"$SUNSHINE_CLIENT_HEIGHT" in
        1280x720|1920x1080|3840x2160) ;;
        *)
          printf 'Unsupported Moonlight resolution: %sx%s. Expected 720p, 1080p, or 4K.\n' \
            "$SUNSHINE_CLIENT_WIDTH" "$SUNSHINE_CLIENT_HEIGHT" >&2
          exit 1
          ;;
      esac
      case "$SUNSHINE_CLIENT_FPS" in
        30|60) ;;
        *)
          printf 'Unsupported Moonlight frame rate: %s. Expected 30 or 60 FPS.\n' \
            "$SUNSHINE_CLIENT_FPS" >&2
          exit 1
          ;;
      esac

      systemctl --user start "$steam_unit"
      ready_checks=0
      for _ in {1..600}; do
        [ ! -e "$disconnect_marker" ] || exit 0
        steam_cgroup="$(
          systemctl --user show --property=ControlGroup --value "$steam_unit" 2>/dev/null
        )"
        if systemctl --user --quiet is-active "$steam_unit" \
          && [ -n "$steam_cgroup" ] \
          && [ -n "$(steam_pids)" ] \
          && steam_ready; then
          ready_checks=$((ready_checks + 1))
          if [ "$ready_checks" -ge 3 ]; then
            break
          fi
        else
          ready_checks=0
        fi
        sleep 0.1
      done
      if ! systemctl --user --quiet is-active "$steam_unit" \
        || [ -z "$steam_cgroup" ] \
        || [ -z "$(steam_pids)" ] \
        || [ "$ready_checks" -lt 3 ]; then
        printf 'Sunshine session refused: %s did not become ready.\n' "$steam_unit" >&2
        exit 1
      fi

      initialize_game_registry
      if ! steam_game_registry_is_empty; then
        printf 'Sunshine session refused: a Steam game is already running.\n' >&2
        exit 1
      fi

      audio_snapshot_file="$(mktemp "$XDG_RUNTIME_DIR/sunshine-steam-audio.XXXXXX")"
      snapshot_file="$(mktemp "$XDG_RUNTIME_DIR/sunshine-steam-windows.XXXXXX")"
      default_sink="$(pactl get-default-sink)"
      pactl --format=json list sink-inputs \
        | jq --argjson pids "$(steam_pids_json)" \
          '[.[]
            | (.properties["application.process.id"] // "" | tonumber?) as $pid
            | select($pid != null and ($pids | index($pid)))
            | { index, sink, pid: $pid }
          ]' >"$audio_snapshot_file"
      hyprctl clients -j \
        | jq --argjson pids "$(steam_pids_json)" \
          '[.[]
            | select(.pid as $pid | $pids | index($pid))
            | {
                address,
                workspace: (
                  if .workspace.id > 0 then
                    .workspace.id | tostring
                  elif .workspace.name | startswith("special:") then
                    .workspace.name
                  else
                    "name:" + .workspace.name
                  end
                )
              }
          ]' >"$snapshot_file"
      lease_active=true

      write_stream_pids
      ${lib.getExe streamAudioRouter} "$steam_unit" "$stream_pids_file" &
      router_pid=$!
      "$steam_command" steam://open/gamepadui >/dev/null

      big_picture_ready=false
      for _ in {1..200}; do
        [ ! -e "$disconnect_marker" ] || exit 0
        if steam_big_picture_is_open; then
          big_picture_ready=true
          break
        fi
        systemctl --user --quiet is-active "$steam_unit" || break
        sleep 0.1
      done
      if [ "$big_picture_ready" != true ]; then
        printf 'Steam Big Picture did not open before the launch timeout.\n' >&2
        exit 1
      fi

      move_stream_windows
      if ! activate_stream_workspace; then
        printf 'Unable to activate Steam streaming workspace %s.\n' "$stream_workspace" >&2
        exit 1
      fi

      while systemctl --user --quiet is-active "$steam_unit"; do
        [ ! -e "$disconnect_marker" ] || exit 0
        write_stream_pids
        move_stream_windows
        if ! stream_workspace_is_active; then
          activate_stream_workspace || true
        fi
        sleep 0.25
      done

      printf 'Persistent Steam service stopped during streaming.\n' >&2
      exit 1
    '';
  };

  mkSessionController =
    {
      name,
      unit,
      otherUnit,
      environmentFile,
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.hyprland
        pkgs.jq
        pkgs.systemd
        pkgs.util-linux
      ];
      text = ''
        readonly session_unit=${lib.escapeShellArg unit}
        readonly other_unit=${lib.escapeShellArg otherUnit}
        readonly stream_output=${lib.escapeShellArg cfg.display.connector}
        readonly stream_workspace=${lib.escapeShellArg cfg.display.workspace}
        readonly stream_workspace_selector=${lib.escapeShellArg workspaceSelector}
        readonly disconnect_marker="$XDG_RUNTIME_DIR/${disconnectMarker}"
        readonly session_environment="$XDG_RUNTIME_DIR/${environmentFile}"
        readonly session_lock="$XDG_RUNTIME_DIR/sunshine-streaming-session.lock"

        cleanup() {
          trap - EXIT
          trap "" INT TERM HUP
          systemctl --user stop "$session_unit" >/dev/null 2>&1 || true
          rm -f "$disconnect_marker" "$session_environment"
        }

        stream_workspace_is_active() {
          hyprctl monitors -j \
            | jq --exit-status \
              --arg output "$stream_output" \
              --arg workspace "$stream_workspace" \
              'any(.[]; .name == $output and .activeWorkspace.name == $workspace)' \
              >/dev/null
        }

        activate_stream_workspace() {
          local cursor cursor_x cursor_y local_monitor

          local_monitor="$(hyprctl activeworkspace -j | jq --raw-output '.monitor // empty')"
          cursor="$(hyprctl cursorpos -j)"
          cursor_x="$(printf '%s' "$cursor" | jq --raw-output '.x')"
          cursor_y="$(printf '%s' "$cursor" | jq --raw-output '.y')"

          if [ -z "$local_monitor" ]; then
            printf 'Unable to determine the focused local monitor.\n' >&2
            return 1
          fi

          hyprctl --batch \
            "dispatch workspace $stream_workspace_selector ; dispatch focusmonitor $local_monitor ; dispatch movecursor $cursor_x $cursor_y" \
            >/dev/null

          stream_workspace_is_active
        }

        exec 9>"$session_lock"
        if ! flock --nonblock 9; then
          printf 'Sunshine session refused: another streaming session owns the session lock.\n' >&2
          exit 1
        fi

        if systemctl --user --quiet is-active "$other_unit"; then
          printf 'Sunshine session refused: %s is already active.\n' "$other_unit" >&2
          exit 1
        fi

        trap cleanup EXIT
        trap 'exit 0' INT TERM HUP
        rm -f "$disconnect_marker"

        case "$SUNSHINE_CLIENT_WIDTH"x"$SUNSHINE_CLIENT_HEIGHT" in
          1280x720|1920x1080|3840x2160) ;;
          *)
            printf 'Unsupported Moonlight resolution: %sx%s. Expected 720p, 1080p, or 4K.\n' \
              "$SUNSHINE_CLIENT_WIDTH" "$SUNSHINE_CLIENT_HEIGHT" >&2
            exit 1
            ;;
        esac

        case "$SUNSHINE_CLIENT_FPS" in
          30|60) ;;
          *)
            printf 'Unsupported Moonlight frame rate: %s. Expected 30 or 60 FPS.\n' \
              "$SUNSHINE_CLIENT_FPS" >&2
            exit 1
            ;;
        esac

        umask 077
        printf 'SUNSHINE_CLIENT_WIDTH=%s\nSUNSHINE_CLIENT_HEIGHT=%s\nSUNSHINE_CLIENT_FPS=%s\n' \
          "$SUNSHINE_CLIENT_WIDTH" \
          "$SUNSHINE_CLIENT_HEIGHT" \
          "$SUNSHINE_CLIENT_FPS" \
          >"$session_environment"

        systemctl --user reset-failed "$session_unit" >/dev/null 2>&1 || true
        if ! systemctl --user start "$session_unit"; then
          exit 1
        fi

        gamescope_ready=false
        for _ in {1..200}; do
          [ ! -e "$disconnect_marker" ] || exit 0
          if hyprctl clients -j \
            | jq --exit-status --arg workspace "$stream_workspace" \
              'any(.[]; .class == "gamescope" and .workspace.name == $workspace)' \
              >/dev/null; then
            gamescope_ready=true
            break
          fi

          if ! systemctl --user --quiet is-active "$session_unit"; then
            break
          fi

          sleep 0.1
        done

        if [ "$gamescope_ready" != true ]; then
          printf 'Gamescope did not map to workspace %s before the launch timeout.\n' \
            "$stream_workspace" >&2
          exit 1
        fi

        if ! activate_stream_workspace; then
          exit 1
        fi

        while systemctl --user --quiet is-active "$session_unit"; do
          [ ! -e "$disconnect_marker" ] || exit 0
          if ! stream_workspace_is_active; then
            activate_stream_workspace || true
          fi
          sleep 1
        done

        if systemctl --user --quiet is-failed "$session_unit"; then
          exit 1
        fi
      '';
    };

  pegasusController = mkSessionController {
    name = "sunshine-pegasus-controller";
    unit = pegasusUnit;
    otherUnit = steamUnit;
    environmentFile = pegasusEnvironmentFile;
  };
in
{
  options.workstation.sunshine = {
    enable = lib.mkEnableOption "Sunshine game streaming";

    display = {
      connector = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9_.:-]+";
        default = "HDMI-A-1";
        description = "Hyprland connector name of the dummy streaming display.";
      };

      sunshineId = lib.mkOption {
        type = lib.types.ints.unsigned;
        description = ''
          Numeric display ID reported by Sunshine for the dummy streaming
          display. This is not necessarily the Hyprland monitor ID.
        '';
      };

      refreshRate = lib.mkOption {
        type = lib.types.numbers.positive;
        default = 60;
        description = "Exact refresh rate advertised by the fixed 4K streaming display.";
      };

      position = lib.mkOption {
        type = lib.types.strMatching "-?[0-9]+x-?[0-9]+";
        default = "10000x10000";
        description = ''
          Hyprland position of the dummy display. A distant diagonal position
          creates an empty gap that prevents ordinary relative pointer movement
          from crossing onto it.
        '';
      };

      workspace = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9_.:-]+";
        default = "99";
        description = "Hyprland workspace reserved for game streaming.";
      };

      notificationOutput = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9_.:-]+";
        default = "DP-1";
        description = "Local output where Mako shows notifications while streaming.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.workstation.display.enable;
        message = "workstation.sunshine requires workstation.display.enable";
      }
      {
        assertion = config.services.pipewire.enable && config.services.pipewire.pulse.enable;
        message = "workstation.sunshine requires PipeWire with PulseAudio compatibility";
      }
    ];

    hardware.uinput.enable = true;

    programs = {
      gamescope = {
        enable = true;
        capSysNice = true;
      };
      steam = {
        enable = true;
        package = pkgs.steam.override {
          extraPkgs = pkgs: [ pkgs.pulseaudio ];
          extraPreBwrapCmds = ''
            ignored+=(/mnt)
          '';
          extraBwrapArgs = [ "--dir /mnt" ];
          buildFHSEnv = pkgs.buildFHSEnv.override {
            bubblewrap = "${config.security.wrapperDir}/..";
          };
        };
      };
    };

    security.wrappers.bwrap = {
      owner = "root";
      group = "root";
      source = "${pkgs.bubblewrap}/bin/bwrap";
      setuid = true;
    };

    environment.systemPackages = [ pkgs.lutris ];

    services = {
      pipewire.extraConfig.pipewire."91-sunshine-game-audio" = {
        "context.objects" = [
          {
            factory = "adapter";
            args = {
              "factory.name" = "support.null-audio-sink";
              "node.name" = audioSinkName;
              "node.description" = "Sunshine Game Audio";
              "node.virtual" = true;
              "media.class" = "Audio/Sink";
              "priority.driver" = 0;
              "priority.session" = -1000;
              "sunshine.exclude-default" = true;
              "audio.channels" = 8;
              "audio.rate" = 48000;
              "audio.position" = [
                "FL"
                "FR"
                "FC"
                "LFE"
                "RL"
                "RR"
                "SL"
                "SR"
              ];
              "monitor.channel-volumes" = true;
              "object.linger" = true;
            };
          }
        ];
      };

      pipewire.wireplumber = {
        extraConfig."91-sunshine-game-audio" = {
          "stream.rules" = [
            {
              matches = [
                {
                  "media.class" = "Stream/Output/Audio";
                  "sunshine.audio-route" = audioSinkName;
                }
              ];
              actions."update-props" = {
                "channelmix.upmix" = false;
                "node.dont-fallback" = true;
                "state.restore-target" = false;
                "target.object" = audioSinkName;
              };
            }
          ];

          "wireplumber.components" = [
            {
              name = "sunshine/filter-default-nodes.lua";
              type = "script/lua";
              provides = "custom.sunshine-filter-default-nodes";
            }
          ];

          "wireplumber.profiles".main."custom.sunshine-filter-default-nodes" = "required";
        };

        extraScripts."sunshine/filter-default-nodes.lua" = ''
          SimpleEventHook {
            name = "sunshine/filter-default-nodes",
            before = {
              "default-nodes/find-selected-default-node",
              "default-nodes/find-stored-default-node",
              "default-nodes/find-best-default-node",
            },
            interests = {
              EventInterest {
                Constraint { "event.type", "=", "select-default-node" },
              },
            },
            execute = function (event)
              local available_nodes = event:get_data ("available-nodes")
              available_nodes = available_nodes and available_nodes:parse ()
              if not available_nodes then
                return
              end

              local filtered_nodes = {}
              local selected_node = event:get_data ("selected-node")
              local selected_node_excluded = false
              for _, node_props in ipairs (available_nodes) do
                if tostring (node_props ["sunshine.exclude-default"]) == "true" then
                  selected_node_excluded = selected_node_excluded or
                      node_props ["node.name"] == selected_node
                else
                  table.insert (filtered_nodes, Json.Object (node_props))
                end
              end

              event:set_data ("available-nodes", Json.Array (filtered_nodes))
              if selected_node_excluded then
                event:set_data ("selected-node", nil)
                event:set_data ("selected-node-priority", nil)
                event:set_data ("selected-route-priority", nil)
              end
            end
          }:register ()
        '';
      };

      sunshine = {
        enable = true;
        package = sunshinePackage;
        autoStart = true;
        capSysAdmin = true;
        openFirewall = true;

        settings = {
          capture = "kms";
          encoder = "nvenc";
          output_name = cfg.display.sunshineId;
          audio_sink = audioSinkName;
          controller = true;
          keyboard = false;
          mouse = false;
          system_tray = false;
        };

        applications.apps = [
          {
            name = "Pegasus";
            cmd = lib.getExe pegasusController;
            image-path = "${pkgs.pegasus-frontend}/share/icons/hicolor/128x128/apps/org.pegasus_frontend.Pegasus.png";
            auto-detach = false;
            wait-all = true;
            exit-timeout = 15;
            prep-cmd = [
              {
                do = "${systemctl} --user stop ${steamUnit}";
                undo = "${systemctl} --user start ${steamUnit}";
              }
              {
                do = "";
                undo = "${systemctl} --user stop ${pegasusUnit}";
              }
            ];
          }
          {
            name = "Steam Big Picture";
            cmd = lib.getExe steamStreamSession;
            image-path = "${pkgs.steam}/share/icons/hicolor/256x256/apps/steam.png";
            auto-detach = false;
            wait-all = true;
            exit-timeout = 30;
          }
        ];
      };
    };

    home-manager.sharedModules = [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          retroarchRootDir = "${config.home.homeDirectory}/syncthing/RetroArch";
          retroarch = lib.getExe config.programs.retroarch.finalPackage;
        in
        {
          user.desktop.hyprland.excludedOutputs = [ cfg.display.connector ];
          user.desktop.hyprland.ignoredWorkspaces = [ cfg.display.workspace ];

          user.gui = {
            pegasus = {
              enable = true;
              gameDirectories = [ "${retroarchRootDir}/roms" ];
              settings = {
                "general.fullscreen" = true;
                "general.input-mouse-support" = false;
                "providers.lutris.enabled" = true;
                "providers.steam.enabled" = false;
              };
              collections = [
                {
                  name = "Game Boy Advance";
                  shortname = "gba";
                  extensions = [ "gba" ];
                  launch = ''${retroarch} -L ${pkgs.libretro.mgba}/lib/retroarch/cores/mgba_libretro.so "{file.path}"'';
                  directories = [ "${retroarchRootDir}/roms/Nintendo - Game Boy Advance" ];
                }
                {
                  name = "Super Nintendo";
                  shortname = "snes";
                  extensions = [
                    "smc"
                    "sfc"
                  ];
                  launch = ''${retroarch} -L ${pkgs.libretro.snes9x}/lib/retroarch/cores/snes9x_libretro.so "{file.path}"'';
                  directories = [
                    "${retroarchRootDir}/roms/Nintendo - Super Nintendo Entertainment System"
                  ];
                }
                {
                  name = "Nintendo 64";
                  shortname = "n64";
                  extensions = [
                    "z64"
                    "n64"
                    "v64"
                  ];
                  launch = ''${retroarch} -L ${pkgs.libretro.mupen64plus}/lib/retroarch/cores/mupen64plus_next_libretro.so "{file.path}"'';
                  directories = [ "${retroarchRootDir}/roms/Nintendo - Nintendo 64" ];
                }
              ];
            };

            retroarch = {
              enable = true;
              rootDir = retroarchRootDir;
            };
          };

          programs.retroarch.settings.audio_driver = "pulse";

          wayland.windowManager.hyprland.settings = lib.mkIf config.user.desktop.hyprland.enable {
            monitor = [
              "${cfg.display.connector},${toString outerWidth}x${toString outerHeight}@${toString cfg.display.refreshRate},${cfg.display.position},1"
            ];
            workspace = [
              "${workspaceSelector}, monitor:${cfg.display.connector}, default:true, persistent:true, gapsout:0, gapsin:0"
            ];
            windowrulev2 = [
              "workspace ${workspaceSelector} silent,class:^(gamescope)$"
              "noinitialfocus,class:^(gamescope)$"
              "bordersize 0,class:^(gamescope)$"
              "rounding 0,class:^(gamescope)$"
            ];
          };

          systemd.user.services.sunshine-pegasus-session = lib.mkIf config.user.desktop.hyprland.enable {
            Unit = {
              Description = "Gamescope Pegasus streaming session";
              Requires = [ "hyprland-session.target" ];
              After = [ "hyprland-session.target" ];
              PartOf = [ "hyprland-session.target" ];
            };
            Service = {
              Type = "simple";
              ExecStart = lib.getExe pegasusSession;
              ExecStopPost = "${lib.getExe' pkgs.coreutils "rm"} -f %t/${pegasusEnvironmentFile}";
              Environment = lib.mapAttrsToList (name: value: "${name}=${value}") streamEnvironment;
              EnvironmentFile = "-%t/${pegasusEnvironmentFile}";
              KillMode = "control-group";
              TimeoutStopSec = "12s";
            };
          };

          systemd.user.services.sunshine-steam = lib.mkIf config.user.desktop.hyprland.enable {
            Unit = {
              Description = "Persistent Steam client for Sunshine";
              Requires = [
                "hyprland-session.target"
                "sunshine.service"
              ];
              After = [
                "hyprland-session.target"
                "sunshine.service"
              ];
              PartOf = [
                "hyprland-session.target"
                "sunshine.service"
              ];
            };
            Service = {
              Type = "simple";
              ExecStart = "${lib.getExe steamPackage} -silent";
              ExecStop = "${lib.getExe steamPackage} -shutdown";
              Environment = [
                "PIPEWIRE_PROPS={state.restore-target=false}"
                "PULSE_PROP=state.restore-target=false"
              ];
              KillMode = "control-group";
              Restart = "always";
              RestartSec = "5s";
              TimeoutStopSec = "15s";
            };
            Install.WantedBy = [ "sunshine.service" ];
          };

          systemd.user.services.mako = lib.mkIf config.user.desktop.hyprland.enable {
            Service.ExecStart = lib.mkForce (
              "${lib.getExe pkgs.mako} --output ${lib.escapeShellArg cfg.display.notificationOutput}"
            );
          };
        }
      )
    ];
  };
}
