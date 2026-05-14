{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:

let
  cfg = config.user.tui.opencode;
  smallModel = "openai/gpt-5.4-mini";

  # OpenCode leaks tmux pane startup queries when passthrough is enabled, so
  # run it with pane-local passthrough disabled and restore the prior state.
  tmuxWrappedUnstableOpencodeBin = pkgs.writeShellScriptBin "opencode" ''
    set -euo pipefail

    real_opencode="${lib.getExe pkgs-unstable.opencode}"

    if [ -z "''${TMUX:-}" ]; then
      exec "$real_opencode" "$@"
    fi

    tmux_bin="${lib.getExe pkgs.tmux}"
    if ! pane_id=$("$tmux_bin" display-message -p '#{pane_id}' 2>/dev/null); then
      exec "$real_opencode" "$@"
    fi

    had_local=true
    if local_value=$("$tmux_bin" show-options -q -p -v -t "$pane_id" allow-passthrough 2>/dev/null); then
      old_value="$local_value"
    else
      had_local=false
      old_value=$("$tmux_bin" show-options -A -p -v -t "$pane_id" allow-passthrough 2>/dev/null || printf 'off\n')
    fi

    cleanup() {
      if [ "$had_local" = true ]; then
        "$tmux_bin" set-option -q -p -t "$pane_id" allow-passthrough "$old_value" >/dev/null 2>&1 || true
      else
        "$tmux_bin" set-option -q -p -u -t "$pane_id" allow-passthrough >/dev/null 2>&1 || true
      fi
    }

    trap cleanup EXIT HUP INT TERM

    "$tmux_bin" set-option -q -p -t "$pane_id" allow-passthrough off >/dev/null 2>&1 || true
    "$real_opencode" "$@"
  '';

  tmuxWrappedUnstableOpencode = pkgs.symlinkJoin {
    name = "opencode-${pkgs-unstable.opencode.version}-tmux-wrapped";
    paths = [ pkgs-unstable.opencode ];
    postBuild = ''
      rm "$out/bin/opencode"
      cp "${tmuxWrappedUnstableOpencodeBin}/bin/opencode" "$out/bin/opencode"
      chmod +x "$out/bin/opencode"
    '';
  };
in
{
  options.user.tui.opencode = {
    enable = lib.mkEnableOption "OpenCode AI coding agent";
  };

  config = lib.mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      package = tmuxWrappedUnstableOpencode;

      settings = {
        share = "disabled";
        autoupdate = false;

        default_agent = "plan";

        enabled_providers = [
          # "opencode"
          "openai"
        ];

        small_model = smallModel;

        provider.openai.options.setCacheKey = true;

        agent = {
          plan = {
            model = "openai/gpt-5.4";
            variant = "xhigh";
          };
          build = {
            model = "openai/gpt-5.4";
            variant = "xhigh";
          };
        };

        command = {
          "commit-subject" = {
            description = "Suggest a Git commit subject";
            agent = "build";
            model = smallModel;
            template = ''
              Staged diff stat:
              !`git diff --cached --stat`

              Staged diff:
              !`git diff --cached`

              Write exactly one Git commit subject line for the currently staged changes.
              Do NOT output anything else!

              Requirements:
              - Use imperative mood.
              - Focus on the intent of the change, not a file-by-file summary.
              - Do not end with a period.
              - Prefer 50-60 characters and never exceed 72 characters.
              - Use a prefix like fix:, feat:, refactor:, docs:, test:, or chore: only when it clearly fits.
              - Output only the subject line.
            '';
          };
        };

        formatter = {
          "nix" = {
            command = [
              "nix"
              "fmt"
              "$FILE"
            ];
            extensions = [ ".nix" ];
          };
        };

        watcher.ignore = [ ".worktrees/**" ];

        permission = {
          edit = {
            "*" = "allow";
            "/nix/store/**" = "deny";
          };
          bash = {
            "*" = "ask";

            # nix
            "nix fmt*" = "allow";
            "nix eval*" = "allow";
            "nix flake check*" = "allow";
            "nix flake show*" = "allow";
            "nixos-rebuild*" = "deny";
            "nh os*" = "deny";

            # sops
            "sops*" = "ask";

            # tools
            "grep *" = "allow";
            "rg *" = "allow";
            "man *" = "allow";

            # systemd inspection
            "systemctl status*" = "allow";
            "systemctl is-active*" = "allow";
            "systemctl is-enabled*" = "allow";
            "systemctl list-units*" = "allow";
            "systemctl list-unit-files*" = "allow";
            "systemctl list-timers*" = "allow";
            "systemctl --failed*" = "allow";
            "systemctl cat*" = "allow";
            "systemctl --user status*" = "allow";
            "systemctl --user is-active*" = "allow";
            "systemctl --user is-enabled*" = "allow";
            "systemctl --user list-units*" = "allow";
            "systemctl --user list-unit-files*" = "allow";
            "systemctl --user list-timers*" = "allow";
            "systemctl --user --failed*" = "allow";
            "systemctl --user cat*" = "allow";
            "journalctl*" = "ask";

            # safe HTTP fetches
            "curl *" = "ask";
            "curl -I https://*" = "allow";
            "curl -sS https://*" = "allow";
            "curl -sSL https://*" = "allow";
            "curl -fsSL https://*" = "allow";
            "curl*--data*" = "deny";
            "curl*-d*" = "deny";
            "curl*--form*" = "deny";
            "curl*-F*" = "deny";
            "curl*-T*" = "deny";
            "curl*file://*" = "deny";
            "curl*localhost*" = "deny";
            "curl*127.0.0.1*" = "deny";
            "curl*.lan*" = "deny";

            # git — read-only operations allowed
            "git status*" = "allow";
            "git diff*" = "allow";
            "git log*" = "allow";
            "git show*" = "allow";
            "git blame*" = "allow";
            "git grep*" = "allow";
            "git reflog*" = "allow";
            "git add*" = "allow";
            "git restore*" = "allow";
            "git rm*" = "allow";
            "git mv*" = "allow";
            "git fetch*" = "allow";

            "git commit*" = "ask";
            "git checkout*" = "ask";
            "git switch*" = "ask";
            "git branch*" = "ask";
            "git pull*" = "ask";
            "git remote*" = "ask";
            "git revert*" = "ask";

            "git push*" = "deny";
            "git merge*" = "deny";
            "git rebase*" = "deny";
            "git cherry-pick*" = "deny";
            "git reset*" = "deny";
            "git filter-repo*" = "deny";
            "git gc*" = "deny";
            "git prune*" = "deny";
          };
          skill = "ask";
          webfetch = "allow";
          doom_loop = "ask";
          external_directory = {
            "*" = "ask";
            "/nix/store/**" = "allow";
          };
        };
      };
    };
  };
}
