{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.cli.starship;
in
{
  options.user.cli.starship = {
    enable = lib.mkEnableOption "starship prompt";
  };

  config = lib.mkIf cfg.enable {
    programs.starship = {
      enable = true;
      settings = {
        format = lib.concatStrings [
          "$git_branch"
          "$git_status"
          "$git_commit"
          "$nix_shell"
          "$python"

          "$line_break"

          "$directory"
          "$sudo"
          "$character"
        ];

        git_branch = {
          format = " [ $branch](purple bold)";
        };

        git_status = {
          ahead = "[⇡$count](green)";
          behind = "[⇣$count](red)";
          format = "[ \\[[$all_status](yellow)$ahead_behind\\]](purple) ";
        };

        git_commit = {
          format = " [\\($hash$tag\\)](purple)";
        };

        nix_shell = {
          format = " [❄️ $name](cyan)";
        };

        python = {
          format = " [ $virtualenv](yellow)";
        };

        directory = {
          truncation_length = 5;
          truncate_to_repo = true;
          style = "blue bold";
        };

        sudo = {
          format = "👑 ";
          disabled = false;
        };

        character = {
          success_symbol = "[❯](green)";
          error_symbol = "[❯](red)";
          vicmd_symbol = "[❮](yellow)";
          vimcmd_replace_one_symbol = "[❮](purple)";
          vimcmd_replace_symbol = "[❮](purple)";
          vimcmd_visual_symbol = "[❮](yellow)";
        };
      };
    };
  };
}
