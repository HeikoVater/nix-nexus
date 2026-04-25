{
  config,
  lib,
  ...
}:

let
  cfg = config.user.cli.television;
  secretsDir = "/run/secrets";
  obsidianDir = "~/syncthing/Obsidian/";
in
{
  options.user.cli.television = {
    enable = lib.mkEnableOption "television";
  };

  config = lib.mkIf cfg.enable {
    programs.television = {
      enable = true;

      channels = {
        # ════════════════════════════════════════════════════════════════
        # FILES
        # ════════════════════════════════════════════════════════════════
        files = {
          metadata = {
            name = "files";
            description = "Browse files and directories";
            requirements = [
              "fd"
              "bat"
            ];
          };

          source = {
            command = "fd -t f";
          };

          preview = {
            command = "bat -n --color=always '{}'";
            env = {
              BAT_THEME = "ansi";
            };
          };

          keybindings = {
            shortcut = "f1";
          };
        };

        # ════════════════════════════════════════════════════════════════
        # TEXT (ripgrep)
        # ════════════════════════════════════════════════════════════════
        text = {
          metadata = {
            name = "text";
            description = "Full-text search using ripgrep";
            requirements = [
              "rg"
              "bat"
            ];
          };

          source = {
            command = "rg --vimgrep '' .";
            output = "{split: :4}";
          };

          preview = {
            command = "bat --style=numbers --color=always '{1}'";
          };

          keybindings = {
            shortcut = "f2";
          };
        };

        # ════════════════════════════════════════════════════════════════
        # GIT REPOSITORIES
        # ════════════════════════════════════════════════════════════════
        "git-repos" = {
          metadata = {
            name = "git-repos";
            description = "Browse local Git repositories";
            requirements = [
              "fd"
              "git"
            ];
          };

          source = {
            command = ''
              fd -t d -H '^\.git$' \
                --execdir sh -c 'pwd' \
                | sed 's#/.git$##'
            '';
          };

          preview = {
            command = "git -C '{}' status --short --branch";
          };

          keybindings = {
            shortcut = "f3";
          };
        };

        # ════════════════════════════════════════════════════════════════
        # PROCESSES
        # ════════════════════════════════════════════════════════════════
        processes = {
          metadata = {
            name = "processes";
            description = "Inspect running system processes";
            requirements = [ "ps" ];
          };

          source = {
            command = "ps aux";
          };

          preview = {
            command = "echo '{}'";
          };

          keybindings = {
            shortcut = "f4";
          };
        };

        # ════════════════════════════════════════════════════════════════
        # ENVIRONMENT VARIABLES
        # ════════════════════════════════════════════════════════════════
        env = {
          metadata = {
            name = "env";
            description = "Browse environment variables";
          };

          source = {
            command = "env | sort";
          };

          preview = {
            command = "echo '{}'";
          };

          keybindings = {
            shortcut = "f5";
          };
        };

        # ════════════════════════════════════════════════════════════════
        # PROGRAMS (PATH)
        # ════════════════════════════════════════════════════════════════
        programs = {
          metadata = {
            name = "programs";
            description = "Executables available in PATH";
            requirements = [ "which" ];
          };

          source = {
            command = "bash -lc 'compgen -c | sort -u'";
          };

          preview = {
            command = "which '{}' 2>/dev/null || true";
          };

          keybindings = {
            shortcut = "f6";
          };
        };

        # ════════════════════════════════════════════════════════════════
        # SOPS PASSWORDS
        # ════════════════════════════════════════════════════════════════
        "sops-passwords" = {
          metadata = {
            name = "sops-passwords";
            description = "Encrypted secrets from /run/secrets";
            requirements = [
              "sops"
              "yq"
            ];
          };

          source = {
            command = "fd -t f '\\.ya?ml$' ${secretsDir}";
          };

          preview = {
            command = ''
              sops -d '{}' \
                | yq '.password // .token // .value // .'
            '';
          };

          keybindings = {
            shortcut = "f7";
          };
        };

        # ════════════════════════════════════════════════════════════════
        # TMUX SESSIONS
        # ════════════════════════════════════════════════════════════════
        "tmux-sessions" = {
          metadata = {
            name = "tmux-sessions";
            description = "Existing tmux sessions";
            requirements = [ "tmux" ];
          };

          source = {
            command = "tmux list-sessions -F '#S' 2>/dev/null || true";
          };

          preview = {
            command = "tmux list-windows -t '{}' 2>/dev/null || true";
          };

          keybindings = {
            shortcut = "f8";
          };
        };

        # ════════════════════════════════════════════════════════════════
        # OBSIDIAN VAULT
        # ════════════════════════════════════════════════════════════════
        obsidian = {
          metadata = {
            name = "obsidian";
            description = "Markdown notes in Obsidian vault";
            requirements = [
              "fd"
              "bat"
            ];
          };

          source = {
            command = "fd -t f '\\.md$' ${obsidianDir}";
          };

          preview = {
            command = "bat --color=always '{}'";
          };

          keybindings = {
            shortcut = "f9";
          };
        };
      };
    };
  };
}
