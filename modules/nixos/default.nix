{ lib, ... }:

{
  imports = [
    ./host
    ./services
    ./workstation
  ];

  # Prefer declarative users by default across the repo. `hosts/wsl/wanzl`
  # is the current exception because it intentionally avoids secrets.
  users.mutableUsers = lib.mkDefault false;
}
