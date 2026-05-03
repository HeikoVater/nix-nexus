{
  inputs,
  config,
  lib,
  modulesPath,
  ...
}:

let
  facterReport = ./facter.json;
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
    inputs.nixos-hardware.nixosModules.common-gpu-intel
  ];

  # ─── Host Hardware Features ─────────────────────────────────────
  workstation.wake-on-lan = {
    enable = true;
    interface = "enp0s31f6";
  };

  # ─── Hardware Detection ─────────────────────────────────────────
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists facterReport) facterReport;

  # ─── Bootloader ─────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-2301e646-c66a-45a8-982c-a0a68524d16b".device =
    "/dev/disk/by-uuid/2301e646-c66a-45a8-982c-a0a68524d16b";

  # ─── Graphics Stack ─────────────────────────────────────────────
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware = {
    nvidia = {
      open = false;
      modesetting.enable = true;
    };

    graphics = {
      enable = true;
      enable32Bit = true;
    };
  };

  # ─── Fallbacks ──────────────────────────────────────────────────
  boot.initrd.availableKernelModules = lib.mkDefault [
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];

  boot.initrd.kernelModules = lib.mkDefault [ ];
  boot.kernelModules = lib.mkDefault [ "kvm-intel" ];
  boot.extraModulePackages = lib.mkDefault [ ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
