{
  aitModel,
  assets,
  commonImageNodes,
  ideogram4Base,
  model,
  patchedWorkflowFile,
  templateFiles,
  workflowFile,
  ...
}:

let
  workflow = "IDEOGRAM_ULTRA_WORKFLOW-V2.json";
  diffusionModel =
    name: model "diffusion_models/${name}" "${ideogram4Base}/diffusion_models/${name}?download=true";
in
{
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
    (aitModel "text_encoders/gemma4_e4b_it_fp8_scaled.safetensors")
    (aitModel "text_encoders/qwen3vl_8b_fp8_scaled.safetensors")
    (aitModel "vae/flux2-vae.safetensors")
  ];
  extraDependencies = [ "piexif" ];
  files = templateFiles "ideogram4" (assets + "/templates/ideogram4");
  variants = {
    fp8 = {
      description = "Default FP8 conditional and unconditional models";
      models = [
        (diffusionModel "ideogram4_fp8_scaled.safetensors")
        (diffusionModel "ideogram4_unconditional_fp8_scaled.safetensors")
      ];
      files = [ (workflowFile workflow) ];
    };
    mixed = {
      description = "FP8 conditional model with NVFP4 unconditional model";
      models = [
        (diffusionModel "ideogram4_fp8_scaled.safetensors")
        (diffusionModel "ideogram4_unconditional_nvfp4_mixed.safetensors")
      ];
      files = [
        (patchedWorkflowFile workflow [
          {
            from = "ideogram4_unconditional_fp8_scaled.safetensors";
            to = "ideogram4_unconditional_nvfp4_mixed.safetensors";
          }
        ])
      ];
    };
    nvfp4 = {
      description = "NVFP4 conditional and unconditional models";
      models = [
        (diffusionModel "ideogram4_nvfp4_mixed.safetensors")
        (diffusionModel "ideogram4_unconditional_nvfp4_mixed.safetensors")
      ];
      files = [
        (patchedWorkflowFile workflow [
          {
            from = "ideogram4_fp8_scaled.safetensors";
            to = "ideogram4_nvfp4_mixed.safetensors";
          }
          {
            from = "ideogram4_unconditional_fp8_scaled.safetensors";
            to = "ideogram4_unconditional_nvfp4_mixed.safetensors";
          }
        ])
      ];
    };
  };
}
