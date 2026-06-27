{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.immich;
  nsfw = cfg.nsfw;
  immichHost = "immich.${config.homelab.domain}";
  immichPort = 2283;
  mediaLocation = toString cfg.mediaLocation;
  setupService = "immich-storage-setup.service";
  installBin = lib.getExe' pkgs.coreutils "install";
  chownBin = lib.getExe' pkgs.coreutils "chown";
  chmodBin = lib.getExe' pkgs.coreutils "chmod";
  python = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.requests ]);
  nudeNetVersion = "3.4.2";
  nudeNetWheel = pkgs.stdenvNoCC.mkDerivation {
    pname = "nudenet-wheel";
    version = nudeNetVersion;
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/1c/ee/1aa02d44ba958cc77e16ff1e41a0aac5e721037db7bf62b9c9d124917f87/nudenet-${nudeNetVersion}-py3-none-any.whl";
      hash = "sha256-WTfb2E5djl3gOPCP/qWhu1CghHV3a/K0eVkUzg6vAzE=";
    };
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/${pkgs.python3.sitePackages}"
      ${lib.getExe pkgs.unzip} -q "$src" -d "$out/${pkgs.python3.sitePackages}"
      runHook postInstall
    '';
  };
  nudeNet640m = pkgs.fetchurl {
    name = "640m.onnx";
    url = "https://api.github.com/repos/notAI-tech/NudeNet/releases/assets/176832019";
    curlOptsList = [
      "-H"
      "Accept: application/octet-stream"
    ];
    hash = "sha256-BP49d5gHgMH4KX3G1/lC/Vs6vmlCoYj3QqhSQeT2NOs=";
  };
  nudeNetDetectorArgs =
    if nsfw.classifier.model == "640m" then
      ''model_path="${nudeNet640m}", inference_resolution=640''
    else
      "";
  nudeNetPython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.numpy
    pythonPackages.onnxruntime
    pythonPackages.opencv4
  ]);
  nudeNetClassifierScript = pkgs.writeText "immich-nsfw-nudenet.py" ''
    import json
    import sys

    import cv2
    from nudenet import NudeDetector

    cv2.setNumThreads(${toString nsfw.classifier.threads})

    detector = NudeDetector(${nudeNetDetectorArgs})
    results = []
    for image_path in sys.argv[1:]:
        image = cv2.imread(image_path)
        if image is None:
            raise SystemExit(f"unable to read image: {image_path}")

        height, width = image.shape[:2]
        results.append({
            "detections": detector.detect(image_path),
            "image_width": width,
            "image_height": height,
        })
    print(json.dumps(results[0] if len(results) == 1 else results))
  '';
  immichNsfwNudeNet = pkgs.writeShellApplication {
    name = "immich-nsfw-nudenet";
    text = ''
      export PYTHONPATH=${nudeNetWheel}/${pkgs.python3.sitePackages}:''${PYTHONPATH:-}
      exec ${nudeNetPython}/bin/python3 ${nudeNetClassifierScript} "$@"
    '';
  };
  immichNsfwGuard = pkgs.writeTextFile {
    name = "immich-nsfw-guard";
    executable = true;
    destination = "/bin/immich-nsfw-guard";
    text = "#!${python}/bin/python3\n${builtins.readFile ./immich-nsfw-guard.py}";
  };
  nsfwConfigFile = pkgs.writeText "immich-nsfw-guard.json" (
    builtins.toJSON (
      {
        immich_url = "http://127.0.0.1:${toString immichPort}/api";
        mode = nsfw.mode;
        state_dir = nsfw.stateDir;
        source_api_key_file = config.sops.secrets.${nsfw.sourceApiKeySecret}.path;
        classifier_command = nsfw.classifier.command;
        classifier_timeout_seconds = nsfw.classifier.timeoutSeconds;
        classifier_batch_size = nsfw.classifier.batchSize;
        label_thresholds = nsfw.classifier.labelThresholds;
        scan_page_size = nsfw.scanPageSize;
        max_search_pages_per_run = nsfw.maxSearchPagesPerRun;
        max_assets_per_run = nsfw.maxAssetsPerRun;
        scan_asset_types = nsfw.scanAssetTypes;
        scan_failure_retry_base_minutes = nsfw.scanFailureRetryBaseMinutes;
        scan_failure_retry_max_hours = nsfw.scanFailureRetryMaxHours;
        review_threshold = nsfw.reviewThreshold;
        force_delete_source = nsfw.forceDeleteSource;
        keep_local_copies = nsfw.keepLocalCopies;
        review_bind = nsfw.review.bind;
        review_port = nsfw.review.port;
        review_username = nsfw.review.username;
      }
      // lib.optionalAttrs (nsfw.mode == "dual-account") {
        target_api_key_file = config.sops.secrets.${nsfw.targetApiKeySecret}.path;
      }
      // lib.optionalAttrs nsfw.review.enable {
        review_password_file = config.sops.secrets.${nsfw.review.passwordSecret}.path;
      }
    )
  );
