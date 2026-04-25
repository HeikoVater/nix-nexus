{
  config,
  lib,
  ...
}:

{
  # ─── sops-nix ─────────────────────────────────────────────────
  # Decrypts secrets at activation time into /run/secrets/<name>.
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

    # Path to the age key on the server (created during setup)
    age.keyFile = "/var/lib/sops-nix/key.txt";

    secrets = lib.mkMerge [
      (lib.mkIf config.homelab.mosquitto.enable {
        mqtt_password_homeassistant = {
          owner = "mosquitto";
        };
        mqtt_password_zigbee2mqtt = {
          owner = "zigbee2mqtt";
        };
      })

      (lib.mkIf config.homelab.backups.enable {
        borg_passphrase = { };
      })
    ];
  };
}
