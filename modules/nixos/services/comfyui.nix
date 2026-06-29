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
  modelSourceStateDir = "${cfg.dataDir}/.modelpack-model-state";

  packDefinitions = import ./comfyui-modelpacks.nix { inherit lib pkgs; };
  variantPackNames = filter (name: packDefinitions.${name} ? variants) (attrNames packDefinitions);
  enabledPackNames = filter (name: cfg.modelPacks.${name}.enable) (attrNames packDefinitions);

  mergePackAttrs =
    base: variant:
    base
    // variant
    // {
      nodes = (base.nodes or [ ]) ++ (variant.nodes or [ ]);
      models = (base.models or [ ]) ++ (variant.models or [ ]);
      files = (base.files or [ ]) ++ (variant.files or [ ]);
      extraDependencies = (base.extraDependencies or [ ]) ++ (variant.extraDependencies or [ ]);
      runtimePackages = (base.runtimePackages or [ ]) ++ (variant.runtimePackages or [ ]);
      python = (base.python or { }) // (variant.python or { });
      enableManager = (base.enableManager or false) || (variant.enableManager or false);
      sanitizeRequirements =
        (base.sanitizeRequirements or false) || (variant.sanitizeRequirements or false);
      disableManagerMatrix =
        (base.disableManagerMatrix or false) || (variant.disableManagerMatrix or false);
      disableImpactSam2 = (base.disableImpactSam2 or false) || (variant.disableImpactSam2 or false);
      protectManagerPackages =
        (base.protectManagerPackages or false) || (variant.protectManagerPackages or false);
    }
    // optionalAttrs ((base ? opencv) || (variant ? opencv)) {
      opencv = variant.opencv or base.opencv;
    };

  resolvePack =
    name:
    let
      pack = packDefinitions.${name};
      selectedVariant =
        if (pack ? variants) && cfg.modelPacks.${name}.variant != null then
          pack.variants.${cfg.modelPacks.${name}.variant}
        else
          { };
    in
    mergePackAttrs pack selectedVariant;

  enabledPacks = map resolvePack enabledPackNames;

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

  syncPackNodes = concatMapStringsSep "\n" (node: ''
    sync_pack_node \
      ${escapeShellArg node.name} \
      ${escapeShellArg node.url} \
      ${escapeShellArg (node.ref or "")} \
      ${escapeShellArg (if node.recursive or false then "true" else "false")}
  '') packNodes;

  syncPackModels = concatMapStringsSep "\n" (model: ''
    sync_pack_model ${escapeShellArg model.path} ${escapeShellArg model.url}
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

    resolve_origin_head_ref() {
      local repo="$1"
      local origin_head_ref=""

      origin_head_ref=$(${pkgs.git}/bin/git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)
      if [ -z "$origin_head_ref" ]; then
        ${pkgs.git}/bin/git -C "$repo" remote set-head origin --auto >/dev/null 2>&1 || true
        origin_head_ref=$(${pkgs.git}/bin/git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)
      fi

      [ -n "$origin_head_ref" ] || return 1
      printf '%s\n' "$origin_head_ref"
    }

    checkout_pack_node_repo() {
      local repo="$1"
      local ref="$2"
      local recursive="$3"
      local name="$4"

      if [ -n "$ref" ]; then
        ${pkgs.git}/bin/git -C "$repo" checkout --detach -f "$ref"
      else
        local origin_head_ref

        origin_head_ref=$(resolve_origin_head_ref "$repo") || {
          echo "Unable to determine default branch for model-pack node: $name" >&2
          return 1
        }

        ${pkgs.git}/bin/git -C "$repo" checkout --detach -f "$origin_head_ref"
      fi

      if [ "$recursive" = "true" ]; then
        ${pkgs.git}/bin/git -C "$repo" submodule sync --recursive
        ${pkgs.git}/bin/git -C "$repo" submodule update --init --recursive
      fi
    }

    clone_pack_node_repo() {
      local name="$1"
      local url="$2"
      local ref="$3"
      local recursive="$4"
      local repo="$5"
      local clone_args=()

      if [ "$recursive" = "true" ]; then
        clone_args+=(--recursive)
      fi

      ${pkgs.git}/bin/git clone ''${clone_args[@]} "$url" "$repo"
      checkout_pack_node_repo "$repo" "$ref" "$recursive" "$name"
    }

    sync_pack_node() {
      local name="$1"
      local url="$2"
      local ref="$3"
      local recursive="$4"
      local target="${customNodesDir}/$name"
      local current_url=""

      if [ -d "$target/.git" ]; then
        current_url=$(${pkgs.git}/bin/git -C "$target" remote get-url origin 2>/dev/null || true)
      fi

      if [ -d "$target/.git" ] && [ "$current_url" = "$url" ]; then
        echo "Updating model-pack node: $name"
        ${pkgs.git}/bin/git -C "$target" fetch --all --tags --prune
        checkout_pack_node_repo "$target" "$ref" "$recursive" "$name"
        return 0
      fi

      local tmp_target
      tmp_target=$(mktemp -d "${customNodesDir}/.$name.tmp.XXXXXX")

      if [ -e "$target" ]; then
        echo "Replacing model-pack node: $name"
      else
        echo "Cloning model-pack node: $name"
      fi

      if ! clone_pack_node_repo "$name" "$url" "$ref" "$recursive" "$tmp_target"; then
        ${pkgs.coreutils}/bin/rm -rf "$tmp_target"
        return 1
      fi

      if [ -e "$target" ]; then
        local backup_target

        backup_target="$target.previous.$$"
        ${pkgs.coreutils}/bin/rm -rf "$backup_target"
        ${pkgs.coreutils}/bin/mv "$target" "$backup_target"
        if ${pkgs.coreutils}/bin/mv "$tmp_target" "$target"; then
          ${pkgs.coreutils}/bin/rm -rf "$backup_target"
        else
          ${pkgs.coreutils}/bin/mv "$backup_target" "$target"
          ${pkgs.coreutils}/bin/rm -rf "$tmp_target"
          return 1
        fi
      else
        ${pkgs.coreutils}/bin/mv "$tmp_target" "$target"
      fi
    }

    extract_last_header() {
      local headers="$1"
      local header_name="$2"
      local value=""

      value=$(
        ${pkgs.gnugrep}/bin/grep -i "^$header_name:" "$headers" \
          | ${pkgs.coreutils}/bin/tail -n 1 \
          | ${pkgs.gnused}/bin/sed -E "s/^$header_name:[[:space:]]*//I; s/\r$//" \
          || true
      )

      printf '%s\n' "$value"
    }

    query_model_fingerprint() {
      local url="$1"
      local headers
      local fingerprint=""

      headers=$(mktemp)
      if ! ${pkgs.curl}/bin/curl -L --fail --retry 5 --retry-delay 10 --retry-connrefused --silent --show-error --head --dump-header "$headers" --output /dev/null "$url"; then
        ${pkgs.coreutils}/bin/rm -f "$headers"
        return 1
      fi

      fingerprint=$(extract_last_header "$headers" "etag")
      if [ -z "$fingerprint" ]; then
        fingerprint=$(extract_last_header "$headers" "last-modified")
      fi

      ${pkgs.coreutils}/bin/rm -f "$headers"
      printf '%s\n' "$fingerprint"
    }

    download_pack_model() {
      local url="$1"
      local target="$2"
      local headers="$3"
      local tmp_target="$target.tmp"

      ${pkgs.coreutils}/bin/rm -f "$tmp_target"
      ${pkgs.curl}/bin/curl -L --fail --retry 5 --retry-delay 10 --retry-connrefused --progress-bar --show-error --dump-header "$headers" -o "$tmp_target" "$url"
      ${pkgs.coreutils}/bin/mv "$tmp_target" "$target"
    }

    sync_pack_model() {
      local rel_path="$1"
      local url="$2"
      local target="${comfyuiDir}/models/$rel_path"
      local state_base="${modelSourceStateDir}/$rel_path"
      local url_state="$state_base.url"
      local fingerprint_state="$state_base.fingerprint"
      local current_url=""
      local current_fingerprint=""
      local remote_fingerprint=""
      local should_download="false"

      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$target")" "$(${pkgs.coreutils}/bin/dirname "$url_state")"

      [ -f "$url_state" ] && current_url=$(${pkgs.coreutils}/bin/cat "$url_state")
      [ -f "$fingerprint_state" ] && current_fingerprint=$(${pkgs.coreutils}/bin/cat "$fingerprint_state")

      if [ ! -f "$target" ]; then
        should_download="true"
      elif [ -z "$current_url" ]; then
        printf '%s\n' "$url" > "$url_state"
        current_url="$url"
      elif [ "$current_url" != "$url" ]; then
        should_download="true"
      fi

      if [ "$should_download" = "false" ]; then
        remote_fingerprint=$(query_model_fingerprint "$url" || true)
        if [ -z "$remote_fingerprint" ]; then
          echo "Model $rel_path fingerprint unavailable - keeping existing file"
        elif [ -z "$current_fingerprint" ]; then
          echo "Bootstrapping model fingerprint: $rel_path"
          printf '%s\n' "$remote_fingerprint" > "$fingerprint_state"
        elif [ "$current_fingerprint" = "$remote_fingerprint" ]; then
          echo "Model $rel_path is current - skip"
        else
          should_download="true"
        fi
      fi

      if [ "$should_download" = "true" ]; then
        local headers

        echo "Downloading model: $rel_path"
        headers=$(mktemp)
        download_pack_model "$url" "$target" "$headers"
        remote_fingerprint=$(extract_last_header "$headers" "etag")
        if [ -z "$remote_fingerprint" ]; then
          remote_fingerprint=$(extract_last_header "$headers" "last-modified")
        fi
        ${pkgs.coreutils}/bin/rm -f "$headers"

        printf '%s\n' "$url" > "$url_state"
        if [ -n "$remote_fingerprint" ]; then
          printf '%s\n' "$remote_fingerprint" > "$fingerprint_state"
        else
          ${pkgs.coreutils}/bin/rm -f "$fingerprint_state"
        fi
      fi
    }

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
            remove_model_state "$path"
            ${pkgs.coreutils}/bin/rm -f "$path"
            prune_empty_parents "${comfyuiDir}" "$(${pkgs.coreutils}/bin/dirname "$path")"
          fi
        fi
      done < "$manifest"
    }

    prune_empty_parents() {
      local base="$1"
      local dir="$2"

      while [ "$dir" != "$base" ] && [ "$dir" != "/" ]; do
        ${pkgs.coreutils}/bin/rmdir "$dir" 2>/dev/null || break
        dir="$(${pkgs.coreutils}/bin/dirname "$dir")"
      done
    }

    remove_model_state() {
      local target="$1"

      case "$target" in
        "${comfyuiDir}/models/"*)
          local rel_path="''${target#${comfyuiDir}/models/}"
          local state_base="${modelSourceStateDir}/$rel_path"

          ${pkgs.coreutils}/bin/rm -f "$state_base.url" "$state_base.fingerprint"
          prune_empty_parents "${modelSourceStateDir}" "$(${pkgs.coreutils}/bin/dirname "$state_base")"
          ;;
      esac
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

    # Sync model-pack custom nodes, model files, and tracked assets first so
    # existing working files remain in place if a replacement fetch fails.
    ${syncPackNodes}
    ${syncPackModels}
    ${syncPackFiles}

    # Remove items from previously enabled packs only after the replacement set
    # has been realized successfully.
    cleanup_removed_pack_entries "${packNodeManifestFile}" "$DESIRED_PACK_NODE_MANIFEST" directory
    cleanup_removed_pack_entries "${packFileManifestFile}" "$DESIRED_PACK_FILE_MANIFEST" file

    # Sync declarative custom nodes last so pack-to-declarative migrations can
    # happen in a single deployment.
    ${syncDeclarativeNodes}

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
        type = types.submodule {
          options = {
            enable = mkEnableOption pack.description;
          }
          // optionalAttrs (pack ? variants) {
            variant = mkOption {
              type = types.nullOr (types.enum (attrNames pack.variants));
              default = null;
              description = ''
                Model variant for ${pack.description}. Required when this pack is enabled.
                Available variants: ${concatStringsSep ", " (attrNames pack.variants)}.
              '';
            };
          };
        };
        default = { };
        description = "Configuration for ${pack.description}.";
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
    assertions = map (name: {
      assertion = !cfg.modelPacks.${name}.enable || cfg.modelPacks.${name}.variant != null;
      message = "services.comfyui.modelPacks.${name}.variant must be set when enabling ${name}. Valid variants: ${
        concatStringsSep ", " (attrNames packDefinitions.${name}.variants)
      }.";
    }) variantPackNames;

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
