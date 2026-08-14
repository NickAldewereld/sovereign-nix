# A machine that wipes the directory holding its own configuration cannot
# rebuild itself. The module stops that at evaluation; this proves the guard
# actually fires, which the claims table previously asserted without any test
# behind it.
{
  pkgs,
  self,
  nixpkgs,
}:
let
  mk =
    impermanence:
    (nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.impermanence
        {
          sovereign.impermanence = {
            enable = true;
            device = "/dev/mapper/cryptroot";
          } // impermanence;
          fileSystems."/" = {
            device = "/dev/mapper/cryptroot";
            fsType = "btrfs";
            options = [ "subvol=@root" ];
          };
          boot.loader.grub.enable = false;
          system.stateVersion = "25.11";
        }
      ];
    }).config.system.build.toplevel.drvPath;
in
# Nothing persisted at all: the configuration would be gone at the first boot.
assert (builtins.tryEval (mk { persistPaths = [ ]; })).success == false;
# Persisting other things is not enough; this is the one that matters.
assert (builtins.tryEval (mk { persistPaths = [ "/var/log" ]; })).success == false;
# Persisting it clears the guard.
assert
  (builtins.tryEval (mk {
    persistPaths = [
      "/etc/nixos"
      "/var/log"
    ];
  })).success;
# And saying out loud that the config lives elsewhere clears it too.
assert
  (builtins.tryEval (mk {
    persistPaths = [ ];
    allowEphemeralConfig = true;
  })).success;
pkgs.runCommand "config-guard-ok" { } "echo ok > $out"
