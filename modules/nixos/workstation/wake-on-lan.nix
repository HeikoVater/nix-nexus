{
  config,
  lib,
  ...
}:

let
  cfg = config.workstation.wake-on-lan;
in
{
  options.workstation.wake-on-lan = {
    enable = lib.mkEnableOption "Wake-on-LAN";

    interface = lib.mkOption {
      type = lib.types.str;
      description = "Network interface to enable Wake-on-LAN on.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking = {
      interfaces.${cfg.interface}.wakeOnLan.enable = true;
      firewall.allowedUDPPorts = [ 9 ];
    };
  };
}
