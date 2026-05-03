# Self-contained ComfyUI NixOS service module using uv for Python package management
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.comfyui;

  comfyuiDir = "${cfg.dataDir}/ComfyUI";
  customNodesDir = "${comfyuiDir}/custom_nodes";
  venvDir = "${cfg.dataDir}/.venv";
  hashFile = "${cfg.dataDir}/.requirements-hash";

  runtimeLibs = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    libGL
    glib
    xorg.libX11
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
  ];

  comfyuiSrc = pkgs.fetchFromGitHub {
    owner = "Comfy-Org";
    repo = "ComfyUI";
    rev = "v${cfg.version}";
    hash = cfg.srcHash;
  };

  managerSrc = pkgs.fetchFromGitHub {
    owner = "Comfy-Org";
    repo = "ComfyUI-Manager";
    rev = cfg.managerVersion;
    hash = cfg.managerHash;
  };

  managerConfigIni = pkgs.writeText "comfyui-manager-config.ini" ''
    [default]
    security_level = normal
    network_mode = public
    use_uv = true
    file_logging = true
  '';

  syncDeclarativeNodes = concatMapStringsSep "\n" (node: ''
    echo "Syncing declarative node: ${node.name}"
    ${pkgs.rsync}/bin/rsync -a --delete --chmod=ug+rwX "${node.src}/" "${customNodesDir}/${node.name}/"
  '') cfg.declarativeNodes;

  collectRequirementFiles = concatMapStringsSep "\n" (node: ''
    REQUIREMENT_FILES+=("${customNodesDir}/${node.name}/requirements.txt")
    INSTALL_SCRIPTS+=("${customNodesDir}/${node.name}/install.py")
  '') cfg.declarativeNodes;

  setupScript = pkgs.writeShellScript "comfyui-setup" ''
    set -euo pipefail

    mkdir -p "${comfyuiDir}" "${customNodesDir}"

    # Initialize models directory from source on first setup (preserves subdirs + placeholder files)
    if [ ! -d "${comfyuiDir}/models" ]; then
      if [ -d "${comfyuiSrc}/models" ]; then
        cp -r "${comfyuiSrc}/models" "${comfyuiDir}/"
      else
        mkdir -p "${comfyuiDir}/models"
      fi
    fi

    # Sync ComfyUI source (preserve runtime directories)
    ${pkgs.rsync}/bin/rsync -a --delete --chmod=ug+rwX \
      --exclude '/custom_nodes' \
      --exclude '/models' \
      --exclude '/input' \
      --exclude '/output' \
      --exclude '/temp' \
      --exclude '/user' \
      "${comfyuiSrc}/" "${comfyuiDir}/"

    # Ensure runtime directories exist
    mkdir -p "${comfyuiDir}"/{input,output,temp,user}

    # Sync Manager if enabled
    ${optionalString cfg.enableManager ''
      echo "Syncing ComfyUI-Manager..."
      ${pkgs.rsync}/bin/rsync -a --delete --chmod=ug+rwX "${managerSrc}/" "${customNodesDir}/comfyui-manager/"
      mkdir -p "${comfyuiDir}/user/__manager"
      cp -f "${managerConfigIni}" "${comfyuiDir}/user/__manager/config.ini"
    ''}

    ${optionalString (!cfg.enableManager) ''
      rm -rf "${customNodesDir}/comfyui-manager"
    ''}

    # Sync declarative custom nodes
    ${syncDeclarativeNodes}

    # Create venv if missing
    if [ ! -x "${venvDir}/bin/python" ]; then
      ${pkgs.uv}/bin/uv venv --python ${pkgs.python312}/bin/python "${venvDir}"
    fi

    # Collect all requirements files
    REQUIREMENT_FILES=("${comfyuiDir}/requirements.txt")
    INSTALL_SCRIPTS=()
    ${optionalString cfg.enableManager ''
      REQUIREMENT_FILES+=("${comfyuiDir}/manager_requirements.txt")
      REQUIREMENT_FILES+=("${customNodesDir}/comfyui-manager/requirements.txt")
      INSTALL_SCRIPTS+=("${customNodesDir}/comfyui-manager/install.py")
    ''}
    ${collectRequirementFiles}

    # Compute hash of all requirements
    HASH_INPUT=$(mktemp)
    {
      echo "extra:${concatStringsSep " " cfg.extraDependencies}"
      echo "install-scripts:${boolToString cfg.runInstallScripts}"
      for f in "''${REQUIREMENT_FILES[@]}"; do
        [ -f "$f" ] && cat "$f"
      done
      if [ "${boolToString cfg.runInstallScripts}" = "true" ]; then
        for f in "''${INSTALL_SCRIPTS[@]}"; do
          [ -f "$f" ] && cat "$f"
        done
      fi
    } > "$HASH_INPUT"
    NEXT_HASH=$(sha256sum "$HASH_INPUT" | cut -d' ' -f1)
    rm -f "$HASH_INPUT"

    CURRENT_HASH=""
    [ -f "${hashFile}" ] && CURRENT_HASH=$(cat "${hashFile}")

    # Install dependencies only if requirements changed
    if [ "$NEXT_HASH" != "$CURRENT_HASH" ]; then
      echo "Installing Python dependencies..."
      for f in "''${REQUIREMENT_FILES[@]}"; do
        [ -f "$f" ] && ${pkgs.uv}/bin/uv pip install --python "${venvDir}/bin/python" --upgrade -r "$f"
      done

      ${optionalString (cfg.extraDependencies != [ ]) ''
        ${pkgs.uv}/bin/uv pip install --python "${venvDir}/bin/python" --upgrade ${concatStringsSep " " cfg.extraDependencies}
      ''}

      ${optionalString cfg.runInstallScripts ''
        for f in "''${INSTALL_SCRIPTS[@]}"; do
          if [ -f "$f" ]; then
            echo "Running install script: $f"
            "${venvDir}/bin/python" "$f"
          fi
        done
      ''}

      echo "$NEXT_HASH" > "${hashFile}"
    fi

    # Ensure group permissions on ComfyUI directory (setgid for new files to inherit group)
    find "${comfyuiDir}" -type d -exec chmod g+rwxs {} +
    find "${comfyuiDir}" -type f -exec chmod g+rw {} +
  '';

  startScript = pkgs.writeShellScript "comfyui-start" ''
    set -euo pipefail
    cd "${comfyuiDir}"
    exec "${venvDir}/bin/python" main.py \
      --listen ${cfg.host} \
      --port ${toString cfg.port} \
      ${optionalString cfg.enableManager "--enable-manager"} \
      ${concatStringsSep " " cfg.extraArgs}
  '';
