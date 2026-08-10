# A machine configured with the example seed must fail to EVALUATE, unless it
# opts in explicitly. Evaluation is the only place that stops `nixos-rebuild
# boot` as well as `switch`.
{
  pkgs,
  self,
  nixpkgs,
}:
let
  mk =
    diversity:
    (nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.diversity
        {
          sovereign.diversity = diversity;
          fileSystems."/" = {
            device = "/dev/null";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = "25.11";
        }
      ];
    }).config.system.build.toplevel.drvPath;
in
# Forcing drvPath forces config.assertions; a failed assertion is a throw.
assert
  (builtins.tryEval (mk {
    enable = true;
    seed = "__example__";
  })).success == false;
assert
  (builtins.tryEval (mk {
    enable = true;
    seed = "__example__";
    allowExampleSeed = true;
  })).success;
assert
  (builtins.tryEval (mk {
    enable = true;
    seed = "a-real-host-seed";
  })).success;
pkgs.runCommand "seed-guard-ok" { } "echo ok > $out"
