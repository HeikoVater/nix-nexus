{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.workstation.mount-nas;
in
{
  options.workstation.mount-nas = {
    enable = lib.mkEnableOption "NAS CIFS mount";

    host = lib.mkOption {
      type = lib.types.str;
      default = "192.168.188.7";
      description = "NAS host or IP address.";
    };

    share = lib.mkOption {
      type = lib.types.str;
      default = "share";
      description = "Remote CIFS share name.";
    };

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/share";
      description = "Local mount point.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "heikov";
      description = "Local owner for mounted files.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Local group for mounted files.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.host.secrets.enable;
        message = "workstation.mount-nas.enable requires host.secrets.enable so the CIFS credentials can be decrypted.";
      }
    ];

    # ─── CIFS Mount Support ───────────────────────────────────────
    environment.systemPackages = [ pkgs.cifs-utils ];

    fileSystems.${cfg.mountPoint} = {
      device = "//${cfg.host}/${cfg.share}";
      fsType = "cifs";
      options = [
        (lib.concatStringsSep "," [
          "x-systemd.automount"
          "noauto"
          "x-systemd.idle-timeout=60"
          "x-systemd.device-timeout=5s"
          "x-systemd.mount-timeout=5s"
          "credentials=${config.sops.secrets."smb-credentials".path}"
          "uid=${cfg.user}"
          "gid=${cfg.group}"
          "file_mode=0660"
          "dir_mode=0770"
          "nofail"
          "cache=strict"
          "actimeo=60"
          "vers=3.1.1"
        ])
      ];
    };
  };
}
