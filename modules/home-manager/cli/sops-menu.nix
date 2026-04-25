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
      # fzf password finder for sops-encrypted YAML secrets (headless)
      set -euo pipefail

      SECRETS_FILE="''${SOPS_SECRETS_FILE:-}"
      CLIP_TIMEOUT=15

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
              -h|--help)
                  cat <<'HELP'
      Usage: sops-menu [--file PATH]
        --file PATH   Override SOPS_SECRETS_FILE

      Keybindings:
        Enter      Print password
        Alt+u      Copy username to clipboard (OSC 52)
        Alt+p      Copy password to clipboard (OSC 52)
        Alt+l      Copy URL to clipboard (OSC 52)
        Alt+o      Copy OTP to clipboard (OSC 52)
        Shift+U    Print username
        Shift+P    Print password
        Shift+L    Print URL
        Shift+O    Print OTP
      HELP
                  exit 0
                  ;;
              *) echo "Unknown option: $1" >&2; exit 1 ;;
          esac
      done

      if [[ -z "$SECRETS_FILE" ]]; then
          echo "sops-menu: Secrets file not set. Use --file or set SOPS_SECRETS_FILE." >&2
          exit 1
      fi
      if [[ ! -f "$SECRETS_FILE" ]]; then
          echo "sops-menu: Secrets file not found: $SECRETS_FILE" >&2
          exit 1
      fi

      yaml=$(sops -d "$SECRETS_FILE") || {
          echo "sops-menu: Failed to decrypt secrets" >&2
          exit 1
      }

      # Validate schema
      entries_type=$(echo "$yaml" | yq -r '.entries | type')
      if [[ "$entries_type" != "!!seq" ]]; then
          echo "sops-menu: Invalid schema: .entries must be a list" >&2
          exit 1
      fi
      missing=$(echo "$yaml" | yq -r \
          '.entries[] | select(.name == null or .username == null or .password == null) | (.name // "[missing name]")')
      if [[ -n "$missing" ]]; then
          echo "sops-menu: Missing required fields in: $missing" >&2
          exit 1
      fi

      names=$(echo "$yaml" | yq -r '.entries[].name')

      get_field() {
          echo "$yaml" | yq -r ".entries[] | select(.name == \"$1\") | .$2 // \"\""
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

      set +e
      result=$(echo "$names" | fzf \
          --prompt="Password> " \
          --header="Enter: password | Alt+u/p/l/o: copy | Shift: print" \
          --ignore-case \
          --preview="echo '$yaml' | yq -r '.entries[] | select(.name == \"{}\") | .notes // \"No notes\"'" \
          --expect="U,P,L,O,alt-u,alt-p,alt-l,alt-o")
      set -e

      key=$(echo "$result" | head -1)
      selected=$(echo "$result" | tail -1)
      [[ -z "$selected" ]] && exit 0

      case "$key" in
          "")    get_field "$selected" password ;;
          U)     get_field "$selected" username ;;
          P)     get_field "$selected" password ;;
          L)     get_field "$selected" url ;;
          O)     get_field "$selected" otp ;;
          alt-u) osc52_copy "$(get_field "$selected" username)" ;;
          alt-p) osc52_copy "$(get_field "$selected" password)" ;;
          alt-l) osc52_copy "$(get_field "$selected" url)" ;;
          alt-o) osc52_copy "$(get_field "$selected" otp)" ;;
      esac
    '';
  };
in
{
  options.user.cli.sops-menu = {
    enable = lib.mkEnableOption "sops-menu password finder";

    secretsFile = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "/path/to/secrets/users/heikov.yaml";
      description = "Path to the sops-encrypted YAML file for sops-menu.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ sops-menu ];
      }

      (lib.mkIf (cfg.secretsFile != "") {
        home.sessionVariables = {
          SOPS_SECRETS_FILE = cfg.secretsFile;
        };
      })
    ]
  );
}
