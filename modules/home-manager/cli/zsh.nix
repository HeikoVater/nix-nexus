{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.cli.zsh;
in
{
  options.user.cli.zsh = {
    enable = lib.mkEnableOption "Zsh";
  };

  config = lib.mkIf cfg.enable {
    programs.zsh = {
      enable = true;

      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      defaultKeymap = "viins";

      history = {
        size = 100000;
        save = 100000;
        ignoreDups = true;
        ignoreSpace = true;
        share = true;
        expireDuplicatesFirst = true;
      };

      initContent = builtins.concatStringsSep "\n" [
        # suggestions
        "bindkey '^a' autosuggest-accept"

        # completion
        "zstyle ':completion:*' menu select"
        "zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'"
        "zstyle ':completion:*' list-colors ''"
        "zstyle ':completion:*' group-name ''"

        # vim
        "KEYTIMEOUT=20"

        "bindkey -M viins 'jj' vi-cmd-mode"

        "bindkey -M vicmd 'v' visual-mode"
        "bindkey -M vicmd 'V' visual-line-mode"

        "bindkey -M vicmd '/' history-incremental-search-backward"

        # delete last word
        "bindkey '^h' backward-kill-word"

        ''
          # Auto-attach tmux session
          if command -v tmux &> /dev/null && [ -z "$TMUX" ]; then
            if tmux has-session -t main 2>/dev/null; then
              # Main session exists, check if it has any attached clients
              if tmux list-clients -t main 2>/dev/null | grep -q .; then
                # Main has attached clients, create a new session
                tmux new-session
              else
                # Main has no attached clients, attach to it
                tmux attach-session -t main
              fi
            else
              # Main doesn't exist, create it
              tmux new-session -s main
            fi
          fi
        ''
      ];
    };
  };
}
