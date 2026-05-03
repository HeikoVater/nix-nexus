# Example hardware configuration.
# Generate with: nixos-generate-config --show-hardware-config
# Replace this file with the output for your specific hardware.
{
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
