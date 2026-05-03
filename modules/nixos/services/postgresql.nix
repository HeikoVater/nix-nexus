{
  config,
  lib,
  ...
}:

let
  paperless = config.homelab.paperless;
  immich = config.homelab.immich;
in
{
  config = lib.mkIf (paperless.enable || immich.enable) {
    services.postgresql.initdbArgs = lib.mkDefault [ "--data-checksums" ];
  };
}
