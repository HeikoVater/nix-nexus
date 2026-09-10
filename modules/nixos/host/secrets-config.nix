{
  config,
  lib,
  ...
}:

let
  mountNas = config.workstation.mount-nas.enable;
  display = config.workstation.display.enable;
  immichNsfw = config.homelab.immich.nsfw;
  immichNsfwSecretNames = lib.unique (
    [
      immichNsfw.sourceApiKeySecret
    ]
    ++ lib.optional (immichNsfw.mode == "dual-account") immichNsfw.targetApiKeySecret
    ++ lib.optional immichNsfw.review.enable immichNsfw.review.passwordSecret
  );
  immichNsfwRestartUnits = [
    "immich-nsfw-scan.service"
  ]
  ++ lib.optional immichNsfw.review.enable "immich-nsfw-review.service";
  cfg = config.host.secrets;
in
{
  config = lib.mkIf cfg.enable {
    sops = {
      defaultSopsFormat = "yaml";

      age.keyFile = cfg.ageKeyFile;

      secrets = lib.mkMerge [
        (lib.mkIf config.homelab.mosquitto.enable {
          mqtt_password_homeassistant = {
            owner = "mosquitto";
          };
          mqtt_password_zigbee2mqtt = {
            owner = "zigbee2mqtt";
            restartUnits = lib.optional config.homelab.zigbee2mqtt.enable "zigbee2mqtt.service";
          };
        })

        (lib.mkIf config.homelab.backups.enable {
          borg_passphrase = { };
        })

        (lib.mkIf config.homelab.pihole.enable {
          pihole_web_password_hash = {
            restartUnits = [ "pihole-ftl.service" ];
          };
        })

        (lib.mkIf config.homelab.samba.enable {
          "samba_password_${config.homelab.samba.user}" = {
            restartUnits = [ "samba-smbd.service" ];
          };
        })

        (lib.mkIf mountNas {
          smb_credentials = { };
        })

        (lib.mkIf display {
          crypto_tracker_api_key = {
            group = "users";
            mode = "0440";
          };
        })

        (lib.mkIf config.homelab.nixarr.enable {
          airvpn_wg_conf = { };
        })

        (lib.mkIf immichNsfw.enable (
          lib.genAttrs immichNsfwSecretNames (_: {
            owner = "immich-nsfw";
            restartUnits = immichNsfwRestartUnits;
          })
        ))
      ];
    };
  };
}
