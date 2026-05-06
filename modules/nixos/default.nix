{ lib, ... }:

let
  certDir = ../../certs;
  certFiles = map (name: certDir + "/${name}") (
    builtins.attrNames (lib.filterAttrs (_: type: type != "directory") (builtins.readDir certDir))
  );
in

{
  imports = [
    ./host
    ./services
    ./workstation
  ];

  security.pki.certificateFiles = certFiles;

  # Prefer declarative users by default across the repo. `hosts/wsl/wanzl`
  # is the current exception because it intentionally avoids secrets.
  users.mutableUsers = lib.mkDefault false;
}
