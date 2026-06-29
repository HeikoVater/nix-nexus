{
  aitModel,
  commonImageNodes,
  easyUseNode,
  ggufNode,
  patchedWorkflowFile,
  pkgs,
  res4lyfNode,
  workflowFile,
  node,
  nodeAt,
  ...
}:

let
  workflow = "LTX-2-3_ULTRA_WORKFLOW-V2-UPDATED.json";

  variant = suffix: vram: {
    description = vram;
    models = [ (aitModel "unet/ltx-2.3-22b-dev-${suffix}.gguf") ];
    files = [
      (patchedWorkflowFile workflow [
        {
          from = "ltx-2.3-22b-dev-Q8_0.gguf";
          to = "ltx-2.3-22b-dev-${suffix}.gguf";
        }
      ])
    ];
  };
in
{
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
    (aitModel "latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors")
    (aitModel "clip_vision/ltxv_spatial_upscaler_v1.0.safetensors")
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
  variants = {
    q4_k_s = variant "Q4_K_S" "GPUs under 12 GB VRAM";
    q5_k_s = variant "Q5_K_S" "GPUs with 12-16 GB VRAM";
    q8_0 = (variant "Q8_0" "Best quality, GPUs with 24 GB or more VRAM") // {
      files = [ (workflowFile workflow) ];
    };
  };
}
