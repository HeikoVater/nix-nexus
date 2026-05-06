{
  config,
  lib,
  pkgs-unstable,
  ...
}:

let
  cfg = config.user.tui.opencode;
  smallModel = "openai/gpt-5.4-mini";
in
{
  options.user.tui.opencode = {
    enable = lib.mkEnableOption "OpenCode AI coding agent";
  };

  config = lib.mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      package = pkgs-unstable.opencode;

      settings = {
        share = "disabled";
        autoupdate = "notify";

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
            "grep*" = "allow";
            "rg*" = "allow";

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
