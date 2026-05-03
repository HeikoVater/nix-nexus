# Example hardware configuration.
# Generate with: nixos-generate-config --show-hardware-config
# Replace this file with the output for your specific hardware.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Replace with your actual hardware config
}
