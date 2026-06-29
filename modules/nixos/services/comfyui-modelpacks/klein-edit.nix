{
  aitModel,
  commonImageNodes,
  easyUseNode,
  ggufNode,
  patchedWorkflowFile,
  pkgs,
  pythonPins450,
  res4lyfNode,
  vrgamegirlNode,
  wlshNode,
  workflowFile,
  node,
  ...
}:

let
  workflow = "KLEIN_EDIT_ULTRA_WORKFLOW.json";

  variant = suffix: vram: {
    description = vram;
    models = [ (aitModel "unet/flux-2-klein-9b-${suffix}.gguf") ];
    files = [
      (patchedWorkflowFile workflow [
        {
          from = "flux-2-klein-9b-Q8_0.gguf";
          to = "flux-2-klein-9b-${suffix}.gguf";
        }
      ])
    ];
  };
in
{
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
  variants = {
    q4_k_s = variant "Q4_K_S" "GPUs under 12 GB VRAM";
    q5_k_s = variant "Q5_K_S" "GPUs with 12-16 GB VRAM";
    q8_0 = (variant "Q8_0" "Best quality, GPUs with 12-16 GB or more VRAM") // {
      files = [ (workflowFile workflow) ];
    };
  };
}
