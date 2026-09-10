{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.desktop.hyprland.autostart;
  excludedOutputs = lib.escapeShellArg (builtins.toJSON config.user.desktop.hyprland.excludedOutputs);

  wallpaperSetup = pkgs.writeShellScript "swww-setup" ''
    for _ in {1..50}; do
      if ${pkgs.swww}/bin/swww query >/dev/null 2>&1; then
        break
      fi
      ${lib.getExe' pkgs.coreutils "sleep"} 0.1
    done

    MONITORS_JSON="$(
      ${pkgs.hyprland}/bin/hyprctl monitors -j \
        | ${pkgs.jq}/bin/jq \
          --argjson excluded ${excludedOutputs} \
          '[.[] | select(.name as $name | ($excluded | index($name)) == null)]'
    )"
    MONITORS_COUNT="$(printf '%s' "$MONITORS_JSON" | ${pkgs.jq}/bin/jq 'length')"
    SORTED_MONITORS="$(printf '%s' "$MONITORS_JSON" | ${pkgs.jq}/bin/jq -r 'sort_by(.x) | .[].name')"
    WP="${config.home.homeDirectory}/wallpapers/wp.gif"
    WP_L="${config.home.homeDirectory}/wallpapers/wp_l.gif"
    WP_R="${config.home.homeDirectory}/wallpapers/wp_r.gif"
    if [ "$MONITORS_COUNT" -eq 2 ] && [ -f "$WP_L" ] && [ -f "$WP_R" ]; then
      LEFT_MONITOR="$(printf '%s\n' "$SORTED_MONITORS" | ${lib.getExe' pkgs.coreutils "head"} -n 1)"
      RIGHT_MONITOR="$(printf '%s\n' "$SORTED_MONITORS" | ${lib.getExe' pkgs.coreutils "tail"} -n 1)"
      ${pkgs.swww}/bin/swww img "$WP_L" --outputs "$LEFT_MONITOR" 2>/dev/null || true
      ${pkgs.swww}/bin/swww img "$WP_R" --outputs "$RIGHT_MONITOR" 2>/dev/null || true
    else
      printf '%s\n' "$SORTED_MONITORS" | while read -r MONITOR; do
        ${pkgs.swww}/bin/swww img "$WP" --outputs "$MONITOR" 2>/dev/null || true
      done
    fi
  '';
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
        ExecStart = "${pkgs.swww}/bin/swww-daemon --no-cache";
        ExecStartPost = wallpaperSetup;
        Restart = "on-failure";
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
