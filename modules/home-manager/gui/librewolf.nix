{
  config,
  lib,
  ...
}:

let
  cfg = config.user.gui.librewolf;
in
{
  options.user.gui.librewolf = {
    enable = lib.mkEnableOption "librewolf";
  };

  config = lib.mkIf cfg.enable {
    programs.librewolf = {
      enable = true;
      settings = {
        "browser.startup.page" = "3";
        "browser.tabs.closeWindowWithLastTab" = false;
        "browser.tabs.hoverPreview.enabled" = false;
        "browser.newtabpage.enabled" = false;
        "browser.toolbars.bookmarks.visibility" = "always";
        "sidebar.verticalTabs" = true;
      };

      policies.ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        };

        "firefox@tampermonkey.net" = {
          installation_mode = "normal_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/tampermonkey/latest.xpi";
        };

        "addon@darkreader.org" = {
          installation_mode = "normal_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
        };

        "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
          installation_mode = "normal_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi";
        };
      };
    };
  };
}
