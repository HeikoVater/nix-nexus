{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.homepage-dashboard;
  zfsCfg = cfg.zfs;
  hasZfs = config.boot.supportedFilesystems.zfs or false;

  homepageHost = "homepage.${config.homelab.domain}";
  trustHost = "trust.${config.homelab.domain}";
  homepagePort = config.services.homepage-dashboard.listenPort;
  homepagePortString = toString homepagePort;

  homepageStatusPort = 38181;
  homepageStatusPortString = toString homepageStatusPort;
  homepageStatusRoot = "/var/lib/homepage-dashboard-api";

  domainSuffix = ".${config.homelab.domain}";

  proxiedHosts = lib.pipe config.services.caddy.virtualHosts [
    builtins.attrNames
    (builtins.filter (
      host: lib.hasSuffix domainSuffix host && host != homepageHost && !(lib.hasInfix "://" host)
    ))
    lib.unique
  ];

  trustDocs = pkgs.writeTextDir "trust/index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Trust the local Caddy CA</title>
        <style>
          body {
            font-family: system-ui, sans-serif;
            line-height: 1.5;
            margin: 2rem auto;
            max-width: 48rem;
            padding: 0 1rem;
          }

          code {
            background: #f3f4f6;
            border-radius: 0.25rem;
            padding: 0.1rem 0.3rem;
          }
        </style>
      </head>
      <body>
        <h1>Trust the local Caddy CA</h1>
        <p>
          Install this certificate once on each device that should trust
          <code>*.${config.homelab.domain}</code>.
        </p>
        <ol>
          <li><a href="/root.crt">Download the root certificate</a>.</li>
          <li>Import it into your device's trusted root certificate store.</li>
          <li>Reopen your browser and visit <a href="https://${homepageHost}">https://${homepageHost}</a>.</li>
        </ol>
        <p>Quick hints:</p>
        <ul>
          <li><strong>NixOS:</strong> add the PEM file to <code>security.pki.certificateFiles</code>.</li>
          <li><strong>Windows:</strong> import it into <code>Trusted Root Certification Authorities</code>.</li>
          <li><strong>Apple devices:</strong> install the certificate profile and mark it trusted.</li>
          <li><strong>Firefox:</strong> it may use its own trust store unless configured to use the OS store.</li>
        </ul>
        <p>
          Server path: <code>/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt</code>
        </p>
      </body>
    </html>
  '';

  serviceMetadata = {
    pihole = {
      description = "DNS filtering";
      group = "Core Services";
      icon = "pi-hole.png";
      name = "Pi-hole";
      siteMonitor = "http://127.0.0.1:8081/admin/";
    };
    hass = {
      description = "Home automation";
      group = "Automation";
      icon = "home-assistant.png";
      name = "Home Assistant";
      siteMonitor = "http://127.0.0.1:8123/";
    };
    z2m = {
      description = "Zigbee devices";
      group = "Automation";
      icon = "zigbee2mqtt.png";
      name = "Zigbee2MQTT";
      siteMonitor = "http://127.0.0.1:8080/";
    };
    coolercontrol = {
      description = "Cooling control";
      group = "Cooling Control";
      icon = "mdi-fan";
      name = "CoolerControl";
      siteMonitor = "http://127.0.0.1:11987/";
    };
    paperless = {
      description = "Document archive";
      group = "Other Services";
      icon = "paperless-ngx.png";
      name = "Paperless";
      siteMonitor = "http://127.0.0.1:28981/";
    };
    immich = {
      description = "Photo and video library";
      group = "Other Services";
      icon = "immich.png";
      name = "Immich";
      siteMonitor = "http://127.0.0.1:2283/";
    };
  };

  groupSpecs = [
    {
      name = "Core Services";
      tab = "Overview";
      icon = "mdi-home-analytics";
      columns = 3;
    }
    {
      name = "Automation";
      tab = "Overview";
      icon = "mdi-robot-outline";
      columns = 3;
    }
    {
      name = "Cooling Control";
      tab = "Cooling";
      icon = "mdi-fan";
      columns = 3;
    }
    {
      name = "Thermals";
      tab = "Cooling";
      icon = "mdi-thermometer";
      columns = 2;
    }
    {
      name = "ZFS Summary";
      tab = "Storage";
      icon = "mdi-harddisk";
      columns = 2;
    }
    {
      name = "Datasets";
      tab = "Storage";
      icon = "mdi-database";
      columns = 2;
    }
    {
      name = "Operations";
      tab = "Ops";
      icon = "mdi-wrench-clock";
      columns = 2;
    }
    {
      name = "Other Services";
      tab = "Overview";
      icon = "mdi-view-grid-outline";
      columns = 3;
    }
  ];

  serviceGroupOrder = map (spec: spec.name) groupSpecs;

  zfsHiddenMountpointCases = lib.concatMapStrings (mountpoint: ''
    ${lib.escapeShellArg mountpoint})
      return 0
      ;;
  '') zfsCfg.hiddenMountpoints;

  zfsLabelOverrideCases = lib.concatStrings (
    lib.mapAttrsToList (mountpoint: label: ''
      ${lib.escapeShellArg mountpoint})
        printf '%s' ${lib.escapeShellArg label}
        return 0
        ;;
    '') zfsCfg.labelOverrides
  );

  mkSnapshotService =
    description: script: extraConfig:
    {
      inherit description;
      serviceConfig.Type = "oneshot";
      script = ''
        ${lib.getExe script} ${lib.escapeShellArg homepageStatusRoot}
      '';
    }
    // extraConfig;

  mkSnapshotTimer = onBootSec: onUnitActiveSec: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = onBootSec;
      OnUnitActiveSec = onUnitActiveSec;
      Persistent = true;
    };
  };

  coolingSnapshotScript = pkgs.writeShellApplication {
    name = "homepage-dashboard-export-cooling";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.lm_sensors
    ];
    text = ''
      set -euo pipefail

      out_dir="$1"
      tmp_file="$(mktemp "$out_dir/cooling.json.XXXXXX")"
      sensors_json="$(sensors -j 2>/dev/null || printf '{}')"

      temps_json="$(${pkgs.jq}/bin/jq '
        def dimm_label(chip):
          if chip | endswith("-51") then "DIMM 1"
          elif chip | endswith("-53") then "DIMM 2"
          else "DIMM"
          end;

        def temp_rank(sensorLabel):
          if sensorLabel == "CPU Control" then 10
          elif sensorLabel | test("^CPU CCD [0-9]+$") then 20 + ((sensorLabel | capture("^CPU CCD (?<index>[0-9]+)$").index) | tonumber)
          elif sensorLabel == "CPU Die" then 30
          elif sensorLabel == "CPU Package" then 40
          elif sensorLabel == "System" then 50
          elif sensorLabel == "NVMe" then 60
          elif sensorLabel | test("^NVMe Sensor [0-9]+$") then 60 + ((sensorLabel | capture("^NVMe Sensor (?<index>[0-9]+)$").index) | tonumber)
          elif sensorLabel | test("^DIMM [0-9]+$") then 70 + ((sensorLabel | capture("^DIMM (?<index>[0-9]+)$").index) | tonumber)
          elif sensorLabel | test("^GPU ") then 80
          else 90
          end;

        def clean_temp_label(chip; sensorLabel):
          if chip | test("^spd5118-") then
            dimm_label(chip)
          elif chip | test("^nvme-") then
            if sensorLabel == "Composite" then "NVMe"
            elif sensorLabel == "Sensor 1" then "NVMe Sensor 1"
            elif sensorLabel == "Sensor 2" then "NVMe Sensor 2"
            else "NVMe " + sensorLabel
            end
          else
            sensorLabel
            | sub("^Package id 0$"; "CPU Package")
            | sub("^CPUTIN$"; "CPU")
            | sub("^SYSTIN$"; "System")
            | sub("^AUXTIN[0-9]*$"; "Auxiliary")
            | sub("^Tctl$"; "CPU Control")
            | sub("^Tdie$"; "CPU Die")
            | (
              if test("^Tccd[0-9]+$") then
                "CPU CCD " + (capture("^Tccd(?<index>[0-9]+)$").index)
              else
                .
              end
            )
            | sub("^edge$"; "GPU Edge")
            | sub("^junction$"; "GPU Junction")
            | sub("^temp[0-9]+$"; "Temperature")
          end;

        [
          to_entries[]
          | select(.value | type == "object")
          | .key as $chip
          | .value
          | to_entries[]
          | select(.value | type == "object")
          | .key as $label
          | .value as $props
          | ($props | to_entries | map(select(.key | endswith("_input"))) | first? | .value) as $input
          | select($input != null)
          | select(($label | test("(?i)^fan")) | not)
          | select(
              (($props | keys | join(" ")) | test("_crit|_max|_alarm"))
              or ($label | test("(?i)(cpu|package|tdie|tctl|tccd|temp|sys|board|composite|edge|junction|pch|vrm)"))
            )
          | {
              label: clean_temp_label($chip; $label),
              value: ($input | tonumber)
            }
        ]
        | map(. + { rank: temp_rank(.label) })
        | sort_by(.rank, .label)
        | .[:8]
        | if length == 0 then
            [{ label: "No thermal sensors", text: "Unavailable" }]
          else
            map(del(.rank) | . + {
              text: ((((.value * 10) | round) / 10 | tostring) + " C")
            })
          end
      ' <<< "$sensors_json")"

      fans_json="$(${pkgs.jq}/bin/jq '
        def fan_rank(sensorLabel):
          if sensorLabel | test("^Fan [0-9]+$") then
            (sensorLabel | capture("^Fan (?<index>[0-9]+)$").index | tonumber)
          else
            999
          end;

        [
          to_entries[]
          | select(.value | type == "object")
          | .value
          | to_entries[]
          | select(.value | type == "object")
          | .key as $label
          | .value as $props
          | ($props | to_entries | map(select(.key | endswith("_input"))) | first? | .value) as $input
          | select($input != null)
          | select($label | test("(?i)^fan"))
          | {
              label: ($label | sub("(?i)^fan"; "Fan ")),
              value: ($input | tonumber)
            }
          | select(.value > 0)
        ]
        | map(. + { rank: fan_rank(.label) })
        | sort_by(.rank, .label)
        | .[:6]
        | if length == 0 then
            [{ label: "No fan telemetry", text: "Unavailable" }]
          else
            map(del(.rank) | . + {
              text: ((.value | round | tostring) + " RPM")
            })
          end
      ' <<< "$sensors_json")"

      ${pkgs.jq}/bin/jq -n \
        --argjson temps "$temps_json" \
        --argjson fans "$fans_json" \
        '{
          temps: $temps,
          fans: $fans
        }' > "$tmp_file"

      chmod 0644 "$tmp_file"
      mv "$tmp_file" "$out_dir/cooling.json"
    '';
  };

  zfsSnapshotScript = pkgs.writeShellApplication {
    name = "homepage-dashboard-export-zfs";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.coreutils
      pkgs.gawk
      pkgs.jq
    ];
    text = ''
            set -euo pipefail

            out_dir="$1"
            tmp_file="$(mktemp "$out_dir/zfs.json.XXXXXX")"

            format_bytes() {
              numfmt --to=iec-i --suffix=B --format="%.1f" "$1"
            }

            percent_used() {
              awk -v used="$1" -v total="$2" 'BEGIN {
                if (total <= 0) {
                  print "0"
                } else {
                  printf "%.0f", (used / total) * 100
                }
              }'
            }

            mountpoint_hidden() {
              case "$1" in
      ${zfsHiddenMountpointCases}          *)
                  return 1
                  ;;
              esac
            }

            dataset_label() {
              local mountpoint="$1"
              local leaf

              case "$mountpoint" in
      ${zfsLabelOverrideCases}          *)
                  ;;
              esac

              if [ "$mountpoint" = "/" ]; then
                leaf="root"
              else
                leaf="''${mountpoint##*/}"
              fi

              leaf="''${leaf//-/ }"
              leaf="''${leaf//_/ }"

              printf '%s' "$leaf" | awk '
                {
                  for (i = 1; i <= NF; i++) {
                    $i = toupper(substr($i, 1, 1)) tolower(substr($i, 2))
                  }
                  print
                }
              '
            }

            pools_json="$({
              while IFS=$'\t' read -r name size alloc free health; do
                [ -n "$name" ] || continue

                used_text="$(format_bytes "$alloc")"
                size_text="$(format_bytes "$size")"
                free_text="$(format_bytes "$free")"
                percent="$(percent_used "$alloc" "$size")"

                ${pkgs.jq}/bin/jq -cn \
                  --arg name "$name" \
                  --arg summary "$health | $used_text / $size_text used ($percent%)" \
                  --arg health "$health" \
                  --arg used "$used_text" \
                  --arg total "$size_text" \
                  --arg free "$free_text" \
                  --arg percent "$percent" \
                  '{
                    name: $name,
                    summary: $summary,
                    health: $health,
                    used: $used,
                    total: $total,
                    free: $free,
                    percent: $percent
                  }'
              done < <(zpool list -Hp -o name,size,alloc,free,health 2>/dev/null || true)
            } | ${pkgs.jq}/bin/jq -s '
              if length == 0 then
                [{ name: "Unavailable", summary: "No imported pools detected" }]
              else
                .
              end
            ')"

            datasets_json="$({
              while IFS=$'\t' read -r name used avail mountpoint; do
                case "$mountpoint" in
                  none|legacy|-|"")
                    continue
                    ;;
                  /*)
                    ;;
                  *)
                    continue
                    ;;
                esac

                if mountpoint_hidden "$mountpoint"; then
                  continue
                fi

                label="$(dataset_label "$mountpoint")"

                total=$((used + avail))
                used_text="$(format_bytes "$used")"
                total_text="$(format_bytes "$total")"
                free_text="$(format_bytes "$avail")"
                percent="$(percent_used "$used" "$total")"

                ${pkgs.jq}/bin/jq -cn \
                  --arg name "$label" \
                  --arg dataset "$name" \
                  --arg mountpoint "$mountpoint" \
                  --arg summary "$used_text / $total_text used ($percent%)" \
                  --arg free "$free_text" \
                  '{
                    name: $name,
                    dataset: $dataset,
                    mountpoint: $mountpoint,
                    summary: $summary,
                    free: $free
                  }'
              done < <((zfs list -Hp -o name,used,avail,mountpoint 2>/dev/null || true) | sort -t $'\t' -k4,4)
            } | ${pkgs.jq}/bin/jq -s '.')"

            datasets_json="$(printf '%s' "$datasets_json" | ${pkgs.jq}/bin/jq '
              if length == 0 then
                [{ name: "No mounted datasets", summary: "Nothing tracked" }]
              else
                .
              end
            ')"

            if printf '%s' "$pools_json" | ${pkgs.jq}/bin/jq -e 'all(.[]; has("health"))' >/dev/null; then
              attention_count="$(printf '%s' "$pools_json" | ${pkgs.jq}/bin/jq '[.[] | select(.health != "ONLINE")] | length')"
              if [ "$attention_count" = "0" ]; then
                overall="Healthy"
                attention="All pools are ONLINE"
              else
                overall="Needs attention"
                attention="$attention_count pool(s) are not ONLINE"
              fi
            else
              overall="Unavailable"
              attention="Pool health unavailable"
            fi

            ${pkgs.jq}/bin/jq -n \
              --arg overall "$overall" \
              --arg attention "$attention" \
              --argjson pools "$pools_json" \
              --argjson datasets "$datasets_json" \
              '{
                overall: $overall,
                attention: $attention,
                pools: $pools,
                datasets: $datasets
              }' > "$tmp_file"

            chmod 0644 "$tmp_file"
            mv "$tmp_file" "$out_dir/zfs.json"
    '';
  };

  backupSnapshotScript = pkgs.writeShellApplication {
    name = "homepage-dashboard-export-backup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      out_dir="$1"
      tmp_file="$(mktemp "$out_dir/backup.json.XXXXXX")"

      write_snapshot() {
        ${pkgs.jq}/bin/jq -n \
          --arg summary "$1" \
          --arg lastRun "$2" \
          --arg nextRun "$3" \
          --arg detail "$4" \
          '{
            summary: $summary,
            lastRun: $lastRun,
            nextRun: $nextRun,
            detail: $detail
          }' > "$tmp_file"

          chmod 0644 "$tmp_file"
          mv "$tmp_file" "$out_dir/backup.json"
      }
    ''
    + lib.optionalString (!config.homelab.backups.enable) ''
      write_snapshot "Disabled" "Never" "Not scheduled" "Borg backup is not enabled on this host"
    ''
    + lib.optionalString config.homelab.backups.enable ''
      service="borgbackup-job-${config.networking.hostName}.service"
      timer="borgbackup-job-${config.networking.hostName}.timer"

      prop() {
        local unit="$1"
        local property="$2"

        systemctl show "$unit" --property="$property" --value 2>/dev/null || true
      }

      clean_value() {
        local value="$1"
        local fallback="$2"

        if [ -z "$value" ] || [ "$value" = "n/a" ]; then
          printf '%s' "$fallback"
        else
          printf '%s' "$value"
        fi
      }

      timer_active="$(prop "$timer" ActiveState)"
      next_run="$(clean_value "$(prop "$timer" NextElapseUSecRealtime)" "Not scheduled")"
      last_trigger="$(clean_value "$(prop "$timer" LastTriggerUSec)" "Never")"

      service_active="$(prop "$service" ActiveState)"
      service_result="$(prop "$service" Result)"
      service_status="$(clean_value "$(prop "$service" ExecMainStatus)" "0")"

      if [ -z "$timer_active$service_active" ]; then
        summary="Unavailable"
        detail="Backup units were not found"
      elif [ "$service_active" = "active" ]; then
        summary="Running"
        detail="Borg is writing a new archive"
      elif [ "$timer_active" != "active" ]; then
        summary="Paused"
        detail="The backup timer is not active"
      elif [ "$last_trigger" = "Never" ]; then
        summary="Scheduled"
        detail="Waiting for the first scheduled run"
      elif [ "$service_result" = "success" ]; then
        summary="Healthy"
        detail="Last run completed successfully"
      elif [ -n "$service_result" ]; then
        summary="Attention"
        detail="Last result: $service_result (exit $service_status)"
      else
        summary="Idle"
        detail="Waiting for the next scheduled run"
      fi

      write_snapshot "$summary" "$last_trigger" "$next_run" "$detail"
    '';
  };

  mkServiceDefinition =
    host:
    let
      prefix = lib.removeSuffix domainSuffix host;
      metadata =
        serviceMetadata.${prefix} or {
          description = "Web service";
          group = "Other Services";
          icon = "mdi-web";
          name = prefix;
          siteMonitor = null;
        };
    in
    {
      inherit (metadata) group;
      card = {
        "${metadata.name}" = lib.filterAttrs (_: value: value != null) {
          description = metadata.description;
          href = "https://${host}";
          icon = metadata.icon;
          siteMonitor = metadata.siteMonitor;
        };
      };
    };

  serviceDefinitions = [
    {
      group = "Core Services";
      card = {
        Homepage = {
          description = "Homelab dashboard";
          href = "https://${homepageHost}";
          icon = "homepage.png";
          siteMonitor = "http://127.0.0.1:${homepagePortString}/";
        };
      };
    }
  ]
  ++ map mkServiceDefinition proxiedHosts;

  groupedServices = lib.groupBy (item: item.group) serviceDefinitions;

  discoveredGroups = lib.concatMap (
    groupName:
    let
      cards = map (item: item.card) (groupedServices.${groupName} or [ ]);
    in
    lib.optional (cards != [ ]) { "${groupName}" = cards; }
  ) serviceGroupOrder;

  customApiUrl = name: "http://127.0.0.1:${homepageStatusPortString}/${name}.json";
  homepageApiUrl = path: "http://127.0.0.1:${homepagePortString}${path}";

  thermalGroups = lib.optionals config.homelab.coolercontrol.enable [
    {
      Thermals = [
        {
          Temperatures = {
            description = "CPU, NVMe, and RAM";
            icon = "mdi-thermometer-lines";
            widget = {
              type = "customapi";
              url = customApiUrl "cooling";
              refreshInterval = 60000;
              display = "dynamic-list";
              mappings = {
                items = "temps";
                name = "label";
                label = "text";
                limit = 8;
              };
            };
          };
        }
        {
          Fans = {
            description = "Current fan RPM";
            icon = "mdi-fan-chevron-up";
            widget = {
              type = "customapi";
              url = customApiUrl "cooling";
              refreshInterval = 60000;
              display = "dynamic-list";
              mappings = {
                items = "fans";
                name = "label";
                label = "text";
                limit = 6;
              };
            };
          };
        }
      ];
    }
  ];

  zfsGroups = lib.optionals hasZfs [
    {
      "ZFS Summary" = [
        {
          "Pool Health" = {
            description = "Hourly pool health";
            icon = "mdi-shield-check-outline";
            widget = {
              type = "customapi";
              url = customApiUrl "zfs";
              refreshInterval = 3600000;
              display = "list";
              mappings = [
                {
                  field = "overall";
                  label = "Status";
                }
                {
                  field = "attention";
                  label = "Attention";
                }
              ];
            };
          };
        }
        {
          "Pool Capacity" = {
            description = "Hourly pool usage";
            icon = "mdi-harddisk";
            widget = {
              type = "customapi";
              url = customApiUrl "zfs";
              refreshInterval = 3600000;
              display = "dynamic-list";
              mappings = {
                items = "pools";
                name = "name";
                label = "summary";
                limit = 6;
              };
            };
          };
        }
      ];
    }
    {
      Datasets = [
        {
          "Mounted Datasets" = {
            description = "Auto-discovered mountpoints";
            icon = "mdi-database-eye";
            widget = {
              type = "customapi";
              url = customApiUrl "zfs";
              refreshInterval = 3600000;
              display = "dynamic-list";
              mappings = {
                items = "datasets";
                name = "name";
                label = "summary";
                limit = 12;
              };
            };
          };
        }
      ];
    }
  ];

  operationsGroups = [
    {
      Operations = [
        {
          "Trust Local CA" = {
            description = "Download the Caddy root certificate and install notes";
            href = "http://${trustHost}";
            icon = "mdi-certificate-outline";
          };
        }
        {
          "Host Uptime" = {
            description = "Current uptime";
            icon = "mdi-timer-outline";
            widget = {
              type = "customapi";
              url = homepageApiUrl "/api/widgets/resources?type=uptime";
              refreshInterval = 60000;
              display = "list";
              mappings = [
                {
                  field = "uptime";
                  label = "Uptime";
                  format = "duration";
                }
              ];
            };
          };
        }
        {
          "Backup Status" = {
            description = "Systemd backup status";
            icon = "mdi-backup-restore";
            widget = {
              type = "customapi";
              url = customApiUrl "backup";
              refreshInterval = 300000;
              display = "list";
              mappings = [
                {
                  field = "summary";
                  label = "State";
                }
                {
                  field = "lastRun";
                  label = "Last Run";
                }
                {
                  field = "nextRun";
                  label = "Next Run";
                }
                {
                  field = "detail";
                  label = "Detail";
                }
              ];
            };
          };
        }
      ];
    }
  ];

  homepageGroups = discoveredGroups ++ thermalGroups ++ zfsGroups ++ operationsGroups;

  configuredGroupNames = map (group: builtins.head (builtins.attrNames group)) homepageGroups;

  homepageLayout = map (spec: {
    "${spec.name}" = {
      columns = spec.columns;
      icon = spec.icon;
      style = "row";
      tab = spec.tab;
      useEqualHeights = true;
    };
  }) (builtins.filter (spec: lib.elem spec.name configuredGroupNames) groupSpecs);
in
{
  options.homelab.homepage-dashboard = {
    enable = lib.mkEnableOption "Homepage Dashboard";

    zfs = {
      hiddenMountpoints = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        example = [ "/var/lib/postgresql" ];
        description = "Mounted ZFS paths to exclude from the dashboard dataset list.";
      };

      labelOverrides = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = {
          "/tank/safe/immich" = "Immich";
          "/tank/safe/paperless" = "Paperless";
          "/nix" = "Nix Store";
          "/persist" = "Persist";
          "/var/lib/postgresql" = "PostgreSQL";
        };
        example = {
          "/srv/photos" = "Photos";
          "/tank/media" = "Media";
        };
        description = "Friendly labels for auto-discovered ZFS mountpoints on the dashboard.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.pihole-ftl.settings.misc.dnsmasq_lines = lib.mkIf config.homelab.pihole.enable [
      "address=/${trustHost}/${config.homelab.hostIPv4}"
    ];

    systemd.tmpfiles.rules = [ "d ${homepageStatusRoot} 0755 root root -" ];

    systemd.services.homepage-dashboard-export-backup =
      mkSnapshotService "Export Homepage backup snapshot" backupSnapshotScript
        { };

    systemd.timers.homepage-dashboard-export-backup = mkSnapshotTimer "2m" "10m";

    systemd.services.homepage-dashboard-export-cooling = lib.mkIf config.homelab.coolercontrol.enable (
      mkSnapshotService "Export Homepage cooling snapshot" coolingSnapshotScript { }
    );

    systemd.timers.homepage-dashboard-export-cooling = lib.mkIf config.homelab.coolercontrol.enable (
      mkSnapshotTimer "90s" "1m"
    );

    systemd.services.homepage-dashboard-export-zfs = lib.mkIf hasZfs (
      mkSnapshotService "Export Homepage ZFS snapshot" zfsSnapshotScript {
        after = [ "zfs.target" ];
        wants = [ "zfs.target" ];
      }
    );

    systemd.timers.homepage-dashboard-export-zfs = lib.mkIf hasZfs (mkSnapshotTimer "3m" "1h");

    services.homepage-dashboard = {
      enable = true;

      # Homepage validates the Host header even behind a reverse proxy,
      # so allow the public Caddy hostname in addition to local access.
      allowedHosts = lib.concatStringsSep "," [
        homepageHost
        "localhost:${homepagePortString}"
        "127.0.0.1:${homepagePortString}"
      ];

      openFirewall = false;

      services = homepageGroups;

      settings = {
        color = "slate";
        description = "Homelab operations dashboard for ${config.networking.hostName}";
        disableCollapse = true;
        disableIndexing = true;
        disableUpdateCheck = true;
        fullWidth = true;
        headerStyle = "boxedWidgets";
        hideErrors = true;
        hideVersion = true;
        iconStyle = "theme";
        layout = homepageLayout;
        statusStyle = "dot";
        target = "_self";
        theme = "dark";
        title = "${config.networking.hostName} Dashboard";
        useEqualHeights = true;
      };

      widgets = [
        {
          datetime = {
            text_size = "xl";
            locale = "de-DE";
            format = {
              day = "2-digit";
              month = "2-digit";
              year = "numeric";
              hour = "2-digit";
              minute = "2-digit";
              hourCycle = "h23";
            };
          };
        }
        {
          resources = {
            label = "System";
            cpu = true;
            memory = true;
            refresh = 10000;
          };
        }
        {
          resources = {
            label = "Network";
            network = true;
            refresh = 10000;
          };
        }
      ];
    };

    # Keep Homepage's raw listener off the LAN and publish it through
    # the shared HTTPS entrypoint instead.
    services.caddy.virtualHosts."${homepageHost}" = {
      extraConfig = ''
        tls internal
        reverse_proxy localhost:${homepagePortString}
      '';
    };

    services.caddy.virtualHosts."http://${trustHost}" = {
      logFormat = null;
      extraConfig = ''
        root * ${trustDocs}/trust
        handle /root.crt {
          root * /var/lib/caddy/.local/share/caddy/pki/authorities/local
          file_server
        }
        file_server
      '';
    };

    # Homepage fetches these tiny local JSON snapshots via customapi.
    # The data is generated on timers so the dashboard is not polling
    # ZFS or system state directly on every page refresh.
    services.caddy.virtualHosts."http://127.0.0.1:${homepageStatusPortString}" = {
      logFormat = null;
      extraConfig = ''
        bind 127.0.0.1
        @homepageSnapshots path /backup.json /cooling.json /zfs.json
        handle @homepageSnapshots {
          root * ${homepageStatusRoot}
          file_server
        }
        respond "Not found" 404
      '';
    };
  };
}
