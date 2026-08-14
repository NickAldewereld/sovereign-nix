# Proves that nixosModules.default plus the laptop profile evaluate together
# (option merge works, no collisions between the four modules).
{
  pkgs,
  self,
  nixpkgs,
}:
let
  sys = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.default
      ../profiles/laptop.nix
      {
        sovereign.impermanence.device = "/dev/mapper/cryptroot";
        sovereign.impermanence.persistPaths = [ "/etc/nixos" ];
        # This check deliberately evaluates on the default (sentinel) seed.
        sovereign.diversity.allowExampleSeed = true;
        fileSystems."/" = {
          device = "/dev/mapper/cryptroot";
          fsType = "btrfs";
          options = [ "subvol=@root" ];
        };
        boot.loader.grub.enable = false;
        system.stateVersion = "25.11";
      }
    ];
  };
  port = sys.config.sovereign.diversity.derived.sshPort;
in
assert port >= 20000 && port <= 59999;
# Force full config evaluation (not just the two attrs above) so option
# collisions and assertions actually fire. drvPath only evaluates the
# derivation, it does not build it.
#
# Both published hosts go through the same forcing, so neither can rot into a
# configuration that no longer evaluates while nobody is looking.
builtins.seq sys.config.system.build.toplevel.drvPath (
  builtins.seq self.nixosConfigurations.vm.config.system.build.toplevel.drvPath (
    builtins.seq self.nixosConfigurations.example.config.system.build.toplevel.drvPath (
      pkgs.runCommand "default-module-ok" { } "echo ok > $out"
    )
  )
)