in
{
  options.homelab.immich = {
    enable = lib.mkEnableOption "Immich photo and video library";

    mediaLocation = lib.mkOption {
      type = lib.types.path;
      default = "/tank/safe/immich";
      description = "Directory used to store Immich originals and generated media.";
    };

    nsfw = {
      enable = lib.mkEnableOption "Immich NSFW quarantine and review workflow";

      mode = lib.mkOption {
        type = lib.types.enum [
          "dual-account"
          "same-account"
        ];
        default = "dual-account";
        description = ''
          Review workflow mode. dual-account moves confirmed NSFW assets to the
          target API key's account. same-account moves confirmed NSFW assets to
          Locked in the source account.
        '';
      };

      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/immich-nsfw";
        description = "Directory used by the NSFW scanner for its queue database and temporary review copies.";
      };

      sourceApiKeySecret = lib.mkOption {
        type = lib.types.str;
        default = "immich_nsfw_source_api_key";
        description = ''
          sops-nix secret name containing an Immich API key for the
          family/source account. Required Immich permissions: user.read,
          asset.read, asset.view, asset.download, asset.update, asset.delete,
          and asset.upload. asset.upload is used for dual-account undo fallback.
        '';
      };

      targetApiKeySecret = lib.mkOption {
        type = lib.types.str;
        default = "immich_nsfw_target_api_key";
        description = ''
          sops-nix secret name containing an Immich API key for the dedicated
          NSFW account in dual-account mode. Required Immich permissions:
          asset.read, asset.view, asset.download, asset.upload, and asset.delete.
        '';
      };

      scanInterval = lib.mkOption {
        type = lib.types.str;
        default = "*:0/2";
        description = "systemd OnCalendar expression for scanning Immich uploads.";
      };

      scanPageSize = lib.mkOption {
        type = lib.types.ints.between 1 1000;
        default = 500;
        description = "Number of assets requested per Immich metadata search page.";
      };

      maxSearchPagesPerRun = lib.mkOption {
        type = lib.types.ints.positive;
        default = 25;
        description = "Maximum number of Immich metadata pages walked per scanner run.";
      };

      maxAssetsPerRun = lib.mkOption {
        type = lib.types.ints.positive;
        default = 100;
        description = "Maximum number of previously-unscanned assets classified during one scanner run.";
      };

      scanFailureRetryBaseMinutes = lib.mkOption {
        type = lib.types.ints.positive;
        default = 15;
        description = "Initial retry delay for assets whose thumbnail download or classifier run fails.";
      };

      scanFailureRetryMaxHours = lib.mkOption {
        type = lib.types.ints.positive;
        default = 24;
        description = "Maximum retry delay for repeatedly failing asset scans.";
      };

      scanAssetTypes = lib.mkOption {
        type = lib.types.nonEmptyListOf (
          lib.types.enum [
            "IMAGE"
            "VIDEO"
            "AUDIO"
            "OTHER"
          ]
        );
        default = [
          "IMAGE"
          "VIDEO"
        ];
        description = ''
          Immich asset types searched by the scanner. The default classifier
          examines one Immich preview thumbnail, so images and videos are
          enabled by default.
        '';
      };

      reviewThreshold = lib.mkOption {
        type = lib.types.float;
        default = 0.6;
        description = "Fallback classifier score threshold used when the classifier returns only a scalar score instead of labels.";
      };

      forceDeleteSource = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether moving a reviewed family asset to the target account should force-delete instead of using Immich trash.";
      };

      keepLocalCopies = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Keep scanner-downloaded originals after review decisions instead of deleting local temporary copies.";
      };

      classifier = {
        model = lib.mkOption {
          type = lib.types.enum [
            "320n"
            "640m"
          ];
          default = "320n";
          description = ''
            NudeNet model to use. 320n is bundled and fast. 640m downloads the
            larger ONNX model and uses 640px inference for potentially better
            localization at higher CPU and memory cost.
          '';
        };

        command = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "${immichNsfwNudeNet}/bin/immich-nsfw-nudenet" ];
          example = lib.literalExpression ''
            [ "''${pkgs.my-nsfw-classifier}/bin/nsfw-score" ]
          '';
          description = ''
            Command used to classify an Immich preview image. The scanner appends
            the image path as the final argument. By default this uses NudeNet
            ${nudeNetVersion}. The command may print a number between 0 and 1,
            or JSON containing detections/labels plus optional image dimensions.
          '';
        };

        timeoutSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 120;
          description = "Maximum runtime for the classifier command per asset.";
        };

        batchSize = lib.mkOption {
          type = lib.types.ints.positive;
          default = 8;
          description = "Maximum number of thumbnails classified by one classifier process.";
        };

        threads = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = "Thread count advertised to OpenCV, BLAS, and ONNX runtime for classifier work.";
        };

        cpuQuota = lib.mkOption {
          type = lib.types.str;
          default = "100%";
          description = "systemd CPUQuota applied to the scan service.";
        };

        memoryMax = lib.mkOption {
          type = lib.types.str;
          default = "2G";
          description = "systemd MemoryMax applied to the scan service.";
        };

        labelThresholds = lib.mkOption {
          type = lib.types.attrsOf lib.types.float;
          default = {
            ANUS_EXPOSED = 0.55;
            BUTTOCKS_EXPOSED = 0.75;
            FEMALE_BREAST_EXPOSED = 0.60;
            FEMALE_GENITALIA_EXPOSED = 0.60;
            MALE_GENITALIA_EXPOSED = 0.75;
          };
          description = ''
            NudeNet labels and minimum scores that automatically archive and
            queue a timeline asset. Archived assets are always shown in the
            review UI regardless of labels. Labels not listed here are shown in
            the review UI but do not flag by themselves.
          '';
        };
      };

      review = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Expose the authenticated review UI through Caddy.";
        };

        host = lib.mkOption {
          type = lib.types.str;
          default = "immich-review.${config.homelab.domain}";
          description = "Virtual host used for the NSFW review UI.";
        };

        bind = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address the review UI binds to before Caddy proxies it.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 2284;
          description = "Local TCP port for the review UI.";
        };

        username = lib.mkOption {
          type = lib.types.str;
          default = "admin";
          description = "HTTP basic authentication username for the review UI.";
        };

        passwordSecret = lib.mkOption {
          type = lib.types.str;
          default = "immich_nsfw_review_password";
          description = "sops-nix secret name containing the review UI HTTP basic authentication password.";
        };
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !nsfw.enable || cfg.enable;
          message = "homelab.immich.nsfw.enable requires homelab.immich.enable.";
        }
        {
          assertion = !nsfw.enable || config.host.secrets.enable;
          message = "homelab.immich.nsfw.enable requires host.secrets.enable for Immich API keys and review UI authentication.";
        }
        {
          assertion = !nsfw.enable || nsfw.classifier.command != [ ];
          message = "homelab.immich.nsfw.classifier.command must be set to a local classifier command that prints an NSFW score from 0 to 1.";
        }
        {
          assertion = !nsfw.enable || (nsfw.reviewThreshold >= 0.0 && nsfw.reviewThreshold <= 1.0);
          message = "homelab.immich.nsfw.reviewThreshold must be between 0 and 1.";
        }
        {
          assertion =
            !nsfw.enable
            || lib.all (threshold: threshold >= 0.0 && threshold <= 1.0) (
              lib.attrValues nsfw.classifier.labelThresholds
            );
          message = "homelab.immich.nsfw.classifier.labelThresholds values must be between 0 and 1.";
        }
      ];
    }

    (lib.mkIf cfg.enable {
      services.immich = {
        enable = true;
        host = "127.0.0.1";
        port = immichPort;
        mediaLocation = cfg.mediaLocation;

        settings = {
          backup.database.enabled = false;
          server.externalDomain = "https://${immichHost}";
          storageTemplate = {
            enabled = true;
            hashVerificationEnabled = true;
            template = "{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}";
          };
        };
      };

      # Activation can remount ZFS-backed paths after tmpfiles runs, so make
      # Immich fix its writable media root only after the live mount exists.
      systemd.services.immich-server = {
        requires = [ setupService ];
        after = [ setupService ];
      };

      systemd.services.immich-storage-setup = {
        description = "Prepare Immich writable media directory";
        before = [ "immich-server.service" ];
        requiredBy = [ "immich-server.service" ];
        after = [ "local-fs.target" ];
        unitConfig.RequiresMountsFor = [ mediaLocation ];
        serviceConfig.Type = "oneshot";
        script = ''
          ${installBin} -d -m 0700 ${lib.escapeShellArg mediaLocation}
          ${chownBin} immich:immich ${lib.escapeShellArg mediaLocation}
          ${chmodBin} 0700 ${lib.escapeShellArg mediaLocation}
        '';
      };

      services.caddy.virtualHosts."${immichHost}" = {
        extraConfig = ''
          tls internal
          reverse_proxy 127.0.0.1:${toString immichPort}
        '';
      };

      services.caddy.virtualHosts."http://${immichHost}" = {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString immichPort}
        '';
      };
    })

    (lib.mkIf (cfg.enable && nsfw.enable && config.host.secrets.enable) {
      users.groups.immich-nsfw = { };
      users.users.immich-nsfw = {
        isSystemUser = true;
        group = "immich-nsfw";
        home = nsfw.stateDir;
      };

      systemd.tmpfiles.rules = [
        "d ${nsfw.stateDir} 0750 immich-nsfw immich-nsfw -"
      ];

      systemd.services.immich-nsfw-scan = {
        description = "Scan Immich uploads for NSFW content";
        restartIfChanged = false;
        stopIfChanged = false;
        after = [ "immich-server.service" ];
        wants = [ "immich-server.service" ];
        unitConfig.RequiresMountsFor = [ nsfw.stateDir ];
        environment = {
          PYTHONUNBUFFERED = "1";
          OMP_NUM_THREADS = toString nsfw.classifier.threads;
          OPENBLAS_NUM_THREADS = toString nsfw.classifier.threads;
          MKL_NUM_THREADS = toString nsfw.classifier.threads;
          NUMEXPR_NUM_THREADS = toString nsfw.classifier.threads;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "immich-nsfw";
          Group = "immich-nsfw";
          ExecStart = "${immichNsfwGuard}/bin/immich-nsfw-guard scan --config ${nsfwConfigFile}";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ nsfw.stateDir ];
          TimeoutStartSec = "30min";
          TimeoutStopSec = "30min";
          CPUQuota = nsfw.classifier.cpuQuota;
          MemoryMax = nsfw.classifier.memoryMax;
          Nice = 10;
        }
        // lib.optionalAttrs (nsfw.stateDir == "/var/lib/immich-nsfw") {
          StateDirectory = "immich-nsfw";
        };
      };

      systemd.timers.immich-nsfw-scan = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = nsfw.scanInterval;
          Persistent = false;
        };
      };
    })

    (lib.mkIf (cfg.enable && nsfw.enable && nsfw.review.enable && config.host.secrets.enable) {
      systemd.services.immich-nsfw-review = {
        description = "Immich NSFW review UI";
        restartIfChanged = true;
        stopIfChanged = true;
        after = [ "immich-server.service" ];
        wants = [ "immich-server.service" ];
        wantedBy = [ "multi-user.target" ];
        unitConfig.RequiresMountsFor = [ nsfw.stateDir ];
        environment.PYTHONUNBUFFERED = "1";
        serviceConfig = {
          User = "immich-nsfw";
          Group = "immich-nsfw";
          ExecStart = "${immichNsfwGuard}/bin/immich-nsfw-guard review --config ${nsfwConfigFile}";
          Restart = "on-failure";
          RestartSec = "10s";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ nsfw.stateDir ];
          TimeoutStopSec = "1h";
        }
        // lib.optionalAttrs (nsfw.stateDir == "/var/lib/immich-nsfw") {
          StateDirectory = "immich-nsfw";
        };
      };

      services.caddy.virtualHosts."${nsfw.review.host}" = {
        extraConfig = ''
          tls internal
          reverse_proxy ${nsfw.review.bind}:${toString nsfw.review.port}
        '';
      };
    })
  ];
}
