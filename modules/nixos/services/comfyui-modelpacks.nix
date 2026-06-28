{ lib, pkgs, ... }:

let
  inherit (lib)
    attrNames
    filterAttrs
    hasSuffix
    sort
    ;

  assets = ./comfyui-modelpacks;

  aitFlx = "https://huggingface.co/Aitrepreneur/FLX/resolve/main";
  ideogram4Base = "https://huggingface.co/Comfy-Org/Ideogram-4/resolve/main";

  workflowFile = name: {
    src = assets + "/workflows/${name}";
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
in
{
  ideogram4 = {
    description = "Ideogram 4 Ultra workflow and model pack";
    enableManager = true;
    sanitizeRequirements = true;
    disableManagerMatrix = true;
    opencv = "headless";
    python = {
      pillow11 = true;
    };
    nodes = commonImageNodes;
    models = [
      (model "diffusion_models/ideogram4_fp8_scaled.safetensors" "${ideogram4Base}/diffusion_models/ideogram4_fp8_scaled.safetensors?download=true")
      (model "diffusion_models/ideogram4_unconditional_fp8_scaled.safetensors" "${ideogram4Base}/diffusion_models/ideogram4_unconditional_fp8_scaled.safetensors?download=true")
      (aitModel "text_encoders/gemma4_e4b_it_fp8_scaled.safetensors")
      (aitModel "text_encoders/qwen3vl_8b_fp8_scaled.safetensors")
      (aitModel "vae/flux2-vae.safetensors")
    ];
    extraDependencies = [ "piexif" ];
    files = [
      (workflowFile "IDEOGRAM_ULTRA_WORKFLOW-V2.json")
    ]
    ++ templateFiles "ideogram4" (assets + "/templates/ideogram4");
  };

  ernieImage = {
    description = "ERNIE Image Ultra workflow and model pack";
    enableManager = true;
    sanitizeRequirements = true;
    disableManagerMatrix = true;
    opencv = "headless";
    python = {
      pillow11 = true;
    };
    nodes = [
      ggufNode
      easyUseNode
      wlshNode
      vrgamegirlNode
      res4lyfNode
    ]
    ++ commonImageNodes;
    models = [
      (aitModel "text_encoders/Qwen3-4B-UD-Q6_K_XL.gguf")
      (aitModel "text_encoders/ministral-3-3b.safetensors")
      (aitModel "text_encoders/ernie-image-prompt-enhancer.safetensors")
      (aitModel "vae/ae.safetensors")
      (aitModel "vae/flux2-vae.safetensors")
      (aitModel "unet/z_image_turbo-Q8_0.gguf")
      (aitModel "unet/ernie-image-turbo-Q8_0.gguf")
      (aitModel "upscale_models/4x-ClearRealityV1.pth")
      (aitModel "upscale_models/RealESRGAN_x4plus_anime_6B.pth")
    ];
    extraDependencies = [
      "gguf"
      "piexif"
      "librosa"
      "google-generativeai"
      "google-ai-generativelanguage"
    ];
    files = [
      (workflowFile "ERNIE-IMAGE-ULTRA-WORKFLOW.json")
    ];
  };

  kleinEdit = {
    description = "Klein Edit Ultra workflow and model pack";
    enableManager = true;
    sanitizeRequirements = true;
    disableManagerMatrix = true;
    disableImpactSam2 = true;
    protectManagerPackages = true;
    opencv = "contrib";
    python = pythonPins450;
    runtimePackages = [ pkgs.ffmpeg ];
    nodes = [
      ggufNode
      easyUseNode
      wlshNode
      vrgamegirlNode
      res4lyfNode
      (node "ComfyUI-Detail-Daemon" "https://github.com/Jonseed/ComfyUI-Detail-Daemon.git")
      (node "comfyui_controlnet_aux" "https://github.com/Fannovel16/comfyui_controlnet_aux.git")
      (node "ComfyUI_LayerStyle" "https://github.com/chflame163/ComfyUI_LayerStyle.git")
    ]
    ++ commonImageNodes;
    models = [
      (aitModel "text_encoders/qwen_3_8b_fp8mixed_abliterated.safetensors")
      (aitModel "vae/flux2-vae.safetensors")
      (aitModel "loras/KLEIN-DETAILER.safetensors")
      (aitModel "loras/uncrop_F2K9B.safetensors")
      (aitModel "loras/anime2real-semi.safetensors")
      (aitModel "loras/darkBeastFeb1826Latest_dbkBlitzV15.safetensors")
      (aitModel "loras/lenovo_flux_klein9b.safetensors")
      (aitModel "loras/nicegirls_flux_klein9b.safetensors")
      (aitModel "unet/flux-2-klein-9b-Q8_0.gguf")
      (aitModel "diffusion_models/flux-2-klein-9b-fp8.safetensors")
      (aitModel "upscale_models/4x-ClearRealityV1.pth")
      (aitModel "upscale_models/RealESRGAN_x4plus_anime_6B.pth")
    ];
    extraDependencies = [
      "requests>=2.32.3,<3"
      "charset-normalizer>=2,<4"
      "chardet<6"
      "fsspec<=2025.3.0,>=2023.1.0"
      "matplotlib"
      "scipy"
      "scikit-image"
      "scikit-learn"
      "pymatting"
      "timm"
      "colour-science"
      "blend_modes"
      "loguru"
      "gguf"
      "piexif"
      "lark"
      "librosa"
      "google-generativeai"
      "google-ai-generativelanguage"
    ];
    files = [
      (workflowFile "KLEIN_EDIT_ULTRA_WORKFLOW.json")
    ];
  };

  krea2 = {
    description = "Krea 2 Ultra workflow and model pack";
    enableManager = true;
    sanitizeRequirements = true;
    disableManagerMatrix = true;
    protectManagerPackages = true;
    python = pythonPins450;
    runtimePackages = [ pkgs.ffmpeg ];
    nodes = [
      res4lyfNode
      (node "ComfyUI-RBG-SmartSeedVariance" "https://github.com/RamonGuthrie/ComfyUI-RBG-SmartSeedVariance.git")
      (node "ComfyUI-Krea2T-Enhancer" "https://github.com/capitan01R/ComfyUI-Krea2T-Enhancer.git")
    ]
    ++ commonImageNodes;
    models = [
      (aitModel "text_encoders/qwen3vl_4b_fp8_scaled.safetensors")
      (aitModel "vae/qwen_image_vae.safetensors")
      (aitModel "diffusion_models/krea2_turbo_mxfp8.safetensors")
      (aitModel "loras/krea2_turbo_lora_rank_64_bf16.safetensors")
    ];
    extraDependencies = [
      "requests>=2.32.3,<3"
      "charset-normalizer>=2,<4"
      "chardet<6"
      "fsspec<=2025.3.0,>=2023.1.0"
      "piexif"
      "lark"
      "librosa"
    ];
    files = [
      (workflowFile "KREA2_ULTRA_WORKFLOW-V2.json")
    ];
  };

  ltx23 = {
    description = "LTX 2.3 Ultra workflow and model pack";
    enableManager = true;
    sanitizeRequirements = true;
    disableManagerMatrix = true;
    disableImpactSam2 = true;
    protectManagerPackages = true;
    opencv = "headless";
    python = {
      numpyRange = true;
      pillow11 = true;
      transformersMin = "4.51.3";
      hfHub = true;
      tokenizers021 = true;
      timm1015 = true;
    };
    runtimePackages = [ pkgs.ffmpeg ];
    nodes = [
      ggufNode
      easyUseNode
      res4lyfNode
      (nodeAt "ComfyUI-LTXVideo" "https://github.com/Lightricks/ComfyUI-LTXVideo.git"
        "cd5d371518afb07d6b3641be8012f644f25269fc"
      )
      (node "ComfyUI-Custom-Scripts" "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git")
      (node "ComfyUI-VideoHelperSuite" "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git")
      (node "ComfyUI-WanVideoWrapper" "https://github.com/kijai/ComfyUI-WanVideoWrapper.git")
      (node "ComfyUI-Impact-Pack" "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git")
      (node "Comfyui_TTP_Toolset" "https://github.com/TTPlanetPig/Comfyui_TTP_Toolset.git")
      (node "ComfyMath" "https://github.com/evanspearman/ComfyMath.git")
      (node "WhatDreamsCost-ComfyUI" "https://github.com/WhatDreamsCost/WhatDreamsCost-ComfyUI.git")
    ]
    ++ commonImageNodes;
    models = [
      (aitModel "text_encoders/ltx-2.3_text_projection_bf16.safetensors")
      (aitModel "text_encoders/gemma_3_12B_it_fp4_mixed.safetensors")
      (aitModel "vae/LTX23_audio_vae_bf16.safetensors")
      (aitModel "vae/LTX23_video_vae_bf16.safetensors")
      (aitModel "unet/ltx-2.3-22b-dev-Q8_0.gguf")
      (aitModel "latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors")
      (aitModel "loras/ltx-2.3-22b-distilled-lora-384-1.1.safetensors")
      (aitModel "loras/ltx-2-19b-ic-lora-detailer.safetensors")
    ];
    extraDependencies = [
      "safetensors>=0.4.3"
      "accelerate>=0.34.0"
      "filelock"
      "packaging"
      "pyyaml"
      "regex"
      "requests"
      "tqdm"
      "boto3"
      "rotary-embedding-torch"
      "deepdiff"
      "py-cpuinfo"
      "diffusers"
      "gguf"
      "piexif"
      "einops"
      "sentencepiece"
      "protobuf"
      "av"
      "imageio"
      "imageio-ffmpeg"
      "soundfile"
      "librosa"
    ];
    files = [
      (workflowFile "LTX-2-3_ULTRA_WORKFLOW-V2-UPDATED.json")
    ];
  };
}
