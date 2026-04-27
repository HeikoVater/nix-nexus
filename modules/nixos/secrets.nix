{
  config,
  lib,
  ...
}:

{
  # ─── sops-nix ─────────────────────────────────────────────────
  # Decrypts secrets at activation time. User password hashes stay in sops and
  # are made available early enough for declarative user creation.
  # The age key must exist on the server before first deploy.
  # See .sops.yaml in the repo root for setup instructions.
  #
  # Each host must set sops.defaultSopsFile in its own config:
  #   sops.defaultSopsFile = ../../secrets/hosts/<hostname>.yaml;
  #
  # User password hashes and other host-specific secrets are also
  # declared in the host config. This module only declares secrets
  # shared across all hosts (service passwords, backup passphrases).
  sops = {
    defaultSopsFormat = "yaml";

    # Read the age key directly from /persist so password hashes can be
    # decrypted before impermanence mounts /var/lib/sops-nix.
    age.keyFile = "/persist/var/lib/sops-nix/key.txt";

    secrets = lib.mkMerge [
      (lib.mkIf config.homelab.mosquitto.enable {
        mqtt_password_homeassistant = {
          owner = "mosquitto";
        };
        mqtt_password_zigbee2mqtt = {
          owner = "zigbee2mqtt";
          restartUnits = lib.optional config.homelab.zigbee2mqtt.enable "zigbee2mqtt.service";
        };
      })

      (lib.mkIf config.homelab.backups.enable {
        borg_passphrase = { };
      })

      (lib.mkIf config.homelab.pihole.enable {
        pihole_web_password_hash = {
          restartUnits = [ "pihole-ftl.service" ];
        };
      })
    ];
  };
}
