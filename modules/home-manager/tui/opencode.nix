{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:

let
  cfg = config.user.tui.opencode;
  big-provider = "opencode";
  big-model = "claude-opus-4-6";
  small-provider = "opencode";
  small-model = "claude-sonnet-4-6";
  # big-provider = "openai";
  # big-model = "gpt-5.3-codex";
  # small-provider = "openai";
  # small-model = "gpt-5.3-codex";
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

        enabled_providers = [
          "opencode"
          "openai"
        ];

        default_agent = "plan";

        # provider = {
        #   opencode.models = {
        #     "claude-opus-4.5".options = {
        #       reasoningEffort = "high";
        #     };
        #   };
        #   openai.models = {
        #     "gpt-5.2-codex".options = {
        #       reasoningEffort = "high";
        #     };
        #   };
        # };

        agent = {
          build = {
            model = "${small-provider}/${small-model}";
          };
          plan = {
            model = "${big-provider}/${big-model}";
          };
          # build = {
          #   description = "Full development work with all tools enabled.";
          #   mode = "primary";
          #   model = "${small-model}";
          #   tools = {
          #     write = true;
          #     edit = true;
          #     bash = true;
          #   };
          # };
          # plan = {
          #   description = "Analysis and planning without making changes";
          #   mode = "primary";
          #   model = "${big-model}";
          #   tools = {
          #     write = false;
          #     edit = false;
          #     bash = false;
          #   };
          # };
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
            # "*" = "ask";

            # nix
            "nix-rebuild" = "deny";
            "nh os" = "deny";

            # sops
            "sops" = "ask";

            # git — read-only operations allowed
            "git status" = "allow";
            "git diff" = "allow";
            "git log" = "allow";
            "git show" = "allow";
            "git blame" = "allow";
            "git grep" = "allow";
            "git reflog" = "allow";
            "git add" = "allow";
            "git restore" = "allow";
            "git rm" = "allow";
            "git mv" = "allow";
            "git fetch" = "allow";

            "git commit" = "ask";
            "git checkout" = "ask";
            "git switch" = "ask";
            "git branch" = "ask";
            "git pull" = "ask";
            "git remote" = "ask";
            "git revert" = "ask";

            "git push" = "deny";
            "git merge" = "deny";
            "git rebase" = "deny";
            "git cherry-pick" = "deny";
            "git reset" = "deny";
            "git filter-repo" = "deny";
            "git gc" = "deny";
            "git prune" = "deny";
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
