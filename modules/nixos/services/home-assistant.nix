{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.home-assistant;
  configDir = config.services.home-assistant.configDir;
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  defaultSettings = {
    default_config = { };
    automation = "!include automations.yaml";
    script = "!include scripts.yaml";
    scene = "!include scenes.yaml";
    http = {
      server_host = "127.0.0.1";
      use_x_forwarded_for = true;
      trusted_proxies = [ "127.0.0.1" ];
    };
  };
  mqttConfigEntryBootstrap = lib.optionalString config.homelab.mosquitto.enable ''
    set -eu

    entries_file=${lib.escapeShellArg "${configDir}/.storage/core.config_entries"}
    password_file="''${CREDENTIALS_DIRECTORY}/mqtt-password"
    ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg "${configDir}/.storage"}
    umask 077

    now="$(${pkgs.coreutils}/bin/date --utc --iso-8601=seconds)"
    entry_id="$(${pkgs.coreutils}/bin/tr -d - < /proc/sys/kernel/random/uuid)"
    tmp="$(${pkgs.coreutils}/bin/mktemp "$entries_file.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT

    if [ -f "$entries_file" ]; then
      ${pkgs.jq}/bin/jq \
        --arg now "$now" \
        --arg entry_id "$entry_id" \
        --rawfile password "$password_file" \
        '
          def mqtt_data: {
            broker: "127.0.0.1",
            port: 1883,
            protocol: "5",
            username: "homeassistant",
            password: ($password | rtrimstr("\n") | rtrimstr("\r"))
          };
          def mqtt_entry: {
            created_at: $now,
            data: mqtt_data,
            disabled_by: null,
            discovery_keys: {},
            domain: "mqtt",
            entry_id: $entry_id,
            minor_version: 1,
            modified_at: $now,
            options: { discovery: true },
            pref_disable_new_entities: false,
            pref_disable_polling: false,
            source: "user",
            subentries: [],
            title: "Mosquitto broker",
            unique_id: null,
            version: 2
          };
          if .key != "core.config_entries" or (.data.entries | type) != "array" then
            error("unsupported Home Assistant config-entry storage format")
          elif any(.data.entries[]; .domain == "mqtt") then
            .data.entries |= map(
              if .domain == "mqtt" then
                .data = mqtt_data
                | .minor_version = 1
                | .modified_at = $now
                | .options = ((.options // {}) + { discovery: true })
                | .source = "user"
                | .title = "Mosquitto broker"
                | .version = 2
              else . end
            )
          else
            .data.entries += [mqtt_entry]
          end
        ' "$entries_file" > "$tmp"
    else
      ${pkgs.jq}/bin/jq \
        --arg now "$now" \
        --arg entry_id "$entry_id" \
        --rawfile password "$password_file" \
        -n '
          {
            version: 1,
            minor_version: 5,
            key: "core.config_entries",
            data: {
              entries: [{
                created_at: $now,
                data: {
                  broker: "127.0.0.1",
                  port: 1883,
                  protocol: "5",
                  username: "homeassistant",
                  password: ($password | rtrimstr("\n") | rtrimstr("\r"))
                },
                disabled_by: null,
                discovery_keys: {},
                domain: "mqtt",
                entry_id: $entry_id,
                minor_version: 1,
                modified_at: $now,
                options: { discovery: true },
                pref_disable_new_entities: false,
                pref_disable_polling: false,
                source: "user",
                subentries: [],
                title: "Mosquitto broker",
                unique_id: null,
                version: 2
              }]
            }
          }
        ' > "$tmp"
    fi

    ${pkgs.coreutils}/bin/chmod 0600 "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" "$entries_file"
    trap - EXIT
  '';
in
{
  options.homelab.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant";

    package = lib.mkOption {
      type = lib.types.package;
      default = unstable.home-assistant;
      defaultText = lib.literalExpression "inputs.nixpkgs-unstable.legacyPackages.<system>.home-assistant";
      description = "Home Assistant package to run.";
    };

    manageConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether Nix manages configuration.yaml. The default keeps application
        configuration mutable under /var/lib/hass.
      '';
    };

    requireExistingConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Refuse to start in mutable mode unless configuration.yaml already exists.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Home Assistant configuration merged over the module defaults.";
    };

    extraComponents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional Home Assistant integration domains to package.";
    };

    includeAllComponents = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Package every integration supported by the selected Home Assistant
        package. This is opt-in because a single broken third-party dependency
        can otherwise prevent the entire system from building.
      '';
    };

    excludedComponents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "noaa_tides"
        "raincloud"
        "sendgrid"
      ];
      description = ''
        Integrations excluded from the all-components closure because their
        dependencies are insecure or incompatible with the selected Python.
      '';
    };

    allowComponentPrivileges = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether packaged integrations may expand Home Assistant's capabilities,
        device access, groups, and address families.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = _: [ ];
      description = "Additional Python packages for Home Assistant integrations.";
    };

    customComponents = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Declaratively packaged custom Home Assistant integrations.";
    };

    customLovelaceModules = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Declaratively packaged custom Lovelace cards.";
    };

    discovery.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to allow mDNS and SSDP discovery traffic.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.home-assistant = {
      enable = true;
      configDir = "/var/lib/hass";
      inherit (cfg)
        package
        extraPackages
        customComponents
        customLovelaceModules
        ;

      extraComponents =
        (
          if cfg.includeAllComponents then
            lib.filter (component: !lib.elem component cfg.excludedComponents) cfg.package.availableComponents
          else
            [
              "default_config"
              "homekit_controller"
              "met"
              "mobile_app"
              "mqtt"
              "tuya"
              "webhook"
            ]
        )
        ++ cfg.extraComponents;

      config = if cfg.manageConfig then lib.recursiveUpdate defaultSettings cfg.settings else null;
    };

    services.caddy.virtualHosts."hass.${config.homelab.domain}" = {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:8123
      '';
    };

    networking.firewall.allowedUDPPorts = lib.optionals cfg.discovery.enable [
      1900 # SSDP
      5353 # mDNS
    ];

    users.users.hass.extraGroups = lib.mkIf (!cfg.allowComponentPrivileges) (lib.mkForce [ ]);

    systemd.services.home-assistant = lib.mkMerge [
      {
        wants = lib.optional config.homelab.mosquitto.enable "mosquitto.service";
        after = lib.optional config.homelab.mosquitto.enable "mosquitto.service";
        unitConfig.ConditionPathExists = lib.mkIf (
          !cfg.manageConfig && cfg.requireExistingConfig
        ) "${configDir}/configuration.yaml";
        serviceConfig.LoadCredential = lib.optional config.homelab.mosquitto.enable (
          "mqtt-password:${config.sops.secrets.mqtt_password_homeassistant.path}"
        );
      }
      (lib.mkIf (!cfg.manageConfig) {
        preStart = lib.mkForce mqttConfigEntryBootstrap;
      })
      (lib.mkIf (!cfg.allowComponentPrivileges) {
        serviceConfig = {
          AmbientCapabilities = lib.mkForce "";
          CapabilityBoundingSet = lib.mkForce "";
          DeviceAllow = lib.mkForce [ ];
          DevicePolicy = lib.mkForce "closed";
          PrivateDevices = lib.mkForce true;
          RestrictAddressFamilies = lib.mkForce [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
          ];
          SupplementaryGroups = lib.mkForce [ ];
          SystemCallFilter = lib.mkForce [
            "@system-service @pkey"
            "~@privileged @resources"
            "@chown"
            "mbind" # Required by NumPy/OpenBLAS during import.
          ];
        };
      })
    ];
  };
}
