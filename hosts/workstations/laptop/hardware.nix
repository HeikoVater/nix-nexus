{
  config,
  lib,
  modulesPath,
  inputs,
  ...
}:

let
  facterReport = ./facter.json;
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t430
  ];

  # ─── Hardware Detection ─────────────────────────────────────────
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists facterReport) facterReport;

  # ─── Bootloader ─────────────────────────────────────────────────
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    useOSProber = true;
  };

  # ─── Input Devices ──────────────────────────────────────────────
  services.libinput.enable = true;

  # ─── Fallbacks ──────────────────────────────────────────────────
  boot.initrd.availableKernelModules = lib.mkDefault [
    "xhci_pci"
    "ehci_pci"
    "ahci"
    "usb_storage"
    "sd_mod"
    "sr_mod"
    "sdhci_pci"
  ];

  boot.initrd.kernelModules = lib.mkDefault [ ];
  boot.kernelModules = lib.mkDefault [ ];
  boot.extraModulePackages = lib.mkDefault [ ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
