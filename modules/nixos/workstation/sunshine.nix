{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.workstation.sunshine;
in
{
  options.workstation.sunshine = {
    enable = lib.mkEnableOption "Sunshine game streaming";
  };

  config = lib.mkIf cfg.enable {
    # ─── Sunshine Streaming ────────────────────────────────────────
    # Sunshine runs as a user service and needs `/dev/uinput` access to
    # inject virtual controller input for Moonlight clients.
    hardware.uinput.enable = true;

    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
      applications.apps = [
        {
          name = "Desktop";
          image-path = "desktop.png";
        }
        {
          name = "RetroArch";
          detached = [ "${lib.getExe pkgs.retroarch}" ];
          image-path = "retroarch.png";
        }
        {
          name = "Steam Big Picture";
          detached = [ "setsid steam steam://open/bigpicture" ];
          prep-cmd = [
            {
              do = "";
              undo = "setsid steam steam://close/bigpicture";
            }
          ];
          image-path = "steam.png";
        }
        {
          name = "Pegasus";
          detached = [ "${lib.getExe pkgs.pegasus-frontend}" ];
          image-path = "pegasus-fe.png";
        }
      ];
    };
  };
}
