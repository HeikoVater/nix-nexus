{ lib, ... }:

{
  # ─── Fallback Root Filesystems ──────────────────────────────────
  # `hardware.facter.reportPath` overrides these values automatically once
  # `facter.json` exists for the host.
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-uuid/ee5be617-a4f0-49ff-8d9d-399fa0f0458d";
    fsType = "ext4";
  };

  swapDevices = lib.mkDefault [
    { device = "/dev/disk/by-uuid/10d7b0c7-37d6-4ae4-988a-fbc3c0748f97"; }
  ];
}
