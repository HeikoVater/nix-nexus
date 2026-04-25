{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.home-assistant;
in
{
  options.homelab.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # ─── Base Home Assistant Configuration ────────────────────────
    {
      services.home-assistant = {
        enable = true;
        configDir = "/var/lib/hass";

        package = pkgs.home-assistant.override {
          extraPackages =
            ps: with ps; [
              # Add any Python deps your integrations need here
            ];
        };

        extraComponents = [
          "default_config" # bundles ~20 defaults (history, logbook, frontend, sun, etc.)
          "met" # Met.no weather — no API key, works out of the box
          "mobile_app" # HA companion app (iOS/Android)
          "webhook" # required by mobile_app for notifications/location
          "mqtt" # MQTT client — talks to Mosquitto / Zigbee2MQTT
        ];

        # We keep `config` minimal — only infrastructure settings (http
        # binding, trusted proxies) are set from Nix when behind a proxy.
        # Everything else (automations, dashboards, integrations) lives
        # in HA's own configuration.yaml for manual / UI-driven edits.
        #
        # MQTT credentials: configure via HA UI after first boot:
        #   Settings → Integrations → MQTT → Configure
        #   Broker: localhost, Port: 1883
        #   Username: homeassistant
        #   Password: <value from secrets/secrets.yaml mqtt_password_homeassistant>
      };

      # Give the hass user access to serial devices (/dev/ttyUSB*, /dev/zigbee)
      users.users.hass.extraGroups = [ "dialout" ];
    }

    # ─── Behind Caddy: bind to localhost, register proxy route ────
    (lib.mkIf config.homelab.caddy.enable {
      services.home-assistant.config.http = {
        server_host = "127.0.0.1";
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" ];
      };

      services.caddy.virtualHosts."hass.${config.homelab.caddy.domain}" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:8123
        '';
      };
    })

    # ─── No Caddy: expose directly on the network ────────────────
    (lib.mkIf (!config.homelab.caddy.enable) {
      services.home-assistant.openFirewall = true; # opens port 8123
    })
  ]);
}
