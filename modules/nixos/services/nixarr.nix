{
  config,
  lib,
  inputs,
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

  mkLocalProxyVhost = port: {
    extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:${toString port}
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

    # Keep the Arr API endpoints authenticated for remote clients while still
    # allowing local settings-sync jobs to talk to them over localhost.
    systemd.services.jellyfin.serviceConfig.UMask = lib.mkForce "0007";

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
        configuration = {
          sonarr = {
            "web-1080p-alternative" = {
              base_url = "http://127.0.0.1:8989";
              api_key = "!env_var SONARR_API_KEY";
              delete_old_custom_formats = true;
              quality_definition.type = "series";
              quality_profiles = [
                {
                  trash_id = "9d142234e45d6143785ac55f5a9e8dc9";
                  reset_unmatched_scores.enabled = true;
                }
              ];
              custom_format_groups = {
                add = [
                  {
                    trash_id = "158188097a58d7687dee647e04af0da3";
                    select = [
                      "47435ece6b99a0b477caf360e79ba0bb"
                    ];
                  }
                  {
                    trash_id = "85fae4a2294965b75710ef2989c850eb";
                    select = [
                      "218e93e5702f44a68ad9e3c6ba87d2f0"
                      "43b3cf48cb385cd3eac608ee6bca7f09"
                    ];
                  }
                  {
                    trash_id = "59c3af66780d08332fdc64e68297098f";
                    select = [
                      "15a05bc7c1a36e2b57fd628f8977e2fc"
                      "32b367365729d530ca1c124a0b180c64"
                      "85c61753df5da1fb2aab6f2a47426b09"
                      "6f808933a71bd9666531610cb8c059cc"
                      "fbcb31d8dabd2a319072b84fc0b7249c"
                      "9c11cd3f07101cdba90a2d81cf0e56b4"
                      "e2315f990da2e2cbfc9fa5b7a6fcfe48"
                      "23297a736ca77c0fc8e70f8edd7ee56c"
                    ];
                  }
                ];
              };
            };

            "web-2160p" = {
              base_url = "http://127.0.0.1:8989";
              api_key = "!env_var SONARR_API_KEY";
              delete_old_custom_formats = true;
              quality_definition.type = "series";
              quality_profiles = [
                {
                  trash_id = "d1498e7d189fbe6c7110ceaabb7473e6";
                  reset_unmatched_scores.enabled = true;
                }
              ];
              custom_format_groups = {
                add = [
                  {
                    trash_id = "e3f37512790f00d0e89e54fe5e790d1c";
                    select = [
                      "9b64dff695c2115facf1b6ea59c9bd07"
                    ];
                  }
                  {
                    trash_id = "85fae4a2294965b75710ef2989c850eb";
                    select = [
                      "218e93e5702f44a68ad9e3c6ba87d2f0"
                      "43b3cf48cb385cd3eac608ee6bca7f09"
                    ];
                  }
                  {
                    trash_id = "59c3af66780d08332fdc64e68297098f";
                    select = [
                      "15a05bc7c1a36e2b57fd628f8977e2fc"
                      "32b367365729d530ca1c124a0b180c64"
                      "85c61753df5da1fb2aab6f2a47426b09"
                      "6f808933a71bd9666531610cb8c059cc"
                      "fbcb31d8dabd2a319072b84fc0b7249c"
                      "9c11cd3f07101cdba90a2d81cf0e56b4"
                      "e2315f990da2e2cbfc9fa5b7a6fcfe48"
                      "23297a736ca77c0fc8e70f8edd7ee56c"
                    ];
                  }
                  {
                    trash_id = "d776a1ea912a117d66d83b880ff2055d";
                  }
                ];
              };
            };
          };

          radarr = {
            "hd-bluray-web" = {
              base_url = "http://127.0.0.1:7878";
              api_key = "!env_var RADARR_API_KEY";
              delete_old_custom_formats = true;
              quality_definition.type = "movie";
              quality_profiles = [
                {
                  trash_id = "d1d67249d3890e49bc12e275d989a7e9";
                  reset_unmatched_scores.enabled = true;
                }
              ];
              custom_format_groups = {
                add = [
                  {
                    trash_id = "f8bf8eab4617f12dfdbd16303d8da245";
                    select = [
                      "dc98083864ea246d05a42df0d05f81cc"
                    ];
                  }
                  {
                    trash_id = "a3ac6af01d78e4f21fcb75f601ac96df";
                    select = [
                      "b8cd450cbfa689c0259a01d9e29ba3d6"
                      "cae4ca30163749b891686f95532519bd"
                      "b6832f586342ef70d9c128d40c07b872"
                      "cc444569854e9de0b084ab2b8b1532b2"
                      "ed38b889b31be83fda192888e2286d83"
                      "0a3f082873eb454bde444150b70253cc"
                      "e6886871085226c3da1830830146846c"
                      "90a6f9a284dff5103f6346090e6280c8"
                      "e204b80c87be9497a8a6eaff48f72905"
                      "712d74cd88bceb883ee32f773656b1f5"
                      "bfd8eb01832d646a0a89c4deb46f8564"
                    ];
                  }
                ];
              };
            };

            "uhd-bluray-web" = {
              base_url = "http://127.0.0.1:7878";
              api_key = "!env_var RADARR_API_KEY";
              delete_old_custom_formats = true;
              quality_definition.type = "movie";
              quality_profiles = [
                {
                  trash_id = "64fb5f9858489bdac2af690e27c8f42f";
                  reset_unmatched_scores.enabled = true;
                }
              ];
              custom_format_groups = {
                add = [
                  {
                    trash_id = "ff204bbcecdd487d1cefcefdbf0c278d";
                    select = [
                      "839bea857ed2c0a8e084f3cbdbd65ecb"
                    ];
                  }
                  {
                    trash_id = "a3ac6af01d78e4f21fcb75f601ac96df";
                    select = [
                      "b8cd450cbfa689c0259a01d9e29ba3d6"
                      "cae4ca30163749b891686f95532519bd"
                      "b6832f586342ef70d9c128d40c07b872"
                      "cc444569854e9de0b084ab2b8b1532b2"
                      "ed38b889b31be83fda192888e2286d83"
                      "0a3f082873eb454bde444150b70253cc"
                      "e6886871085226c3da1830830146846c"
                      "90a6f9a284dff5103f6346090e6280c8"
                      "e204b80c87be9497a8a6eaff48f72905"
                      "712d74cd88bceb883ee32f773656b1f5"
                      "bfd8eb01832d646a0a89c4deb46f8564"
                    ];
                  }
                  {
                    trash_id = "7fc2751eef7e6bdc70b74136e5e35c76";
                  }
                ];
              };
            };
          };
        };
      };
    };
  };
}
