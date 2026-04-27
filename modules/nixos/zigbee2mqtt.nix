{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.zigbee2mqtt;
  dataDir = config.services.zigbee2mqtt.dataDir;
  mqttSecretFile = "/run/zigbee2mqtt/secret.yaml";
  mqttSecretLink = "${dataDir}/secret.yaml";
in
{
  options.homelab.zigbee2mqtt.enable = lib.mkEnableOption "Zigbee2MQTT";

  config = lib.mkIf cfg.enable {
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
          # Keep the password out of persisted configuration.yaml.
          # Zigbee2MQTT resolves this from secret.yaml in the data dir.
          password = "!secret.yaml password";
        };

        serial = {
          port = "/dev/zigbee"; # stable udev symlink
          adapter = "ezsp"; # Sonoff Zigbee 3.0 Plus uses EZSP (EFR32)
        };

        frontend = {
          enabled = true;
          host = "127.0.0.1";
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

    services.caddy.virtualHosts."z2m.${config.homelab.domain}" = {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:8080
      '';
    };

    systemd.services.zigbee2mqtt.serviceConfig = {
      RuntimeDirectory = "zigbee2mqtt";
      RuntimeDirectoryMode = "0700";
    };

    # Generate a runtime-only secret file and point Zigbee2MQTT at it.
    # This keeps the plaintext MQTT password out of the persisted data dir.
    systemd.services.zigbee2mqtt.preStart = lib.mkAfter ''
      set -eu

      export PASSWORD=$(cat ${lib.escapeShellArg config.sops.secrets.mqtt_password_zigbee2mqtt.path})
      umask 077

      ${pkgs.yq-go}/bin/yq -n '.password = strenv(PASSWORD)' > ${lib.escapeShellArg mqttSecretFile}
      ln -sfn ${lib.escapeShellArg mqttSecretFile} ${lib.escapeShellArg mqttSecretLink}
      unset PASSWORD
    '';

    # Zigbee2MQTT needs dialout for serial access
    users.users.zigbee2mqtt.extraGroups = [ "dialout" ];
  };
}
