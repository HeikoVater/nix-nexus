{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.tui.yazi;
in
{
  options.user.tui.yazi = {
    enable = lib.mkEnableOption "yazi terminal file manager";
  };

  config = lib.mkIf cfg.enable {
    programs.yazi = {
      enable = true;

      settings = {
        mgr = {
          show_hidden = false;
          sort_by = "natural";
          sort_dir_first = true;
          linemode = "size";
          show_symlink = true;
          scrolloff = 5;
        };

        preview = {
          tab_size = 2;
          max_width = 1000;
          max_height = 1000;
          cache_dir = "";
          image_filter = "lanczos3";
          image_quality = 90;
        };

        # Headless-adapted openers (no GUI image/video viewers)
        opener = {
          edit-text = [
            {
              run = ''$EDITOR "$@"'';
              desc = "Edit with $EDITOR";
            }
          ];
          reveal = [
            {
              run = ''exiftool "$1"; echo "Press enter to continue"; read'';
              block = true;
              desc = "Show EXIF/metadata";
            }
          ];
        };

        open = {
          rules = [
            {
              mime = "text/*";
              use = "edit-text";
            }
            {
              mime = "image/*";
              use = "reveal";
            }
            {
              mime = "video/*";
              use = "reveal";
            }
            {
              mime = "audio/*";
              use = "reveal";
            }
          ];
        };
      };

      keymap = {
        mgr.prepend_keymap = [
          # Navigation
          {
            on = [ "<C-u>" ];
            run = "seek -5";
            desc = "Seek up 5 units";
          }
          {
            on = [ "<C-d>" ];
            run = "seek 5";
            desc = "Seek down 5 units";
          }

          # Toggle hidden files
          {
            on = [ "." ];
            run = "hidden toggle";
            desc = "Toggle hidden";
          }

          # Selection
          {
            on = [ "v" ];
            run = "visual_mode";
            desc = "Enter visual mode";
          }
          {
            on = [ "V" ];
            run = "visual_mode --unset";
            desc = "Exit visual mode";
          }

          # Tabs
          {
            on = [ "t" ];
            run = "tab_create --current";
            desc = "New tab";
          }
          {
            on = [ "T" ];
            run = "tab_close 0";
            desc = "Close current tab";
          }
          {
            on = [ "]" ];
            run = "tab_switch 1 --relative";
            desc = "Next tab";
          }
          {
            on = [ "[" ];
            run = "tab_switch -1 --relative";
            desc = "Previous tab";
          }
          {
            on = [ "}" ];
            run = "tab_swap 1";
            desc = "Swap with next tab";
          }
          {
            on = [ "{" ];
            run = "tab_swap -1";
            desc = "Swap with previous tab";
          }

          # File operations
          {
            on = [
              "y"
              "y"
            ];
            run = "yank";
            desc = "Yank files";
          }
          {
            on = [
              "y"
              "c"
            ];
            run = "yank --cut";
            desc = "Cut files";
          }
          {
            on = [
              "y"
              "p"
            ];
            run = "yank --cut=false";
            desc = "Yank path";
          }
          {
            on = [
              "d"
              "d"
            ];
            run = "remove";
            desc = "Move to trash";
          }
          {
            on = [ "D" ];
            run = "remove --permanently";
            desc = "Delete permanently";
          }

          # Create
          {
            on = [ "a" ];
            run = "create";
            desc = "Create file/dir";
          }
          {
            on = [ "r" ];
            run = "rename --cursor=before_ext";
            desc = "Rename";
          }

          # Open/edit
          {
            on = [ "<Enter>" ];
            run = "open";
            desc = "Open";
          }
          {
            on = [ "<C-Enter>" ];
            run = "open --interactive";
            desc = "Open with...";
          }
          {
            on = [ "e" ];
            run = ''shell '$EDITOR "$0"' --orphan'';
            desc = "Edit with $EDITOR";
          }

          # Search
          {
            on = [ "/" ];
            run = "find --smart";
            desc = "Find";
          }
          {
            on = [ "?" ];
            run = "find --previous --smart";
            desc = "Find previous";
          }

          # Go to
          {
            on = [
              "g"
              "h"
            ];
            run = "cd ~";
            desc = "Go to home";
          }
          {
            on = [
              "g"
              "c"
            ];
            run = "cd ~/.config";
            desc = "Go to config";
          }
          {
            on = [
              "g"
              "d"
            ];
            run = "cd ~/Downloads";
            desc = "Go to downloads";
          }
          {
            on = [
              "g"
              "n"
            ];
            run = "cd /etc/nixos";
            desc = "Go to nixos config";
          }
          {
            on = [
              "g"
              "s"
            ];
            run = "cd /mnt/share";
            desc = "Go to share";
          }

          # Shell
          {
            on = [ "!" ];
            run = "shell --block --confirm";
            desc = "Execute shell command";
          }

          {
            on = [ "X" ];
            run = ''
              shell --block --confirm -- for f in %s; do
                case "$f" in
                  *.zip|*.7z|*.tar.gz|*.tar.bz2|*.tar.xz|*.rar|*.tar)
                    base="$(basename "$f")"
                    dir="$(dirname "$f")"
                    outdir="$dir/$(echo "$base" | sed -E 's/\.(tar\.(gz|bz2|xz)|zip|7z|rar|tar)$//')"
                    mkdir -p "$outdir" && 7z x -y "$f" -o"$outdir" || echo "Failed to extract $f"
                    ;;
                esac
              done
            '';
            desc = "Extract selected archives into named folders";
          }
        ];
      };
    };

    # Zsh integration — change directory on yazi exit
    programs.zsh.initContent = ''
      # Yazi wrapper to change directory on exit
      function yy() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
        yazi "$@" --cwd-file="$tmp"
        if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
          cd -- "$cwd"
        fi
        rm -f -- "$tmp"
      }
    '';

    home.packages = with pkgs; [
      # File operations
      ffmpegthumbnailer # Video thumbnails
      unar # Archives
      p7zip # Archives
      poppler-utils # PDF preview
      fd # Finding/searching
      ripgrep # Finding/searching
      fzf # Finding/searching
      zoxide # Finding/searching

      # Utilities
      exiftool # EXIF data
      mediainfo # Media info
      file # File type detection
    ];
  };
}
