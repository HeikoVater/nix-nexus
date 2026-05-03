{ lib, ... }:

{
  # ─── Fallback Root Filesystems ──────────────────────────────────
  # `hardware.facter.reportPath` overrides these values automatically once
  # `facter.json` exists for the host.
  fileSystems."/" = {
    device = "/dev/mapper/luks-fa74893f-5a57-4a87-a3a4-9b046af77452";
    fsType = "ext4";
  };

  boot.initrd.luks.devices."luks-fa74893f-5a57-4a87-a3a4-9b046af77452".device =
    "/dev/disk/by-uuid/fa74893f-5a57-4a87-a3a4-9b046af77452";

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/099A-D83B";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [
    { device = "/dev/mapper/luks-2301e646-c66a-45a8-982c-a0a68524d16b"; }
  ];
}
