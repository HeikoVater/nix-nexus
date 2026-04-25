{
  config,
  lib,
  pkgs-unstable,
  ...
}:

let
  cfg = config.user.tui.opencode;
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
          "opencode"
        ];

        small_model = "opencode/claude-haiku-4-5";

        provider.opencode.options.setCacheKey = true;

        agent = {
          plan = {
            model = "opencode/claude-opus-4-6";
            variant = "max";
          };
          build = {
            model = "opencode/claude-sonnet-4-6";
            variant = "high";
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
          edit = "allow";
          bash = {
            "*" = "ask";

            # nix
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
          external_directory = "ask";
        };
      };
    };
  };
}
