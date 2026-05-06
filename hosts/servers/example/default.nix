# Example server configuration.
# Copy this directory to hosts/servers/<hostname>/ and customize.
# Then add the host to flake.nix nixosConfigurations.
#
# Replace all occurrences of "example" with your hostname/username.
{
  hostname,
  ...
}:

{
  imports = [
    ../common.nix
    ./hardware-configuration.nix
    # ./disko.nix  # if using declarative disk layout
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Home Manager
  # ═══════════════════════════════════════════════════════════════════
  # home-manager.users.example =
  #   {
  #     ...
  #   }:
  #   {
  #     imports = [ ../../../home/example/headless.nix ];
  #
  #     user.cli.sops-menu = {
  #       enable = true;
  #       secretsFile = ../../../secrets/users/example.yaml;
  #     };
  #   };

  # ═══════════════════════════════════════════════════════════════════
  #  Host Features
  # ═══════════════════════════════════════════════════════════════════
  # host.auto-upgrade.enable = true;

  # ═══════════════════════════════════════════════════════════════════
  #  Service Toggles
  # ═══════════════════════════════════════════════════════════════════
  homelab = {
    # hostIPv4 = "192.168.188.2"; # set this on statically addressed hosts
    # Optional override; defaults to "<hostname>.lan".
    # domain = "example.lan";
    pihole.enable = false;
    home-assistant.enable = false;
    mosquitto.enable = false;
    zigbee2mqtt.enable = false;
    backups.enable = false;
    coolercontrol.enable = false;
    homepage-dashboard.enable = false;
  };

  # ─── Basic System ──────────────────────────────────────────────
  networking.hostName = hostname;

  # ─── Networking ────────────────────────────────────────────────
  networking.useDHCP = true;

  # The shared modules set users.mutableUsers = false, so declare at
  # least one real user before first deploy or you'll lock yourself out.
  # users.users.example = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ];
  #   hashedPasswordFile = config.sops.secrets.example_password_hash.path;
  #   openssh.authorizedKeys.keys = [
  #     "ssh-ed25519 AAAA..."
  #   ];
  # };

  # Optional for single-user lab boxes. Leave this commented unless you
  # explicitly want passwordless sudo for wheel.
  # security.sudo.wheelNeedsPassword = false;

  # sops.defaultSopsFile = ../../../secrets/hosts/example.yaml;
  # sops.secrets.example_password_hash.neededForUsers = true;

  system.stateVersion = "25.11";
}
