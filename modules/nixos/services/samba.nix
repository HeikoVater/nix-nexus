{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.samba;
  sharePath = toString cfg.sharePath;
  shareSetupService = "samba-share-setup.service";
  shareGroup = config.users.users.${cfg.user}.group;
  secretName = "samba_password_${cfg.user}";
  installBin = lib.getExe' pkgs.coreutils "install";
  chownBin = lib.getExe' pkgs.coreutils "chown";
  chmodBin = lib.getExe' pkgs.coreutils "chmod";
  grepBin = lib.getExe' pkgs.gnugrep "grep";
  pdbeditBin = lib.getExe' config.services.samba.package "pdbedit";
  smbpasswdBin = lib.getExe' config.services.samba.package "smbpasswd";
in
{
  options.homelab.samba = {
    enable = lib.mkEnableOption "Samba file sharing";

    shareName = lib.mkOption {
      type = lib.types.str;
      default = "share";
      description = "SMB share name exposed on the LAN.";
    };

    sharePath = lib.mkOption {
      type = lib.types.path;
      default = "/tank/share";
      description = "Local path exported over SMB.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "heikov";
      description = "Local Unix account mapped to SMB writes.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.host.secrets.enable;
        message = "homelab.samba.enable requires host.secrets.enable so the Samba password secret can be decrypted.";
      }
      {
        assertion = builtins.hasAttr cfg.user config.users.users;
        message = "homelab.samba.user must refer to a declared local user.";
      }
    ];

    services.samba = {
      enable = true;
      openFirewall = false;
      nmbd.enable = false;
      winbindd.enable = false;

      settings = {
        global = {
          "disable netbios" = "yes";
          "server string" = config.networking.hostName;
        };

        ${cfg.shareName} = {
          path = sharePath;
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = cfg.user;
          "force user" = cfg.user;
          "force group" = shareGroup;
          "create mask" = "0660";
          "directory mask" = "0770";
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 445 ];

    systemd.services.samba-smbd = {
      requires = [ shareSetupService ];
      after = [ shareSetupService ];
    };

    systemd.services.samba-share-setup = {
      description = "Prepare Samba share and credentials";
      before = [ "samba-smbd.service" ];
      after = [ "local-fs.target" ];
      unitConfig.RequiresMountsFor = [
        sharePath
        "/var/lib/samba"
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        umask 077

        ${installBin} -d -m 0770 ${lib.escapeShellArg sharePath}
        ${chownBin} ${lib.escapeShellArg "${cfg.user}:${shareGroup}"} ${lib.escapeShellArg sharePath}
        ${chmodBin} 0770 ${lib.escapeShellArg sharePath}

        password="$(< ${lib.escapeShellArg config.sops.secrets.${secretName}.path})"

        if ${pdbeditBin} -L | ${grepBin} -q '^${cfg.user}:'; then
          printf '%s\n%s\n' "$password" "$password" | ${smbpasswdBin} -s ${lib.escapeShellArg cfg.user}
        else
          printf '%s\n%s\n' "$password" "$password" | ${smbpasswdBin} -s -a ${lib.escapeShellArg cfg.user}
        fi
      '';
    };
  };
}
