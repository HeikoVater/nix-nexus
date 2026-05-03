{
  config,
  lib,
  ...
}:

{
  # ─── sops-nix ─────────────────────────────────────────────────
  # Hosts opt into sops-nix by enabling `host.secrets.enable`. The actual
  # secret declarations live in `secrets-config.nix`, which is only imported
  # on hosts that also pull in the upstream sops-nix module.
  #
  # Each host must set sops.defaultSopsFile in its own config:
  #   sops.defaultSopsFile = ../../secrets/hosts/<hostname>.yaml;
  #
  # User password hashes and other host-specific secrets are also
  # declared in the host config. This module only declares secrets
  # shared across all hosts (service passwords, backup passphrases).
  options.host.secrets = {
    enable = lib.mkEnableOption "sops-nix host secrets";

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/persist/var/lib/sops-nix/key.txt";
      description = "Path to the age key used by sops-nix on this host.";
    };
  };
}
