{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.zigbee2mqtt;
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  dataDir = config.services.zigbee2mqtt.dataDir;
  mqttSecretFile = "/run/zigbee2mqtt/secret.yaml";
  mqttSecretLink = "${dataDir}/secret.yaml";
  requiredStateFiles =
    (lib.optional (!cfg.manageConfig && cfg.requireExistingConfig) "${dataDir}/configuration.yaml")
    ++ (lib.optional (!cfg.manageConfig && cfg.requireExistingDatabase) "${dataDir}/database.db");
  defaultSettings = {
    permit_join = false;
    mqtt = {
      server = "mqtt://localhost:1883";
      user = cfg.mqtt.user;
      password = "!secret.yaml password";
    };
    serial = {
      port = cfg.serial.port;
    }
    // lib.optionalAttrs (cfg.serial.adapter != null) {
      adapter = cfg.serial.adapter;
    };
    frontend = {
      enabled = true;
      host = "127.0.0.1";
      port = cfg.frontendPort;
    };
    advanced = {
      log_level = "info";
    }
    // lib.optionalAttrs (cfg.networkKeySecret != null) {
      network_key = "!secret.yaml network_key";
    };
  };
in
{
  options.homelab.zigbee2mqtt = {
    enable = lib.mkEnableOption "Zigbee2MQTT";

    package = lib.mkOption {
      type = lib.types.package;
      default = unstable.zigbee2mqtt;
      defaultText = lib.literalExpression "inputs.nixpkgs-unstable.legacyPackages.<system>.zigbee2mqtt";
      description = "Zigbee2MQTT package to run.";
    };

    manageConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether Nix manages configuration.yaml. The default keeps application
        configuration mutable under /var/lib/zigbee2mqtt.
      '';
    };

    serial = {
      port = lib.mkOption {
        type = lib.types.str;
        default = "/dev/ttyUSB0";
        description = "Stable path to the Zigbee coordinator.";
      };

      adapter = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Zigbee2MQTT adapter driver, or null for auto-detection.";
      };
    };

    mqtt = {
      user = lib.mkOption {
        type = lib.types.str;
        default = "zigbee2mqtt";
        description = "MQTT username used by Zigbee2MQTT.";
      };

    };

    networkKeySecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional sops secret containing the Zigbee network key as a YAML flow
        sequence. The value is injected into a runtime-only secret file.
      '';
    };

    frontendPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Local Zigbee2MQTT frontend port.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Zigbee2MQTT settings merged over the module defaults.";
    };

    requireExistingDatabase = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Refuse to start unless database.db already exists in the data directory.";
    };

    requireExistingConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Refuse to start in mutable mode unless configuration.yaml already exists.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.mosquitto.enable;
        message = "Zigbee2MQTT requires Mosquitto. Set homelab.mosquitto.enable = true.";
      }
      {
        assertion = cfg.networkKeySecret == null || config.host.secrets.enable;
        message = "A Zigbee2MQTT network key secret requires host.secrets.enable.";
      }
    ];

    services.zigbee2mqtt = {
      enable = true;
      inherit (cfg) package;
      settings = lib.recursiveUpdate defaultSettings cfg.settings;
    };

    services.caddy.virtualHosts."z2m.${config.homelab.domain}" = {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:${toString cfg.frontendPort}
      '';
    };

    systemd.services.zigbee2mqtt = {
      wants = [ "mosquitto.service" ];
      after = [ "mosquitto.service" ];
      unitConfig.ConditionPathExists = lib.mkIf (requiredStateFiles != [ ]) requiredStateFiles;
      serviceConfig = {
        RuntimeDirectory = "zigbee2mqtt";
        RuntimeDirectoryMode = "0700";
        RestartSec = 10;
      }
      // lib.optionalAttrs (!cfg.manageConfig) {
        DeviceAllow = lib.mkForce [
          "char-ttyACM rw"
          "char-ttyAMA rw"
          "char-ttyUSB rw"
        ];
        DevicePolicy = lib.mkForce "closed";
      };

      # In mutable mode this replaces the upstream preStart that would
      # overwrite configuration.yaml on every service start.
      preStart =
        if cfg.manageConfig then
          lib.mkAfter ''
            set -eu

            export PASSWORD=$(cat ${lib.escapeShellArg config.sops.secrets.mqtt_password_zigbee2mqtt.path})
            umask 077

            ${
              if cfg.networkKeySecret == null then
                "${pkgs.yq-go}/bin/yq -n '.password = strenv(PASSWORD)' > ${lib.escapeShellArg mqttSecretFile}"
              else
                ''
                  export NETWORK_KEY=$(cat ${lib.escapeShellArg config.sops.secrets.${cfg.networkKeySecret}.path})
                  ${pkgs.yq-go}/bin/yq -n \
                    '.password = strenv(PASSWORD) | .network_key = env(NETWORK_KEY)' \
                    > ${lib.escapeShellArg mqttSecretFile}
                  unset NETWORK_KEY
                ''
            }
            ln -sfn ${lib.escapeShellArg mqttSecretFile} ${lib.escapeShellArg mqttSecretLink}
            unset PASSWORD
          ''
        else
          lib.mkForce "";
    };
  };
}
