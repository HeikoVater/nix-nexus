{
  aitModel,
  commonImageNodes,
  patchedWorkflowFile,
  pkgs,
  pythonPins450,
  res4lyfNode,
  workflowFile,
  node,
  ...
}:

let
  workflow = "KREA2_ULTRA_WORKFLOW-V2.json";

  variant = filename: description: {
    inherit description;
    models = [ (aitModel "diffusion_models/${filename}") ];
    files = [
      (patchedWorkflowFile workflow [
        {
          from = "krea2_turbo_mxfp8.safetensors";
          to = filename;
        }
      ])
    ];
  };
in
{
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
  variants = {
    mxfp8 = (variant "krea2_turbo_mxfp8.safetensors" "Recommended MXFP8 model") // {
      files = [ (workflowFile workflow) ];
    };
    fp8 = variant "krea2_turbo_fp8.safetensors" "FP8 model";
  };
}
