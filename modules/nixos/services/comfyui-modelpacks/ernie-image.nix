{
  aitModel,
  commonImageNodes,
  easyUseNode,
  ggufNode,
  patchedWorkflowFile,
  res4lyfNode,
  vrgamegirlNode,
  wlshNode,
  workflowFile,
  ...
}:

let
  workflow = "ERNIE-IMAGE-ULTRA-WORKFLOW.json";

  variant = suffix: vram: {
    description = vram;
    models = [
      (aitModel "unet/z_image_turbo-${suffix}.gguf")
      (aitModel "unet/ernie-image-turbo-${suffix}.gguf")
    ];
    files = [
      (patchedWorkflowFile workflow [
        {
          from = "z_image_turbo-Q8_0.gguf";
          to = "z_image_turbo-${suffix}.gguf";
        }
        {
          from = "ernie-image-turbo-Q8_0.gguf";
          to = "ernie-image-turbo-${suffix}.gguf";
        }
      ])
    ];
  };
in
{
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
  variants = {
    q5_k_s = variant "Q5_K_S" "GPUs under 8 GB VRAM";
    q6_k = variant "Q6_K" "GPUs with 8-12 GB VRAM";
    q8_0 = (variant "Q8_0" "Best quality, GPUs with 12-16 GB or more VRAM") // {
      files = [ (workflowFile workflow) ];
    };
  };
}
