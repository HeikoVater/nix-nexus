{
  config,
  lib,
  ...
}:

let
  cfg = config.workstation.audio;
in
{
  options.workstation.audio = {
    enable = lib.mkEnableOption "PipeWire audio stack";
  };

  config = lib.mkIf cfg.enable {
    # ─── PipeWire Audio ────────────────────────────────────────────
    services = {
      pulseaudio.enable = false;
      pipewire = {
        enable = true;
        alsa = {
          enable = true;
          support32Bit = true;
        };
        pulse.enable = true;
      };
    };

    security.rtkit.enable = true;
  };
}