in
{
  options.services.comfyui = {
    enable = mkEnableOption "ComfyUI image generation service";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/comfyui";
      description = "Directory for ComfyUI data and virtual environment";
    };

    version = mkOption {
      type = types.str;
      default = "0.10.0";
      description = "ComfyUI version (git tag without 'v' prefix)";
    };

    srcHash = mkOption {
      type = types.str;
      default = "sha256-WVWKMXXOls9lYiNWFj164DP96V8IhRfTfxBI9CRprkE=";
      description = "SHA256 hash for the ComfyUI source tarball";
    };

    enableManager = mkOption {
      type = types.bool;
      default = false;
      description = "Enable ComfyUI-Manager for installing custom nodes";
    };

    managerVersion = mkOption {
      type = types.str;
      default = "4.0.5";
      description = "ComfyUI-Manager version tag";
    };

    managerHash = mkOption {
      type = types.str;
      default = "sha256-ZyA6mGIHaNwvVz3B0TkOEnNq/wKeEyO941LIt6gBDAk=";
      description = "SHA256 hash for the ComfyUI-Manager source tarball";
    };

    declarativeNodes = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Directory name for the custom node";
            };
            src = mkOption {
              type = types.path;
              description = "Source path (e.g., fetchFromGitHub result)";
            };
          };
        }
      );
      default = [ ];
      description = "Declaratively managed custom nodes";
    };

    runInstallScripts = mkOption {
      type = types.bool;
      default = false;
      description = "Run install.py scripts from custom nodes (potentially unsafe)";
    };

    extraDependencies = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional Python packages to install";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional CLI arguments for ComfyUI";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address to bind to";
    };

    port = mkOption {
      type = types.port;
      default = 8188;
      description = "Port for the web interface";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the port in the firewall";
    };

    user = mkOption {
      type = types.str;
      default = "comfyui";
      description = "User to run the service as";
    };

    group = mkOption {
      type = types.str;
      default = "comfyui";
      description = "Group to run the service as";
    };

    createUser = mkOption {
      type = types.bool;
      default = true;
      description = "Create the service user and group";
    };
  };

  config = mkIf cfg.enable {
    programs.nix-ld = {
      enable = true;
      libraries = runtimeLibs;
    };

    users.users = mkIf cfg.createUser {
      ${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        description = "ComfyUI service user";
        home = cfg.dataDir;
        createHome = true;
        homeMode = "2750"; # Group can traverse and list (setgid for new entries)
      };
    };

    users.groups = mkIf cfg.createUser {
      ${cfg.group} = { };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.comfyui = {
      description = "ComfyUI Image Generation Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.git ];
      preStart = "${setupScript}";

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = startScript;
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = "30min";

        # Ensure new files are group-writable
        UMask = "0002";

        # Security hardening
        ProtectHome = "read-only";
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.dataDir ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];

        Environment = [
          "CUDA_HOME=${pkgs.cudaPackages.cudatoolkit}"
          "LD_LIBRARY_PATH=${lib.makeLibraryPath runtimeLibs}"
          "NIX_LD_LIBRARY_PATH=${lib.makeLibraryPath runtimeLibs}"
        ];
      };
    };
  };
}
