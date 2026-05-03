# Example WSL configuration.
# Copy this directory to hosts/wsl/<hostname>/ and customize.
{
  hostname,
  pkgs,
  ...
}:

{
  imports = [
    ../common.nix
  ];

  # ═══════════════════════════════════════════════════════════════════
  #  Home Manager
  # ═══════════════════════════════════════════════════════════════════
  # home-manager.users.example = import ../../../home/example/headless.nix;

  # ═══════════════════════════════════════════════════════════════════
  #  WSL Platform
  # ═══════════════════════════════════════════════════════════════════
  # Set this on the concrete host if you want a secret-free WSL user setup.
  # users.mutableUsers = true;

  wsl.defaultUser = "example";
  networking.hostName = hostname;

  users.users.example = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
  };

  system.stateVersion = "25.11";
}
