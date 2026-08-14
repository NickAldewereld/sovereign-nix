# Reads the hardening policy back off a booted machine. Every assertion is
# generated from lib/harden-policy.nix, so the module and this check cannot
# drift; checks/mutation.nix proves the comparison has teeth.
{ pkgs, self }:
let
  inherit (pkgs) lib;
  policy = import ../lib/harden-policy.nix;

  sysctlLines = lib.mapAttrsToList (
    k: v: ''machine.succeed("test \"$(sysctl -n ${k})\" = \"${toString v}\"")''
  ) policy.sysctls;

  cmdlineLines = map (p: ''machine.succeed("grep -q '${p}' /proc/cmdline")'') policy.kernelParams;

  # `sshd -T` prints resolved directives lower-case, one per line.
  sshdLines = lib.mapAttrsToList (
    k: v:
    let
      value = if lib.isBool v then (if v then "yes" else "no") else toString v;
    in
    ''machine.succeed("${pkgs.openssh}/bin/sshd -T | grep -qix '${lib.toLower k} ${value}'")''
  ) policy.sshd;
in
pkgs.testers.runNixOSTest {
  name = "sovereign-harden";
  nodes.machine = {
    imports = [ self.nixosModules.harden ];
    sovereign.harden.enable = true;
    services.openssh.enable = true;
    # Root cannot log in over SSH once this module is on, so the lockout
    # assertion wants somebody who can. Same reason a real host needs one.
    users.users.test = {
      isNormalUser = true;
      hashedPasswordFile = "/persist/etc/passwd.test";
    };
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    ${lib.concatStringsSep "\n    " sysctlLines}
    ${lib.concatStringsSep "\n    " cmdlineLines}
    # PID 1 owns the listening socket, so sshd.service is idle by design
    machine.wait_for_unit("sshd.socket")
    ${lib.concatStringsSep "\n    " sshdLines}
  '';
}
