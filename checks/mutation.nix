# Mutation testing. A check that never fails proves nothing, and there is no
# way to tell the two apart by reading it. So: break every hardening value on
# purpose, one at a time, and require the comparison to notice each time.
#
# This runs at evaluation, not in a VM, so it tests that the policy reaches
# the configuration. checks/harden.nix is what tests that the configuration
# reaches the running machine.
{
  pkgs,
  self,
  nixpkgs,
}:
let
  lib = nixpkgs.lib;
  policy = import ../lib/harden-policy.nix;

  configOf =
    extra:
    (lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.harden
        {
          sovereign.harden.enable = true;
          services.openssh.enable = true;
          users.users.test = {
            isNormalUser = true;
            hashedPasswordFile = "/persist/etc/passwd.test";
          };
          fileSystems."/" = {
            device = "/dev/null";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = "25.11";
        }
        extra
      ];
    }).config;

  # The whole policy, still intact in this configuration?
  holds =
    c:
    lib.all (k: toString c.boot.kernel.sysctl.${k} == toString policy.sysctls.${k}) (
      lib.attrNames policy.sysctls
    )
    && lib.all (p: lib.elem p c.boot.kernelParams) policy.kernelParams
    && lib.all (k: c.services.openssh.settings.${k} == policy.sshd.${k}) (lib.attrNames policy.sshd);

  # One mutant per value, each breaking exactly one thing.
  mutants =
    (map (k: { boot.kernel.sysctl.${k} = lib.mkForce 12345; }) (lib.attrNames policy.sysctls))
    ++ [ { boot.kernelParams = lib.mkForce [ ]; } ]
    ++ (map (k: {
      services.openssh.settings.${k} = lib.mkForce (
        if lib.isBool policy.sshd.${k} then !policy.sshd.${k} else "yes"
      );
    }) (lib.attrNames policy.sshd));
in
# Unmutated, everything holds. Without this the rest could pass vacuously.
assert holds (configOf { });
# And every single mutant is caught.
assert lib.all (m: !(holds (configOf m))) mutants;
pkgs.runCommand "mutation-ok" { } "echo ok > $out"
