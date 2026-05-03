{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.workstation.display;
in
{
  options.workstation.display = {
    enable = lib.mkEnableOption "graphical login, Hyprland, and portals";
  };

  config = lib.mkIf cfg.enable {
    # ─── Boot UX ───────────────────────────────────────────────────
    boot = {
      plymouth = {
        enable = true;
        theme = "blockchain";
        themePackages = [ pkgs.adi1090x-plymouth-themes ];
      };
      kernelParams = [
        "quiet"
        "splash"
        "boot.shell_on_fail"
        "loglevel=3"
        "rd.systemd.show_status=false"
        "rd.udev.log_level=3"
        "udev.log_priority=3"
      ];
      consoleLogLevel = 0;
      initrd.verbose = false;
    };

    # ─── Display Stack ────────────────────────────────────────────
    services = {
      greetd = {
        enable = true;
        settings.default_session = {
          # TUI login that launches Hyprland directly.
          command = "${pkgs.tuigreet}/bin/tuigreet --time --user-menu --asterisks --cmd Hyprland";
          user = "greeter";
        };
      };

      xserver = {
        enable = true;
        xkb = {
          layout = "us";
          variant = "altgr-intl";
        };
      };
    };

    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
    };

    # ─── Portals ──────────────────────────────────────────────────
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
      ];
    };

    environment.pathsToLink = [
      "/share/applications"
      "/share/xdg-desktop-portal"
    ];
  };
}
