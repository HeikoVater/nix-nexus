{
  config,
  lib,
  ...
}:

{
  # ─── sops-nix ─────────────────────────────────────────────────
  # Decrypts secrets at activation time into /run/secrets/<name>.
  # The key file must exist on the server before first deploy.
  # See .sops.yaml in the repo root for setup instructions.
  #
  # Secrets are declared conditionally — only services that are
  # actually enabled will have their secrets decrypted.
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
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
