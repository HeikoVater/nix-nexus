{
  assets,
  lib,
  pkgs,
}:

let
  inherit (lib)
    attrNames
    filterAttrs
    hasSuffix
    sort
    ;

  aitFlx = "https://huggingface.co/Aitrepreneur/FLX/resolve/main";
  ideogram4Base = "https://huggingface.co/Comfy-Org/Ideogram-4/resolve/main";

  workflowPath = name: assets + "/workflows/${name}";
in
rec {
  inherit
    aitFlx
    assets
    ideogram4Base
    lib
    pkgs
    ;

  workflowFile = name: {
    src = workflowPath name;
    target = "user/default/workflows/${name}";
  };

  patchedWorkflowFile = name: replacements: {
    src = pkgs.writeText "comfyui-${name}" (
      builtins.replaceStrings (map (replacement: replacement.from) replacements) (map (
        replacement: replacement.to
      ) replacements) (builtins.readFile (workflowPath name))
    );
    target = "user/default/workflows/${name}";
  };

  templateFiles =
    packName: dir:
    let
      jsonFiles = sort builtins.lessThan (
        attrNames (
          filterAttrs (name: kind: kind == "regular" && hasSuffix ".json" name) (builtins.readDir dir)
        )
      );
    in
    map (name: {
      src = dir + "/${name}";
      target = "user/default/kjnodes/${packName}/templates/${name}";
    }) jsonFiles;

  model = path: url: { inherit path url; };
  aitModel = path: model path "${aitFlx}/${baseNameOf path}?download=true";

  node = name: url: { inherit name url; };
  nodeAt = name: url: ref: { inherit name url ref; };

  commonImageNodes = [
    (node "rgthree-comfy" "https://github.com/rgthree/rgthree-comfy.git")
    (node "ComfyUI-KJNodes" "https://github.com/kijai/ComfyUI-KJNodes.git")
    (node "ComfyUI_essentials" "https://github.com/cubiq/ComfyUI_essentials.git")
  ];

  ggufNode = node "ComfyUI-GGUF" "https://github.com/city96/ComfyUI-GGUF.git";
  easyUseNode = node "ComfyUI-Easy-Use" "https://github.com/yolain/ComfyUI-Easy-Use.git";
  res4lyfNode = node "RES4LYF" "https://github.com/ClownsharkBatwing/RES4LYF.git";
  vrgamegirlNode = node "comfyui-vrgamedevgirl" "https://github.com/vrgamegirl19/comfyui-vrgamedevgirl.git";
  wlshNode = node "wlsh_nodes" "https://github.com/wallish77/wlsh_nodes.git";

  pythonPins450 = {
    numpy126 = true;
    pillow11 = true;
    transformersMin = "4.50.3";
    hfHub = true;
    tokenizers021 = true;
  };
}
