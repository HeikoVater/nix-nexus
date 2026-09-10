{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.user.desktop.hyprland.waybar;
  cryptoTrackerEnabled = cfg.cryptoTrackerApiKeyFile != null;
  outputs = map (output: "!${output}") config.user.desktop.hyprland.excludedOutputs ++ [ "*" ];
  ignoredWorkspaces = map (
    workspace: "^${lib.escapeRegex workspace}$"
  ) config.user.desktop.hyprland.ignoredWorkspaces;
  openaiUsageEnabled = cfg.openaiAuthFile != null;
  centerModules =
    lib.optional cryptoTrackerEnabled "group/finance"
    ++ lib.optional openaiUsageEnabled "custom/openai-usage";

  nvidiaStats = pkgs.writeShellScript "nvidia-stats" ''
    if ! command -v nvidia-smi >/dev/null 2>&1; then
      echo '{"text": "N/A"}'
      exit 0
    fi

    nvidia-smi \
    --query-gpu=utilization.gpu,temperature.gpu,name,memory.used,memory.total,utilization.memory \
    --format=csv,nounits,noheader \
    | awk -F ', ' '{ printf \
    "{\"text\":\" %s%% (%s°C)\",\"tooltip\":\"%s\\nVRAM: %.2f/%.2f GB (%s%%)\"}\n", \
    $1, $2, $3, $4/1024, $5/1024, $6}'
  '';

  cryptoTrackerStats =
    if cryptoTrackerEnabled then
      pkgs.writeShellScript "crypto-tracker-stats" ''
        keyFile=${lib.escapeShellArg cfg.cryptoTrackerApiKeyFile}

        if [ ! -r "$keyFile" ]; then
          echo '{"text": "N/A"}'
          exit 0
        fi

        apiKey="$(${lib.getExe' pkgs.coreutils "tr"} -d '[:space:]' < "$keyFile")"
        if [ -z "$apiKey" ]; then
          echo '{"text": "N/A"}'
          exit 0
        fi

        ${lib.getExe pkgs.crypto-tracker} -k "$apiKey" -s BTC,ETH -m BTC || echo '{"text": "N/A"}'
      ''
    else
      null;

  openaiUsageStats =
    if openaiUsageEnabled then
      pkgs.writeShellApplication {
        name = "openai-usage-stats";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          jq
        ];
        text = ''
          authFile=${lib.escapeShellArg cfg.openaiAuthFile}

          unavailable() {
            ${lib.getExe pkgs.jq} -cn '{text: "OpenAI N/A", tooltip: "OpenAI usage unavailable"}'
            exit 0
          }

          [ -r "$authFile" ] || unavailable

          accessToken="$(${lib.getExe pkgs.jq} -er '.openai | select(.type == "oauth") | .access' "$authFile" 2>/dev/null)" || unavailable
          accountId="$(${lib.getExe pkgs.jq} -er '.openai.accountId' "$authFile" 2>/dev/null)" || unavailable

          response="$(printf '%s\n' \
            "header = \"Authorization: Bearer $accessToken\"" \
            "header = \"ChatGPT-Account-Id: $accountId\"" \
            'header = "Accept: application/json"' \
            | ${lib.getExe pkgs.curl} \
              --config - \
              --fail \
              --silent \
              --max-time 10 \
              https://chatgpt.com/backend-api/wham/usage 2>/dev/null)" || unavailable

          windows="$(${lib.getExe pkgs.jq} -er '
            def window($seconds; $fallback):
              ([.rate_limit.primary_window, .rate_limit.secondary_window]
                | map(select(.limit_window_seconds == $seconds))[0]) // $fallback;
            def remaining:
              (100 - .used_percent) | if . < 0 then 0 elif . > 100 then 100 else . end | round;
            (window(18000; .rate_limit.primary_window)) as $five |
            (window(604800; .rate_limit.secondary_window)) as $week |
            [($five | remaining), $five.reset_at, ($week | remaining), $week.reset_at] | @tsv
          ' <<<"$response" 2>/dev/null)" || unavailable

          IFS=$'\t' read -r fiveRemaining fiveReset weekRemaining weekReset <<<"$windows"
          [[ "$fiveReset" =~ ^[0-9]+$ && "$weekReset" =~ ^[0-9]+$ ]] || unavailable

          fiveResetText="$(${lib.getExe' pkgs.coreutils "date"} --date="@$fiveReset" '+%a %Y-%m-%d %H:%M')" || unavailable
          weekResetText="$(${lib.getExe' pkgs.coreutils "date"} --date="@$weekReset" '+%a %Y-%m-%d %H:%M')" || unavailable

          ${lib.getExe pkgs.jq} -cn \
            --arg text "OpenAI: 5h $fiveRemaining% | W $weekRemaining%" \
            --arg tooltip "5-hour limit resets: $fiveResetText"$'\n'"Weekly limit resets: $weekResetText" \
            '{text: $text, tooltip: $tooltip}'
        '';
      }
    else
      null;
