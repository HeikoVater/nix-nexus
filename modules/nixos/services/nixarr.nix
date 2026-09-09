{
  config,
  lib,
  inputs,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.homelab.nixarr;

  transmissionHost = "transmission.${config.homelab.domain}";
  prowlarrHost = "prowlarr.${config.homelab.domain}";
  sonarrHost = "sonarr.${config.homelab.domain}";
  radarrHost = "radarr.${config.homelab.domain}";
  lidarrHost = "lidarr.${config.homelab.domain}";
  bazarrHost = "bazarr.${config.homelab.domain}";
  jellyfinHost = "jellyfin.${config.homelab.domain}";
  seerrHost = "seerr.${config.homelab.domain}";

  mediaMountUnit = "${utils.escapeSystemdPath (toString cfg.mediaDir)}.mount";
  mediaServices = [
    "bazarr"
    "jellyfin"
    "lidarr"
    "radarr"
    "sonarr"
    "transmission"
  ];

  mkLocalProxyVhost = port: {
    extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:${toString port}
    '';
  };

  recyclarrQualityProfile = {
    name = "HD-1080p";
    reset_unmatched_scores.enabled = true;
    min_format_score = 1;
    min_upgrade_format_score = 1;
    upgrade = {
      allowed = false;
      until_quality = "Bluray-1080p";
      until_score = 100;
    };
    quality_sort = "top";
    qualities = [
      { name = "Bluray-1080p"; }
      { name = "WEBDL-1080p"; }
      { name = "WEBRip-1080p"; }
      { name = "HDTV-1080p"; }
    ];
  };

  mkRecyclarrQualityDefinition = type: {
    inherit type;

    # Values are MB per minute. Keep HDTV/WEB close to the current live
    # settings and only loosen Bluray a bit so better 1080p encodes fit.
    qualities = [
      {
        name = "HDTV-1080p";
        min = 10;
        preferred = 30;
        max = 100;
      }
      {
        name = "WEBDL-1080p";
        min = 10;
        preferred = 30;
        max = 100;
      }
      {
        name = "WEBRip-1080p";
        min = 10;
        preferred = 30;
        max = 100;
      }
      {
        name = "Bluray-1080p";
        min = 20;
        preferred = 50;
        max = 150;
      }
    ];
  };

  mkRecyclarrInstance =
    {
      baseUrl,
      apiKey,
      qualityType,
      x264TrashId,
      x265TrashId,
      av1TrashId,
    }:
    {
      base_url = baseUrl;
      api_key = apiKey;
      delete_old_custom_formats = true;
      quality_definition = mkRecyclarrQualityDefinition qualityType;
      quality_profiles = [ recyclarrQualityProfile ];
      custom_formats = [
        {
          trash_ids = [ x264TrashId ];
          assign_scores_to = [
            {
              name = recyclarrQualityProfile.name;
              score = 50;
            }
          ];
        }
        {
          trash_ids = [ x265TrashId ];
          assign_scores_to = [
            {
              name = recyclarrQualityProfile.name;
              score = 100;
            }
          ];
        }
        {
          trash_ids = [ av1TrashId ];
          assign_scores_to = [
            {
              name = recyclarrQualityProfile.name;
              score = -10000;
            }
          ];
        }
      ];
    };

  recyclarr = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.recyclarr;
  recyclarrPackage = pkgs.writeShellApplication {
    name = "recyclarr";
    text = ''
      args=()
      while (( $# )); do
        if [[ "$1" == "--app-data" ]]; then
          export RECYCLARR_CONFIG_DIR="$2"
          export RECYCLARR_DATA_DIR="$2"
          shift 2
        else
          args+=("$1")
          shift
        fi
      done

      exec ${lib.getExe recyclarr} "''${args[@]}"
    '';
  };
in
{
  imports = [ inputs.nixarr.nixosModules.default ];

  options.homelab.nixarr = {
    enable = lib.mkEnableOption "Nixarr media stack";

    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = "/tank/media";
      description = "Root media directory shared by the Nixarr stack.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/nixarr";
      description = "Persistent state directory for the Nixarr stack.";
    };

    transmissionPeerPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      example = 15570;
      description = "Forwarded VPN peer port for Transmission.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.transmissionPeerPort != null;
        message = "homelab.nixarr.transmissionPeerPort must be set to the AirVPN forwarded port.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${toString cfg.stateDir}' 0755 root root - -"
    ];

    # Never let media consumers run against the underlying mountpoint
    # directory if the media dataset is unavailable or gets unmounted.
    systemd.services = lib.genAttrs mediaServices (
      service:
      {
        unitConfig = {
          RequiresMountsFor = [ (toString cfg.mediaDir) ];
          BindsTo = [ mediaMountUnit ];
          After = [ mediaMountUnit ];
        };
      }
      // lib.optionalAttrs (service == "jellyfin") {
        serviceConfig.UMask = lib.mkForce "0007";
      }
    );

    services = {
      sonarr.settings.auth.required = "DisabledForLocalAddresses";
      radarr.settings.auth.required = "DisabledForLocalAddresses";
      lidarr.settings.auth.required = "DisabledForLocalAddresses";
      prowlarr.settings.auth.required = "DisabledForLocalAddresses";

      caddy.virtualHosts = {
        "${transmissionHost}" = mkLocalProxyVhost config.nixarr.transmission.uiPort;
        "${prowlarrHost}" = mkLocalProxyVhost config.nixarr.prowlarr.port;
        "${sonarrHost}" = mkLocalProxyVhost config.nixarr.sonarr.port;
        "${radarrHost}" = mkLocalProxyVhost config.nixarr.radarr.port;
        "${lidarrHost}" = mkLocalProxyVhost config.nixarr.lidarr.port;
        "${bazarrHost}" = mkLocalProxyVhost config.nixarr.bazarr.port;
        "${jellyfinHost}" = mkLocalProxyVhost config.nixarr.jellyfin.port;
        "http://${jellyfinHost}" = {
          extraConfig = ''
            reverse_proxy 127.0.0.1:${toString config.nixarr.jellyfin.port}
          '';
        };
        "${seerrHost}" = mkLocalProxyVhost config.nixarr.seerr.port;
        "http://${seerrHost}" = {
          extraConfig = ''
            reverse_proxy 127.0.0.1:${toString config.nixarr.seerr.port}
          '';
        };
      };
    };

    nixarr = {
      enable = true;
      mediaDir = cfg.mediaDir;
      stateDir = cfg.stateDir;
      mediaUsers = [ "heikov" ];

      vpn = {
        enable = true;
        wgConf = config.sops.secrets.airvpn_wg_conf.path;
        exposeOnLAN = false;
        proxyListenAddr = "127.0.0.1";
      };

      transmission = {
        enable = true;
        peerPort = cfg.transmissionPeerPort;
        flood.enable = true;
        extraSettings = {
          rpc-host-whitelist = transmissionHost;
          rpc-host-whitelist-enabled = true;
        };
        vpn.enable = true;
        vpn.configureNginx = true;

        # TODO: Enable privateTrackers.cross-seed later using only private
        # Prowlarr indexer IDs once those trackers are configured.
      };

      prowlarr = {
        enable = true;
        settings-sync = {
          enable-nixarr-apps = true;
          sonarr.enable = true;
          radarr.enable = true;
          lidarr.enable = true;
        };
      };

      sonarr = {
        enable = true;
        settings-sync.transmission.enable = true;
      };

      radarr = {
        enable = true;
        settings-sync.transmission.enable = true;
      };

      lidarr.enable = true;

      bazarr = {
        enable = true;
        settings-sync = {
          sonarr.enable = true;
          radarr.enable = true;
        };
      };

      jellyfin.enable = true;
      seerr.enable = true;

      recyclarr = {
        enable = true;
        # Nixarr still passes Recyclarr 7's --app-data flag. The wrapper maps
        # it to the environment variables required by Recyclarr 8.
        package = recyclarrPackage;
        configuration = {
          sonarr = {
            sonarr_hd_1080p = mkRecyclarrInstance {
              baseUrl = "http://127.0.0.1:8989";
              apiKey = "!env_var SONARR_API_KEY";
              qualityType = "series";
              x264TrashId = "cddfb4e32db826151d97352b8e37c648";
              x265TrashId = "c9eafd50846d299b862ca9bb6ea91950";
              av1TrashId = "15a05bc7c1a36e2b57fd628f8977e2fc";
            };
          };

          radarr = {
            radarr_hd_1080p = mkRecyclarrInstance {
              baseUrl = "http://127.0.0.1:7878";
              apiKey = "!env_var RADARR_API_KEY";
              qualityType = "movie";
              x264TrashId = "2899d84dc9372de3408e6d8cc18e9666";
              x265TrashId = "9170d55c319f4fe40da8711ba9d8050d";
              av1TrashId = "cae4ca30163749b891686f95532519bd";
            };
          };
        };
      };
    };
  };
}
