{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.cli.sops-menu;

  sops-menu = pkgs.writeShellApplication {
    name = "sops-menu";
    runtimeInputs = with pkgs; [
      sops
      yq-go
      fzf
      coreutils
    ];
    text = ''
      # fzf password finder for sops-encrypted YAML secrets.
      #
      # This repo uses it for `secrets/users/<username>.yaml`. `sops-menu`
      # decrypts the file on demand via `sops -d`, so the user must have
      # their SSH key available locally or through a forwarded agent.
      set -euo pipefail

      DEFAULT_SECRETS_FILE=${
        lib.escapeShellArg (if cfg.secretsFile == null then "" else toString cfg.secretsFile)
      }
      SECRETS_FILE="$DEFAULT_SECRETS_FILE"
      if [[ -n "''${SOPS_SECRETS_FILE:-}" ]]; then
          SECRETS_FILE="$SOPS_SECRETS_FILE"
      fi
      CLIP_TIMEOUT=15
      MODE="cli"
      TMUX_PANE=""
      HYPRLAND_WINDOW=""
      PREVIEW_NAME=""
      tmux_buffer=""

      cleanup_tmux_buffer() {
          if [[ -n "$tmux_buffer" ]]; then
              tmux delete-buffer -b "$tmux_buffer" >/dev/null 2>&1 || true
          fi
      }

      trap cleanup_tmux_buffer EXIT

      usage() {
          cat <<'HELP'
      Usage: sops-menu [--file PATH] [--mode cli|tmux|hyprland]
                       [--tmux-pane PANE] [--hyprland-window ADDRESS]

        --file PATH               Override SOPS_SECRETS_FILE
        --mode MODE               Delivery mode: cli, tmux, hyprland
        --tmux-pane PANE          Target pane for tmux mode
        --hyprland-window ADDR    Target window address for Hyprland mode

      CLI keybindings:
        Alt+u      Copy username to clipboard (OSC 52)
        Alt+p      Copy password to clipboard (OSC 52)
        Alt+l      Copy URL to clipboard (OSC 52)
        Alt+o      Copy OTP to clipboard (OSC 52)
        Shift+U    Print username
        Shift+P    Print password
        Shift+L    Print URL
        Shift+O    Print OTP

      Popup keybindings:
        Alt+u      Insert username
        Alt+p      Insert password
        Alt+l      Insert URL
        Alt+o      Insert OTP
      HELP
      }

      while [[ $# -gt 0 ]]; do
          case $1 in
              --file)
                  if [[ -z "''${2:-}" ]]; then
                      echo "Missing value for --file" >&2
                      exit 1
                  fi
                  SECRETS_FILE="$2"
                  shift 2
                  ;;
              --mode)
                  if [[ -z "''${2:-}" ]]; then
                      echo "Missing value for --mode" >&2
                      exit 1
                  fi
                  MODE="$2"
                  shift 2
                  ;;
              --tmux-pane)
                  if [[ -z "''${2:-}" ]]; then
                      echo "Missing value for --tmux-pane" >&2
                      exit 1
                  fi
                  TMUX_PANE="$2"
                  shift 2
                  ;;
              --hyprland-window)
                  if [[ -z "''${2:-}" ]]; then
                      echo "Missing value for --hyprland-window" >&2
                      exit 1
                  fi
                  HYPRLAND_WINDOW="$2"
                  shift 2
                  ;;
              --preview-notes)
                  if [[ -z "''${2:-}" ]]; then
                      echo "Missing value for --preview-notes" >&2
                      exit 1
                  fi
                  PREVIEW_NAME="$2"
                  shift 2
                  ;;
              -h|--help)
                  usage
                  exit 0
                  ;;
              *) echo "Unknown option: $1" >&2; exit 1 ;;
          esac
      done

      case "$MODE" in
          cli|tmux|hyprland) ;;
          *)
              echo "sops-menu: Unknown mode: $MODE" >&2
              exit 1
              ;;
      esac

      if [[ "$MODE" == "tmux" && -z "$TMUX_PANE" ]]; then
          echo "sops-menu: --tmux-pane is required in tmux mode" >&2
          exit 1
      fi

      if [[ "$MODE" == "hyprland" && -z "$HYPRLAND_WINDOW" ]]; then
          echo "sops-menu: --hyprland-window is required in Hyprland mode" >&2
          exit 1
      fi

      if [[ -z "$SECRETS_FILE" ]]; then
          echo "sops-menu: Secrets file not set. Use --file or set SOPS_SECRETS_FILE." >&2
          exit 1
      fi
      if [[ ! -f "$SECRETS_FILE" ]]; then
          echo "sops-menu: Secrets file not found: $SECRETS_FILE" >&2
          exit 1
      fi

      load_yaml() {
          sops -d "$SECRETS_FILE"
      }

      yaml=$(load_yaml) || {
          echo "sops-menu: Failed to load secrets" >&2
          exit 1
      }

      # Validate schema
      entries_type=$(printf '%s' "$yaml" | yq -r '.entries | type')
      if [[ "$entries_type" != "!!seq" ]]; then
          echo "sops-menu: Invalid schema: .entries must be a list" >&2
          exit 1
      fi
      missing=$(printf '%s' "$yaml" | yq -r \
          '.entries[] | select(.name == null or .username == null or .password == null) | (.name // "[missing name]")')
      if [[ -n "$missing" ]]; then
          echo "sops-menu: Missing required fields in: $missing" >&2
          exit 1
      fi

      names=$(printf '%s' "$yaml" | yq -r '.entries[].name')

      get_field() {
          printf '%s' "$yaml" | ENTRY_NAME="$1" ENTRY_FIELD="$2" \
              yq -r '.entries[] | select(.name == strenv(ENTRY_NAME)) | .[strenv(ENTRY_FIELD)] // ""'
      }

      print_notes() {
          local notes

          notes=$(get_field "$1" notes)
          if [[ -n "$notes" ]]; then
              printf '%s\n' "$notes"
          else
              printf 'No notes\n'
          fi
      }

      # Copy to client clipboard via OSC 52 escape sequence
      osc52_copy() {
          local text="$1"
          [[ -z "$text" ]] && return
          local encoded
          encoded=$(printf '%s' "$text" | base64 | tr -d '\n')
          printf '\033]52;c;%s\a' "$encoded"
          echo "Copied to clipboard (''${CLIP_TIMEOUT}s)" >&2
          # Clear clipboard after timeout
          ( sleep "$CLIP_TIMEOUT" && printf '\033]52;c;\a' ) &
      }

      tmux_paste() {
          local text="$1"

          [[ -z "$text" ]] && return

          if ! command -v tmux >/dev/null 2>&1; then
              echo "sops-menu: tmux is required in tmux mode" >&2
              exit 1
          fi

          tmux_buffer="sops-menu-$$"
          printf '%s' "$text" | tmux load-buffer -b "$tmux_buffer" -
          tmux paste-buffer -d -b "$tmux_buffer" -t "$TMUX_PANE"
          tmux_buffer=""
      }

      hyprland_focus_original_window() {
          if ! command -v hyprctl >/dev/null 2>&1; then
              echo "sops-menu: hyprctl is required in Hyprland mode" >&2
              exit 1
          fi

          hyprctl dispatch focuswindow "address:$HYPRLAND_WINDOW" >/dev/null
          sleep 0.1
      }

      hyprland_type_text() {
          local text="$1"

          [[ -z "$text" ]] && return

          if ! command -v wtype >/dev/null 2>&1; then
              echo "sops-menu: wtype is required in Hyprland mode" >&2
              exit 1
          fi

          printf '%s' "$text" | wtype -
      }

      hyprland_press_key() {
          if ! command -v wtype >/dev/null 2>&1; then
              echo "sops-menu: wtype is required in Hyprland mode" >&2
              exit 1
          fi

          wtype -P "$1" -p "$1"
      }

      if [[ -n "$PREVIEW_NAME" ]]; then
          print_notes "$PREVIEW_NAME"
          exit 0
      fi

      prepare_interactive_terminal() {
          if [[ "$MODE" == "cli" ]]; then
              return
          fi

          # Clear any lingering passphrase prompt before fzf draws.
          printf '\033[2J\033[H'
      }

      fzf_header="Alt+u/p/l/o: copy | Shift: print"
      if [[ "$MODE" == "tmux" ]]; then
          fzf_header="Alt+u/p/l/o: paste field"
      elif [[ "$MODE" == "hyprland" ]]; then
          fzf_header="Alt+u/p/l/o: insert field"
      fi

      prepare_interactive_terminal

      set +e
      result=$(printf '%s\n' "$names" | fzf \
          --prompt="Password> " \
          --ghost="" \
          --header="$fzf_header" \
          --ignore-case \
          --preview="sops-menu --file \"$SECRETS_FILE\" --preview-notes {}" \
          --expect="U,P,L,O,alt-u,alt-p,alt-l,alt-o")
      set -e

      key=$(echo "$result" | head -1)
      selected=$(echo "$result" | tail -1)
      [[ -z "$selected" ]] && exit 0

      case "$MODE:$key" in
          cli:)
              get_field "$selected" password
              ;;
          cli:U)
              get_field "$selected" username
              ;;
          cli:P)
              get_field "$selected" password
              ;;
          cli:L)
              get_field "$selected" url
              ;;
          cli:O)
              get_field "$selected" otp
              ;;
          cli:alt-u)
              osc52_copy "$(get_field "$selected" username)"
              ;;
          cli:alt-p)
              osc52_copy "$(get_field "$selected" password)"
              ;;
          cli:alt-l)
              osc52_copy "$(get_field "$selected" url)"
              ;;
          cli:alt-o)
              osc52_copy "$(get_field "$selected" otp)"
              ;;
          tmux:|tmux:P|tmux:alt-p)
              tmux_paste "$(get_field "$selected" password)"
              ;;
          tmux:U|tmux:alt-u)
              tmux_paste "$(get_field "$selected" username)"
              ;;
          tmux:L|tmux:alt-l)
              tmux_paste "$(get_field "$selected" url)"
              ;;
          tmux:O|tmux:alt-o)
              tmux_paste "$(get_field "$selected" otp)"
              ;;
          hyprland:)
              hyprland_focus_original_window
              hyprland_type_text "$(get_field "$selected" username)"
              hyprland_press_key Tab
              hyprland_type_text "$(get_field "$selected" password)"
              hyprland_press_key Return
              ;;
          hyprland:U|hyprland:alt-u)
              hyprland_focus_original_window
              hyprland_type_text "$(get_field "$selected" username)"
              ;;
          hyprland:P|hyprland:alt-p)
              hyprland_focus_original_window
              hyprland_type_text "$(get_field "$selected" password)"
              ;;
          hyprland:L|hyprland:alt-l)
              hyprland_focus_original_window
              hyprland_type_text "$(get_field "$selected" url)"
              ;;
          hyprland:O|hyprland:alt-o)
              hyprland_focus_original_window
              hyprland_type_text "$(get_field "$selected" otp)"
              ;;
      esac
    '';
  };

  sops-menu-popup = pkgs.writeShellApplication {
    name = "sops-menu-popup";
    runtimeInputs = with pkgs; [ yq-go ];
    text = ''
      set -euo pipefail

      DEFAULT_SECRETS_FILE=${
        lib.escapeShellArg (if cfg.secretsFile == null then "" else toString cfg.secretsFile)
      }

      if [[ $# -lt 1 ]]; then
          echo "Usage: sops-menu-popup <terminal> [args ...]" >&2
          exit 1
      fi

      if ! command -v hyprctl >/dev/null 2>&1; then
          echo "sops-menu-popup: hyprctl is required" >&2
          exit 1
      fi

      origin_window=$(hyprctl activewindow -j | yq -r '.address // ""')
      if [[ -z "$origin_window" || "$origin_window" == "null" ]]; then
          echo "sops-menu-popup: Failed to determine the active window" >&2
          exit 1
      fi

      cmd=("$@" -e ${lib.getExe sops-menu} --mode hyprland --hyprland-window "$origin_window")
      if [[ -n "$DEFAULT_SECRETS_FILE" ]]; then
          cmd+=(--file "$DEFAULT_SECRETS_FILE")
      fi

      exec "''${cmd[@]}"
    '';
  };
in
{
  options.user.cli.sops-menu = {
    enable = lib.mkEnableOption "sops-menu password finder";

    secretsFile = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.oneOf [
          lib.types.path
          lib.types.str
        ]
      );
      default = null;
      example = "../../secrets/users/heikov.yaml";
      description = ''
        Path to the YAML file used by sops-menu.

        In this repo, it normally points at an encrypted
        `secrets/users/<username>.yaml` file that the user decrypts on demand
        with `sops` and their SSH key/agent.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [
          sops-menu
          sops-menu-popup
        ];
      }

      (lib.mkIf (cfg.secretsFile != null) {
        home.sessionVariables = {
          SOPS_SECRETS_FILE = toString cfg.secretsFile;
        };
      })
    ]
  );
}