in
{
  options.user.desktop.hyprland.waybar = {
    enable = lib.mkEnableOption "waybar";

    cryptoTrackerApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/crypto_tracker_api_key";
      description = "Path to the crypto-tracker API key file. When unset, the crypto widget is omitted.";
    };

    openaiAuthFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/user/.local/share/opencode/auth.json";
      description = "Path to OpenCode's OAuth auth file. When unset, the OpenAI usage widget is omitted.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file.".config/waybar/config.jsonc".text = ''
      {
          "output": ${builtins.toJSON outputs},
          "modules-left": ["hyprland/workspaces", "hyprland/submap"],
          "modules-center": ${builtins.toJSON centerModules},
          "modules-right": ["group/hardware", "group/laptop", "group/system"],

          // Modules configuration
          "hyprland/workspaces": {
              "format": "{icon} <sub>{windows}</sub>",
              "format-window-separator": "",
              "ignore-workspaces": ${builtins.toJSON ignoredWorkspaces},
              "window-rewrite-default": "",
              "window-rewrite": {
                  "title<.*youtube.*>": "",
                  "title<.*4chan.*>": "",
                  "title<.*whatsapp.*>": "",
                  "title<yazi>": "",
                  "class<firefox>": "",
                  "class<kitty>": "",
                  "class<mpv>": ""
                  //     
              }
              // "persistent-workspaces": {
              //     "*": 5
              // }
          },
      ${lib.optionalString cryptoTrackerEnabled ''
        "group/finance": {
            "orientation": "horizontal",
            "modules": [
                "custom/crypto"
            ]
        },
        "custom/crypto": {
            "exec": "${cryptoTrackerStats}",
            "return-type": "json",
            "restart-interval": 600
        },
      ''}
      ${lib.optionalString openaiUsageEnabled ''
        "custom/openai-usage": {
            "exec": "${lib.getExe openaiUsageStats}",
            "return-type": "json",
            "interval": 60
        },
      ''}
          "group/hardware": {
              "orientation": "horizontal",
              "modules": [
                  "custom/gpu",
                  "cpu",
                  "memory",
                  "disk"
              ]
          },
          "custom/gpu": {
              "exec": "${nvidiaStats}",
              "return-type": "json",
              "interval": 3
          },
          "cpu": {
              "format": " {usage}%",
              "interval": 2
          },
          "memory": {
              "format": "  {}%",
              "tooltip-format": "{used:0.1f}/{total:0.1f} GB",
              "interval": 5
          },
          "disk": {
              "format": "  {percentage_used}%",
              "tooltip-format": "{specific_used:0.1f}/{specific_total:0.1f} GB",
              "unit": "GB",
              "interval": 10
          },
          "group/laptop": {
              "orientation": "horizontal",
              "modules": [
                  "backlight",
                  "battery"
              ]
          },
          "backlight": {
              "format": "{icon} {percent}%",
              "format-icons": ["", "", "", "", "", "", "", "", ""]
          },
          "battery": {
              "states": {
                  "warning": 30,
                  "critical": 15
              },
              "format": "{icon} {capacity}%",
              "format-charging": " {capacity}%",
              "format-plugged": " {capacity}%",
              "format-alt": "{icon} {time}",
              "format-icons": ["", "", "", "", ""]
          },
          "group/system": {
              "orientation": "horizontal",
              "modules": [
                  "pulseaudio",
                  "tray",
                  "clock",
                  "custom/power"
              ]
          },
          "pulseaudio": {
              "format": " {volume}%",
              "format-muted": " {volume}%",
              "format-bluetooth": "  {volume}% {format_source}",
              "format-bluetooth-muted": "  {format_source}",
              "scroll-step": 5,
              "on-click": "pavucontrol",
              "tooltip": false
          },
          "tray": {
              "show-passive-items": true,
              // "icon-size": 21,
              "spacing": 10
          },
          "clock": {
              "format": " {:%R}",
              "tooltip-format": "<tt><small>{calendar}</small></tt>",
              "calendar": {
                  "mode"          : "year",
                  "mode-mon-col"  : 4,
                  "format": {
                      "months":     "<span color='#ffead3'><b>{}</b></span>",
                      "days":       "<span color='#ecc6d9'><b>{}</b></span>",
                      "weeks":      "<span color='#99ffdd'><b>W{}</b></span>",
                      "weekdays":   "<span color='#ffcc66'><b>{}</b></span>",
                      "today":      "<span color='#ff6699'><b><u>{}</u></b></span>"
                  }
              }
          },
          "custom/power": {
              "format" : "⏻",
      		"tooltip": false,
      		"menu": "on-click",
      		"menu-file": "$HOME/.config/waybar/power_menu.xml",
      		"menu-actions": {
      			"shutdown": "systemctl poweroff",
      			"reboot": "systemctl reboot",
      			"suspend": "systemctl suspend",
      			"hibernate": "systemctl hibernate"
      		}
          }
      }
    '';

    home.file.".config/waybar/power_menu.xml".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <interface>
        <object class="GtkMenu" id="menu">
          <child>
      		<object class="GtkMenuItem" id="suspend">
      			<property name="label">Suspend</property>
              </object>
      	</child>
      	<child>
              <object class="GtkMenuItem" id="hibernate">
      			<property name="label">Hibernate</property>
              </object>
      	</child>
          <child>
              <object class="GtkMenuItem" id="shutdown">
      			<property name="label">Shutdown</property>
              </object>
          </child>
          <child>
            <object class="GtkSeparatorMenuItem" id="delimiter1"/>
          </child>
          <child>
      		<object class="GtkMenuItem" id="reboot">
      			<property name="label">Reboot</property>
      		</object>
          </child>
        </object>
      </interface>
    '';

    home.file.".config/waybar/style.css".text = ''
      /*color1: #e3b505;
      color2: #95190c;
      color3: #610345;
      color4: #107e7d;
      color5: #044b7f;
      */

      * {
          font-family: FontAwesome, Roboto, Helvetica, Arial, sans-serif;
          font-size: 13px;
      }

      /* -----------------------------------------------------------------------------
       * Base styles
       * -------------------------------------------------------------------------- */

      /* Bar */
      window#waybar {
          color: #ffffff;
          background-color: rgba(50, 50, 50, 0.5);
          border-bottom: 3px solid rgba(100, 114, 125, 0.5);
      }

      /* Buttons */
      button {
          box-shadow: inset 0 -3px transparent;
          border: none;
          border-radius: 0;
      }
      button:hover {
          background: inherit;
          box-shadow: inset 0 -3px #ffffff;
      }

      #workspaces button {
          color: #ffffff;
          background-color: transparent;
          padding: 0 5px;
      }
      #workspaces button.visible {
          background-color: rgba(80, 80, 80, 0.5);
          box-shadow: inset 0 -3px #ffffff;
      }

      /* Modules */
      #window,
      #workspaces {
          margin-left: 0;
      }
      #custom-crypto,
      #custom-openai-usage,
      #custom-gpu,
      #cpu,
      #memory,
      #disk,
      #backlight,
      #battery,
      #pulseaudio,
      #tray,
      #clock,
      #custom-power,

      /* -----------------------------------------------------------------------------
       * Module styles
       * -------------------------------------------------------------------------- */

      /* group/hardware */
      #module {
          color: #ffffff;
          padding-left: 10px;
          padding-right: 10px;
      }

      #custom-crypto:hover {
          box-shadow: inset 0 -3px #ffffff;
      }

      #custom-openai-usage:hover {
          box-shadow: inset 0 -3px #ffffff;
      }

      #custom-gpu:hover {
          box-shadow: inset 0 -3px #ffffff;
      }

      #cpu:hover {
          box-shadow: inset 0 -3px #ffffff;
      }

      #memory:hover {
          box-shadow: inset 0 -3px #ffffff;
      }

      #disk:hover {
          box-shadow: inset 0 -3px #ffffff;
      }

      #pulseaudio:hover {
          box-shadow: inset 0 -3px #ffffff;
      }

      #clock:hover {
          box-shadow: inset 0 -3px #ffffff;
      }

      #custom-power:hover {
          box-shadow: inset 0 -3px #ffffff;
      }
    '';
  };
}
