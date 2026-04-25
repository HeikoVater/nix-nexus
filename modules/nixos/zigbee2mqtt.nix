{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.zigbee2mqtt;
in
{
  options.homelab.zigbee2mqtt = {
    enable = lib.mkEnableOption "Zigbee2MQTT";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # ─── Base Zigbee2MQTT Configuration ───────────────────────────
    {
      assertions = [
        {
          assertion = config.homelab.mosquitto.enable;
          message = "Zigbee2MQTT requires Mosquitto. Set homelab.mosquitto.enable = true.";
        }
      ];

      # ── Zigbee USB Stick ──────────────────────────────────────────
      # Sonoff Zigbee 3.0 Plus uses Silicon Labs CP2102N: 10c4:ea60
      # This udev rule creates a stable /dev/zigbee symlink so the
      # path never changes even if other USB devices are plugged in.
      services.udev.extraRules = ''
        SUBSYSTEM=="tty", \
        ATTRS{idVendor}=="10c4", \
        ATTRS{idProduct}=="ea60", \
        SYMLINK+="zigbee", \
        MODE="0660", \
        GROUP="dialout"
      '';

      services.zigbee2mqtt = {
        enable = true;
        settings = {
          # homeassistant discovery is enabled by default upstream
          permit_join = false; # flip to true in the frontend to pair new devices

          mqtt = {
            server = "mqtt://localhost:1883";
            user = "zigbee2mqtt";
            # Password is injected by the preStart script below;
            # do NOT set it here (it would end up in the Nix store).
          };

          serial = {
            port = "/dev/zigbee"; # stable udev symlink
            adapter = "ezsp"; # Sonoff Zigbee 3.0 Plus uses EZSP (EFR32)
          };

          frontend = {
            enabled = true;
            port = 8080;
          };

          advanced = {
            log_level = "info";
            # Zigbee2MQTT generates network_key on first start.
            # Back up /var/lib/zigbee2mqtt/configuration.yaml afterward
            # — it contains the network key needed to re-pair devices.
          };
        };
      };

      # Inject the MQTT password into Z2M's config file before startup.
      # The NixOS module generates the base config; this patches in the
      # secret without putting it in the Nix store.
      systemd.services.zigbee2mqtt.preStart = lib.mkAfter ''
        PASSWORD=$(cat ${config.sops.secrets.mqtt_password_zigbee2mqtt.path})
        ${pkgs.yq-go}/bin/yq -i ".mqtt.password = \"$PASSWORD\"" \
          /var/lib/zigbee2mqtt/configuration.yaml
      '';

      # Zigbee2MQTT needs dialout for serial access
      users.users.zigbee2mqtt.extraGroups = [ "dialout" ];
    }

    # ─── Behind Caddy: bind to localhost, register proxy route ────
    (lib.mkIf config.homelab.caddy.enable {
      services.zigbee2mqtt.settings.frontend.host = "127.0.0.1";

      services.caddy.virtualHosts."z2m.${config.homelab.caddy.domain}" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:8080
        '';
      };
    })

    # ─── No Caddy: expose directly on the network ────────────────
    (lib.mkIf (!config.homelab.caddy.enable) {
      services.zigbee2mqtt.settings.frontend.host = "0.0.0.0";
      networking.firewall.allowedTCPPorts = [ 8080 ];
    })
  ]);
}
