{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.desktop.hyprland.hyprlandConfig;
in
{
  options.user.desktop.hyprland.hyprlandConfig = {
    enable = lib.mkEnableOption "Hyprland window manager config";
  };

  config = lib.mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;

      settings = {
        monitor = [
          ",preferred,auto,1"
        ];

        env = [
          "XCURSOR_SIZE,24"
          "HYPRCURSOR_SIZE,24"
        ];

        general = {
          gaps_in = 5;
          gaps_out = 20;
          border_size = 2;
          resize_on_border = false;
          allow_tearing = false;
          layout = "dwindle";
        };

        decoration = {
          rounding = 10;
          active_opacity = 1.0;
          inactive_opacity = 1.0;

          shadow = {
            enabled = true;
            range = 4;
            render_power = 3;
          };

          blur = {
            enabled = true;
            size = 3;
            passes = 1;
            vibrancy = 0.1696;
          };
        };

        animations = {
          enabled = true;

          bezier = [
            "easeOutQuint,0.23,1,0.32,1"
            "easeInOutCubic,0.65,0.05,0.36,1"
            "linear,0,0,1,1"
            "almostLinear,0.5,0.5,0.75,1.0"
            "quick,0.15,0,0.1,1"
          ];

          animation = [
            "global, 1, 10, default"
            "border, 1, 5.39, easeOutQuint"
            "windows, 1, 4.79, easeOutQuint"
            "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
            "windowsOut, 1, 1.49, linear, popin 87%"
            "fadeIn, 1, 1.73, almostLinear"
            "fadeOut, 1, 1.46, almostLinear"
            "fade, 1, 3.03, quick"
            "layers, 1, 3.81, easeOutQuint"
            "layersIn, 1, 4, easeOutQuint, fade"
            "layersOut, 1, 1.5, linear, fade"
            "fadeLayersIn, 1, 1.79, almostLinear"
            "fadeLayersOut, 1, 1.39, almostLinear"
            "workspaces, 1, 1.94, almostLinear, fade"
            "workspacesIn, 1, 1.21, almostLinear, fade"
            "workspacesOut, 1, 1.94, almostLinear, fade"
          ];
        };

        workspace = [
          "w[tv1], gapsout:0, gapsin:0"
          "f[1], gapsout:0, gapsin:0"
        ];

        windowrulev2 = [
          "bordersize 0, floating:0, onworkspace:w[tv1]"
          "rounding 0, floating:0, onworkspace:w[tv1]"
          "bordersize 0, floating:0, onworkspace:f[1]"
          "rounding 0, floating:0, onworkspace:f[1]"
          "suppressevent maximize, class:.*"
          "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"
          "float,class:^(sops-menu)$"
          "size 800 600,class:^(sops-menu)$"
          "center,class:^(sops-menu)$"
        ];

        dwindle = {
          pseudotile = true;
          preserve_split = true;
        };

        master = {
          new_status = "master";
        };

        misc = {
          force_default_wallpaper = -1;
        };

        input = {
          kb_layout = "us";
          kb_variant = "altgr-intl";
          kb_options = "caps:hyper";
          follow_mouse = 2;
          float_switch_override_focus = 0;
          sensitivity = 0;

          touchpad = {
            natural_scroll = false;
          };
        };

        device = {
          name = "razer-razer-deathadder-essential";
          sensitivity = 0;
        };

        "$mainMod" = "$SUPER";
        "$shiftMod" = "$mainMod+SHIFT";
        "$ctrlMod" = "$mainMod+CTRL";
        "$resizeAmount" = "100";

        bind = [
          "$mainMod, Return, exec, ${config.home.sessionVariables.TERMINAL}"
          "$mainMod, D, exec, ${config.home.sessionVariables.DMENU}"
          "$mainMod, S, exec, ${config.home.sessionVariables.PMENU}"
          "$mainMod, B, exec, ${config.home.sessionVariables.BROWSER}"
          "$mainMod, E, exec, ${config.home.sessionVariables.FILE_MANAGER}"
          "$mainMod, O, exec, ${config.home.sessionVariables.GUI_FILE_MANAGER}"
          "$mainMod, C, exec, ${config.home.sessionVariables.CALCULATOR}"
          "$mainMod, Escape, exec, hyprlock & systemctl suspend"
          "$shiftMod, Escape, exec, systemctl poweroff"
          "$ctrlMod, Escape, exec, systemctl suspend"
          "$mainMod, PRINT, exec, hyprshot -m output"
          "$shiftMod, PRINT, exec, hyprshot -m window"
          "$ctrlMod, PRINT, exec, hyprshot -m region"
          "$mainMod, R, exec, hyprctl reload"
          "$shiftMod, Q, killactive"
          "$mainMod, SPACE, togglefloating"
          "$mainMod, V, togglesplit"
          "$mainMod, F, fullscreen"
          "$mainMod, H, movefocus, l"
          "$mainMod, L, movefocus, r"
          "$mainMod, K, movefocus, u"
          "$mainMod, J, movefocus, d"
          "$shiftMod, H, movewindow, l"
          "$shiftMod, L, movewindow, r"
          "$shiftMod, K, movewindow, u"
          "$shiftMod, J, movewindow, d"
          "$ctrlMod, H, resizeactive, -$resizeAmount 0"
          "$ctrlMod, L, resizeactive, $resizeAmount 0"
          "$ctrlMod, K, resizeactive, 0 -$resizeAmount"
          "$ctrlMod, J, resizeactive, 0 $resizeAmount"
          "$mainMod, 1, workspace, 1"
          "$mainMod, 2, workspace, 2"
          "$mainMod, 3, workspace, 3"
          "$mainMod, 4, workspace, 4"
          "$mainMod, 5, workspace, 5"
          "$mainMod, 6, workspace, 6"
          "$mainMod, 7, workspace, 7"
          "$mainMod, 8, workspace, 8"
          "$mainMod, 9, workspace, 9"
          "$mainMod, 0, workspace, 10"
          "$shiftMod, 1, movetoworkspace, 1"
          "$shiftMod, 2, movetoworkspace, 2"
          "$shiftMod, 3, movetoworkspace, 3"
          "$shiftMod, 4, movetoworkspace, 4"
          "$shiftMod, 5, movetoworkspace, 5"
          "$shiftMod, 6, movetoworkspace, 6"
          "$shiftMod, 7, movetoworkspace, 7"
          "$shiftMod, 8, movetoworkspace, 8"
          "$shiftMod, 9, movetoworkspace, 9"
          "$shiftMod, 0, movetoworkspace, 10"
        ];

        bindm = [
          "$mainMod, mouse:272, movewindow"
          "$mainMod, mouse:273, resizewindow"
        ];

        bindel = [
          ",XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
          ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
          ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
          ",XF86MonBrightnessUp, exec, brightnessctl s 10%+"
          ",XF86MonBrightnessDown, exec, brightnessctl s 10%-"
        ];

        bindl = [
          ",XF86AudioNext, exec, playerctl next"
          ",XF86AudioPause, exec, playerctl play-pause"
          ",XF86AudioPlay, exec, playerctl play-pause"
          ",XF86AudioPrev, exec, playerctl previous"
        ];
      };
    };
  };
}
