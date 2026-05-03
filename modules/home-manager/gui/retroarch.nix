{
  config,
  lib,
  ...
}:

let
  cfg = config.user.gui.retroarch;
  retroarchRootDir = cfg.rootDir;
  retroarchConfigDir = "${retroarchRootDir}/config";
  retroarchPlaylistsDir = "${retroarchRootDir}/playlists";
  retroarchRomsDir = "${retroarchRootDir}/roms";
  retroarchSavesDir = "${retroarchRootDir}/saves";
  retroarchStatesDir = "${retroarchRootDir}/states";
  retroarchThumbnailsDir = "${retroarchRootDir}/thumbnails";
in
{
  options.user.gui.retroarch = {
    enable = lib.mkEnableOption "retroarch";

    rootDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/RetroArch";
      description = "Root directory for RetroArch config, content, saves, and thumbnails.";
    };

    kioskMode = {
      enable = lib.mkEnableOption "RetroArch kiosk mode";

      password = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Password to exit kiosk mode (stored in plain text in RetroArch config).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.retroarch = {
      enable = true;
      cores = {
        bsnes.enable = true;
        mgba.enable = true;
        mupen64plus.enable = true;
        "parallel-n64".enable = true;
        snes9x.enable = true;
      };
      settings = {
        menu_show_core_updater = "false";
        rgui_config_directory = retroarchConfigDir;
        playlist_directory = retroarchPlaylistsDir;
        content_directory = retroarchRomsDir;
        rgui_browser_directory = retroarchRomsDir;
        savefile_directory = retroarchSavesDir;
        savestate_directory = retroarchStatesDir;
        thumbnails_directory = retroarchThumbnailsDir;
      }
      // lib.optionalAttrs cfg.kioskMode.enable {
        kiosk_mode_enable = "true";
        kiosk_mode_password = cfg.kioskMode.password;
      };
    };

    home.activation.createRetroArchDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p \
        ${lib.escapeShellArg retroarchConfigDir} \
        ${lib.escapeShellArg retroarchPlaylistsDir} \
        ${lib.escapeShellArg retroarchRomsDir} \
        ${lib.escapeShellArg retroarchSavesDir} \
        ${lib.escapeShellArg retroarchStatesDir} \
        ${lib.escapeShellArg retroarchThumbnailsDir}
    '';
  };
}
