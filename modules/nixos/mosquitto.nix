{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.mosquitto;
in
{
  options.homelab.mosquitto = {
    enable = lib.mkEnableOption "Mosquitto MQTT broker";
  };

  config = lib.mkIf cfg.enable {
    # ─── Mosquitto (MQTT Broker) ──────────────────────────────────
    # Authenticated access with per-service credentials managed by
    # sops-nix. Passwords are decrypted at activation time to
    # /run/secrets/ and never stored in the Nix store.
    services.mosquitto = {
      enable = true;
      listeners = [
        {
          port = 1883;
          users = {
            homeassistant = {
              acl = [ "readwrite #" ];
              passwordFile = config.sops.secrets.mqtt_password_homeassistant.path;
            };
            zigbee2mqtt = {
              acl = [ "readwrite #" ];
              passwordFile = config.sops.secrets.mqtt_password_zigbee2mqtt.path;
            };
          };
        }
      ];
    };

    # Port 1883 is intentionally NOT opened in the firewall.
    # Only services on this host need to reach the broker.
    # If you need external MQTT access, add 1883 to allowedTCPPorts.
  };
}
