{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.desktop.hyprland.autostart;
in
{
  options.user.desktop.hyprland.autostart = {
    enable = lib.mkEnableOption "Hyprland autostart services";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.swww-daemon = {
      Unit = {
        Description = "swww wallpaper daemon";
        PartOf = [ "hyprland-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.swww}/bin/swww-daemon";
        Restart = "on-failure";
      };
      Install = {
        WantedBy = [ "hyprland-session.target" ];
      };
    };

    systemd.user.services.swww-wallpaper = {
      Unit = {
        Description = "Set wallpaper via swww";
        Requires = [ "swww-daemon.service" ];
        After = [ "swww-daemon.service" ];
        PartOf = [ "hyprland-session.target" ];
      };

      Service = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "swww-setup" ''
          MONITORS_JSON="$(${pkgs.hyprland}/bin/hyprctl monitors -j)"
          MONITORS_COUNT="$(echo "$MONITORS_JSON" | ${pkgs.jq}/bin/jq 'length')"
          SORTED_MONITORS="$(echo "$MONITORS_JSON" | ${pkgs.jq}/bin/jq -r 'sort_by(.x) | .[].name')"
          WP="${config.home.homeDirectory}/wallpapers/wp.gif"
          WP_L="${config.home.homeDirectory}/wallpapers/wp_l.gif"
          WP_R="${config.home.homeDirectory}/wallpapers/wp_r.gif"
          if [ "$MONITORS_COUNT" -eq 2 ] && [ -f "$WP_L" ]; then
          LEFT_MONITOR="$(echo "$SORTED_MONITORS" | head -n 1)"
          RIGHT_MONITOR="$(echo "$SORTED_MONITORS" | tail -n 1)"
          ${pkgs.swww}/bin/swww img "$WP_L" --outputs "$LEFT_MONITOR" 2>/dev/null || true
          ${pkgs.swww}/bin/swww img "$WP_R" --outputs "$RIGHT_MONITOR" 2>/dev/null || true
          else
          echo "$SORTED_MONITORS" | while read -r MONITOR; do
          ${pkgs.swww}/bin/swww img "$WP" --outputs "$MONITOR" 2>/dev/null || true
          done
          fi
        '';
      };
      Install = {
        WantedBy = [ "hyprland-session.target" ];
      };
    };

    systemd.user.services.waybar = {
      Unit = {
        Description = "Wayland bar";
        Requires = [ "hyprland-session.target" ];
        After = [ "hyprland-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        ExecStart = "${pkgs.waybar}/bin/waybar";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    systemd.user.services.mako = {
      Unit = {
        Description = "Notification daemon";
        Requires = [ "hyprland-session.target" ];
        After = [ "hyprland-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        ExecStart = "${pkgs.mako}/bin/mako";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    systemd.user.services.nm-applet = {
      Unit = {
        Description = "Network manager applet";
        Requires = [ "hyprland-session.target" ];
        After = [ "hyprland-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };
  };
}
