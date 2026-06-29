{ lib, pkgs, ... }:

let
  helpers = import ./common.nix {
    assets = ./.;
    inherit lib pkgs;
  };
in
{
  ideogram4 = import ./ideogram4.nix helpers;
  ernieImage = import ./ernie-image.nix helpers;
  kleinEdit = import ./klein-edit.nix helpers;
  krea2 = import ./krea2.nix helpers;
  ltx23 = import ./ltx23.nix helpers;
}
