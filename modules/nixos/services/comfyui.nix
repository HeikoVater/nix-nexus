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
  packNodeManifestFile = "${cfg.dataDir}/.modelpack-managed-nodes";
  packFileManifestFile = "${cfg.dataDir}/.modelpack-managed-files";

  packDefinitions = import ./comfyui-modelpacks.nix { inherit lib pkgs; };
  enabledPackNames = filter (name: cfg.modelPacks.${name}) (attrNames packDefinitions);
  enabledPacks = map (name: packDefinitions.${name}) enabledPackNames;

  uniqueBy =
    keyFn: values: attrValues (foldl' (acc: value: acc // { ${keyFn value} = value; }) { } values);
  packAttrLists = attr: concatMap (pack: pack.${attr} or [ ]) enabledPacks;
  hasPackFlag = attr: any (pack: pack.${attr} or false) enabledPacks;

  packNodes = uniqueBy (node: node.name) (packAttrLists "nodes");
  packModels = uniqueBy (model: model.path) (packAttrLists "models");
  packFiles = uniqueBy (file: file.target) (packAttrLists "files");
  allNodeNames = unique (
    (map (node: node.name) cfg.declarativeNodes) ++ (map (node: node.name) packNodes)
  );

  effectiveEnableManager = cfg.enableManager || hasPackFlag "enableManager";
  effectiveSanitizeRequirements = cfg.sanitizeRequirements || hasPackFlag "sanitizeRequirements";
  protectManagerPackages = hasPackFlag "protectManagerPackages";

  packPython = map (pack: pack.python or { }) enabledPacks;
  pythonValues =
    attr: filter (value: value != null) (map (python: python.${attr} or null) packPython);
  pythonFlag = attr: any (python: python.${attr} or false) packPython;
  transformersMins = pythonValues "transformersMin";
  opencvKinds =
    pythonValues "opencv"
    ++ filter (value: value != null) (map (pack: pack.opencv or null) enabledPacks);

  selectedTransformersMin =
    if elem "4.51.3" transformersMins then
      "4.51.3"
    else if elem "4.50.3" transformersMins then
      "4.50.3"
    else
      null;

  selectedOpenCvDependency =
    if elem "contrib" opencvKinds then
      "opencv-contrib-python==4.10.0.84"
    else if elem "headless" opencvKinds then
      "opencv-python-headless==4.12.0.88"
    else
      null;

  derivedPythonDependencies =
    optional (pythonFlag "numpy126") "numpy==1.26.4"
    ++ optional (!pythonFlag "numpy126" && pythonFlag "numpyRange") "numpy>=1.26,<3"
    ++ optional (pythonFlag "pillow11") "pillow>=11.0.0"
    ++ optional (selectedTransformersMin != null) "transformers>=${selectedTransformersMin},<5"
    ++ optional (pythonFlag "tokenizers021") "tokenizers>=0.21,<0.22"
    ++ optional (pythonFlag "hfHub") "huggingface-hub>=0.26,<1.0"
    ++ optional (pythonFlag "timm1015") "timm==1.0.15"
    ++ optional (selectedOpenCvDependency != null) selectedOpenCvDependency;

  allExtraDependencies = unique (
    derivedPythonDependencies ++ (packAttrLists "extraDependencies") ++ cfg.extraDependencies
  );

  servicePath = [
    pkgs.coreutils
    pkgs.curl
    pkgs.git
    pkgs.git-lfs
    pkgs.gnugrep
    pkgs.gnused
    pkgs.rsync
  ]
  ++ (packAttrLists "runtimePackages");

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
    use_uv = ${if protectManagerPackages then "false" else "true"}
    ${optionalString protectManagerPackages "always_lazy_install = False"}
    file_logging = true
  '';

  managerPipBlacklist = pkgs.writeText "comfyui-manager-pip-blacklist.list" ''
    torch
    torchvision
    torchaudio
    xformers
    transformers
    tokenizers
    huggingface-hub
    numpy
    opencv-python
    opencv-python-headless
    opencv-contrib-python
    opencv-contrib-python-headless
    nvidia-
    cuda-toolkit
    cuda-bindings
    triton
    torchcodec
  '';

  syncDeclarativeNodes = concatMapStringsSep "\n" (node: ''
    echo "Syncing declarative node: ${node.name}"
    ${pkgs.rsync}/bin/rsync -a --delete --chmod=ug+rwX "${node.src}/" "${customNodesDir}/${node.name}/"
  '') cfg.declarativeNodes;

  syncPackNodes = concatMapStringsSep "\n" (
    node:
    let
      cloneFlags = optionalString (node.recursive or false) "--recursive";
      checkoutRef = optionalString (node ? ref) ''
        ${pkgs.git}/bin/git -C "$target" fetch --all --tags
        ${pkgs.git}/bin/git -C "$target" checkout --detach ${escapeShellArg node.ref}
      '';
    in
    ''
      target="${customNodesDir}/${node.name}"
      if [ -d "$target/.git" ]; then
        ${checkoutRef}
      elif [ -e "$target" ]; then
        echo "Custom node ${node.name} already exists and is not git-managed; leaving it in place"
      else
        echo "Cloning model-pack node: ${node.name}"
        ${pkgs.git}/bin/git clone ${cloneFlags} ${escapeShellArg node.url} "$target"
        ${checkoutRef}
      fi
    ''
  ) packNodes;

  syncPackModels = concatMapStringsSep "\n" (model: ''
    target="${comfyuiDir}/models/${model.path}"
    if [ -f "$target" ]; then
      echo "Model ${model.path} exists - skip"
    else
      echo "Downloading model: ${model.path}"
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")"
      tmp_target="$target.tmp"
      ${pkgs.coreutils}/bin/rm -f "$tmp_target"
      ${pkgs.curl}/bin/curl -L --fail --retry 5 --retry-delay 10 --retry-connrefused --progress-bar --show-error -o "$tmp_target" ${escapeShellArg model.url}
      ${pkgs.coreutils}/bin/mv "$tmp_target" "$target"
    fi
  '') packModels;

  syncPackFiles = concatMapStringsSep "\n" (file: ''
    echo "Syncing model-pack file: ${file.target}"
    ${pkgs.coreutils}/bin/install -D -m 0664 ${escapeShellArg (toString file.src)} "${comfyuiDir}/${file.target}"
  '') packFiles;

  desiredPackNodeManifest = concatMapStringsSep "\n" (node: ''
    printf '%s\n' ${escapeShellArg "${customNodesDir}/${node.name}"} >> "$DESIRED_PACK_NODE_MANIFEST"
  '') packNodes;

  desiredPackFileManifest =
    concatMapStringsSep "\n" (model: ''
      printf '%s\n' ${escapeShellArg "${comfyuiDir}/models/${model.path}"} >> "$DESIRED_PACK_FILE_MANIFEST"
    '') packModels
    + concatMapStringsSep "\n" (file: ''
      printf '%s\n' ${escapeShellArg "${comfyuiDir}/${file.target}"} >> "$DESIRED_PACK_FILE_MANIFEST"
    '') packFiles;

  collectRequirementFiles = concatMapStringsSep "\n" (nodeName: ''
    NODE_REQUIREMENT_FILES+=("${customNodesDir}/${nodeName}/requirements.txt")
    INSTALL_SCRIPTS+=("${customNodesDir}/${nodeName}/install.py")
  '') allNodeNames;

  patchPackRequirements = ''
    ${optionalString (hasPackFlag "disableManagerMatrix") ''
      for req in "${customNodesDir}/comfyui-manager/requirements.txt" "${customNodesDir}/ComfyUI-Manager/requirements.txt"; do
        if [ -f "$req" ]; then
          ${pkgs.gnused}/bin/sed -i 's/^matrix-client==0\.4\.0/# matrix-client disabled by comfyui model-pack setup/' "$req" || true
        fi
      done
    ''}

    ${optionalString (hasPackFlag "disableImpactSam2") ''
      if [ -f "${customNodesDir}/ComfyUI-Impact-Pack/requirements.txt" ]; then
        ${pkgs.gnused}/bin/sed -i 's@^git+https://github.com/facebookresearch/sam2.*@# sam2 disabled by comfyui model-pack setup@' \
          "${customNodesDir}/ComfyUI-Impact-Pack/requirements.txt" || true
      fi
    ''}
  '';

  writeManagerProtection = optionalString protectManagerPackages ''
    mkdir -p "${comfyuiDir}/user/__manager"
    cp -f "${managerPipBlacklist}" "${comfyuiDir}/user/__manager/pip_blacklist.list"
  '';

  clearManagerProtection = optionalString (!protectManagerPackages) ''
    rm -f "${comfyuiDir}/user/__manager/pip_blacklist.list"
  '';

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

    cleanup_removed_pack_entries() {
      local manifest="$1"
      local desired="$2"
      local kind="$3"

      [ -f "$manifest" ] || return 0

      while IFS= read -r path; do
        [ -n "$path" ] || continue

        if ! ${pkgs.gnugrep}/bin/grep -Fxq -- "$path" "$desired"; then
          echo "Removing disabled model-pack $kind: $path"
          if [ "$kind" = "directory" ]; then
            ${pkgs.coreutils}/bin/rm -rf "$path"
          else
            ${pkgs.coreutils}/bin/rm -f "$path"
            prune_empty_parents "$(${pkgs.coreutils}/bin/dirname "$path")"
          fi
        fi
      done < "$manifest"
    }

    prune_empty_parents() {
      local dir="$1"

      while [ "$dir" != "${comfyuiDir}" ] && [ "$dir" != "/" ]; do
        ${pkgs.coreutils}/bin/rmdir "$dir" 2>/dev/null || break
        dir="$(${pkgs.coreutils}/bin/dirname "$dir")"
      done
    }

    # Ensure runtime directories exist
    mkdir -p "${comfyuiDir}"/{input,output,temp,user}

    DESIRED_PACK_NODE_MANIFEST=$(mktemp)
    DESIRED_PACK_FILE_MANIFEST=$(mktemp)
    : > "$DESIRED_PACK_NODE_MANIFEST"
    : > "$DESIRED_PACK_FILE_MANIFEST"
    ${desiredPackNodeManifest}
    ${desiredPackFileManifest}

    # Sync Manager if enabled
    ${optionalString effectiveEnableManager ''
      echo "Syncing ComfyUI-Manager..."
      ${pkgs.rsync}/bin/rsync -a --delete --chmod=ug+rwX "${managerSrc}/" "${customNodesDir}/comfyui-manager/"
      mkdir -p "${comfyuiDir}/user/__manager"
      cp -f "${managerConfigIni}" "${comfyuiDir}/user/__manager/config.ini"
    ''}

    ${optionalString (!effectiveEnableManager) ''
      rm -rf "${customNodesDir}/comfyui-manager" "${comfyuiDir}/user/__manager"
    ''}

    # Sync declarative custom nodes
    ${syncDeclarativeNodes}

    # Remove items from previously enabled packs before syncing the desired set.
    cleanup_removed_pack_entries "${packNodeManifestFile}" "$DESIRED_PACK_NODE_MANIFEST" directory
    cleanup_removed_pack_entries "${packFileManifestFile}" "$DESIRED_PACK_FILE_MANIFEST" file

    # Sync model-pack custom nodes, model files, and tracked assets.
    ${syncPackNodes}
    ${syncPackModels}
    ${syncPackFiles}

    cp -f "$DESIRED_PACK_NODE_MANIFEST" "${packNodeManifestFile}"
    cp -f "$DESIRED_PACK_FILE_MANIFEST" "${packFileManifestFile}"
    rm -f "$DESIRED_PACK_NODE_MANIFEST" "$DESIRED_PACK_FILE_MANIFEST"

    # Apply compatibility patches before dependency hashing/installing.
    ${patchPackRequirements}
    ${writeManagerProtection}
    ${clearManagerProtection}

    # Collect all requirements files
    CORE_REQUIREMENT_FILES=("${comfyuiDir}/requirements.txt")
    NODE_REQUIREMENT_FILES=()
    INSTALL_SCRIPTS=()
    ${optionalString effectiveEnableManager ''
      CORE_REQUIREMENT_FILES+=("${comfyuiDir}/manager_requirements.txt")
      NODE_REQUIREMENT_FILES+=("${customNodesDir}/comfyui-manager/requirements.txt")
      INSTALL_SCRIPTS+=("${customNodesDir}/comfyui-manager/install.py")
    ''}
    ${collectRequirementFiles}

    install_requirements_file() {
      local req="$1"
      local sanitize="$2"
      local install_req="$req"
      local sanitized_req=""
      local req_dir

      [ -f "$req" ] || return 0

      if [ "$sanitize" = "true" ]; then
        sanitized_req=$(mktemp)
        ${pkgs.gnugrep}/bin/grep -Eiv '^[[:space:]]*(-e[[:space:]]+)?(torch|torchvision|torchaudio|xformers|triton|transformers|tokenizers|huggingface-hub|huggingface_hub|numpy|opencv-python|opencv-contrib-python|opencv-python-headless|opencv-contrib-python-headless|sageattention)(\[|==|>=|<=|~=|!=|>|<|[[:space:]]|$)|^[[:space:]]*(-e[[:space:]]+)?(nvidia-|cuda-toolkit|cuda-bindings)|github\.com/facebookresearch/sam2' \
          "$req" > "$sanitized_req" || true
        install_req="$sanitized_req"

        if [ ! -s "$install_req" ]; then
          rm -f "$sanitized_req"
          return 0
        fi
      fi

      req_dir="$(${pkgs.coreutils}/bin/dirname "$req")"
      (
        cd "$req_dir"
        ${pkgs.uv}/bin/uv pip install --python "${venvDir}/bin/python" --upgrade -r "$install_req"
      )

      [ -z "$sanitized_req" ] || rm -f "$sanitized_req"
    }

    # Compute hash of all requirements
    HASH_INPUT=$(mktemp)
    {
      echo "packs:${concatStringsSep " " enabledPackNames}"
      echo "extra:${concatStringsSep " " allExtraDependencies}"
      echo "install-scripts:${boolToString cfg.runInstallScripts}"
      echo "sanitize-requirements:${boolToString effectiveSanitizeRequirements}"
      for f in "''${CORE_REQUIREMENT_FILES[@]}" "''${NODE_REQUIREMENT_FILES[@]}"; do
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

    if [ ! -x "${venvDir}/bin/python" ]; then
      CURRENT_HASH=""
    fi

    # Install dependencies only if requirements changed
    if [ "$NEXT_HASH" != "$CURRENT_HASH" ]; then
      echo "Refreshing Python dependencies..."
      ${pkgs.coreutils}/bin/rm -rf "${venvDir}"
      ${pkgs.uv}/bin/uv venv --python ${pkgs.python312}/bin/python "${venvDir}"

      for f in "''${CORE_REQUIREMENT_FILES[@]}"; do
        install_requirements_file "$f" false
      done

      ${optionalString (allExtraDependencies != [ ]) ''
        ${pkgs.uv}/bin/uv pip install --python "${venvDir}/bin/python" --upgrade ${escapeShellArgs allExtraDependencies}
      ''}

      for f in "''${NODE_REQUIREMENT_FILES[@]}"; do
        install_requirements_file "$f" ${boolToString effectiveSanitizeRequirements}
      done

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
      ${optionalString effectiveEnableManager "--enable-manager"} \
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

    modelPacks = mapAttrs (
      name: pack:
      mkOption {
        type = types.bool;
        default = false;
        description = "Enable the ${pack.description}.";
      }
    ) packDefinitions;

    runInstallScripts = mkOption {
      type = types.bool;
      default = false;
      description = "Run install.py scripts from custom nodes (potentially unsafe)";
    };

    sanitizeRequirements = mkOption {
      type = types.bool;
      default = false;
      description = "Filter fragile GPU stack packages from custom-node requirements before installing them";
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
      path = servicePath;
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
