{
  hostname,
  pkgs,
  ...
}:

{
  imports = [
    ../common.nix
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Home Manager — heikov user
  # ═══════════════════════════════════════════════════════════════════
  home-manager.users.heikov = import ../../../home/heikov/headless.nix;

  # ═══════════════════════════════════════════════════════════════════
  #  WSL Platform
  # ═══════════════════════════════════════════════════════════════════
  # WSL stays secret-free, so keep the user password mutable on this host.
  users.mutableUsers = true;

  wsl.defaultUser = "heikov";
  networking.hostName = hostname;

  users.users.heikov = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
  };

  # ─── Helper Commands ────────────────────────────────────────────
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "wslcopy";

      runtimeInputs = with pkgs; [
        coreutils
        findutils
        gnugrep
      ];

      text = ''
        set -euo pipefail

        clip="/mnt/c/Windows/System32/clip.exe"

        if [[ ! -x "$clip" ]]; then
          printf 'wslcopy: clip.exe is unavailable; is WSL interop enabled?\n' >&2
          exit 1
        fi

        # Use the current directory when no paths are supplied.
        if [[ "$#" -eq 0 ]]; then
          set -- .
        fi

        file_list="$(mktemp)"
        output="$(mktemp)"
        trap 'rm -f "$file_list" "$output"' EXIT

        for path in "$@"; do
          if [[ -f "$path" ]]; then
            case "$(basename -- "$path")" in
              .*|*.lock)
                continue
                ;;
            esac

            printf '%s\0' "$path" >> "$file_list"
          elif [[ -d "$path" ]]; then
            find "$path" -mindepth 1 \
              \( -type d \( \
                -name '.*' \
                -o -name node_modules \
                -o -name result \
              \) -prune \) \
              -o \( \
                -type f \
                ! -name '.*' \
                ! -name '*.lock' \
                -print0 \
              \) >> "$file_list"
          else
            printf 'wslcopy: path does not exist: %s\n' "$path" >&2
            exit 1
          fi
        done

        copied=0
        skipped=0

        while IFS= read -r -d "" file; do
          # Skip non-empty binary files silently.
          if [[ -s "$file" ]] && ! grep -Iq . "$file"; then
            ((skipped += 1))
            continue
          fi

          {
            printf '===== %s =====\n' "$file"
            cat -- "$file"
            printf '\n\n'
          } >> "$output"

          ((copied += 1))
        done < "$file_list"

        if [[ "$copied" -eq 0 ]]; then
          printf 'wslcopy: no text files found\n' >&2
          exit 1
        fi

        "$clip" < "$output"

        bytes="$(wc -c < "$output")"

        if [[ "$skipped" -gt 0 ]]; then
          printf 'Copied %d files, %d bytes; skipped %d binary files.\n' \
            "$copied" "$bytes" "$skipped" >&2
        else
          printf 'Copied %d files, %d bytes.\n' \
            "$copied" "$bytes" >&2
        fi
      '';
    })
  ];

  system.stateVersion = "25.05";
}
