# Hardening closes root's SSH door. A configuration that closes it without
# opening another one must fail to EVALUATE, for the same reason as the seed
# guard: evaluation is the only point that stops `nixos-rebuild boot` as well
# as `switch`. Written after locking a test machine out exactly this way.
{
  pkgs,
  self,
  nixpkgs,
}:
let
  # A key file rather than a key literal: checks/no-personal-data.nix greps
  # the whole tree for key material, and a placeholder would trip it.
  keys = [ "/persist/etc/ssh/authorized_keys" ];
  mk =
    extra:
    (nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.harden
        {
          sovereign.harden.enable = true;
          services.openssh.enable = true;
          fileSystems."/" = {
            device = "/dev/null";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = "25.11";
        }
        extra
      ];
    }).config.system.build.toplevel.drvPath;
in
# Nobody can get in: stopped.
assert (builtins.tryEval (mk { })).success == false;
# Root keys do not count while PermitRootLogin is "no".
assert (builtins.tryEval (mk { users.users.root.openssh.authorizedKeys.keyFiles = keys; })).success
       == false;
# A normal user with a key is a way in.
assert
  (builtins.tryEval (mk {
    users.users.nick = {
      isNormalUser = true;
      openssh.authorizedKeys.keyFiles = keys;
    };
  })).success;
# So is a normal user with a password, for the console.
assert
  (builtins.tryEval (mk {
    users.users.nick = {
      isNormalUser = true;
      hashedPasswordFile = "/persist/etc/passwd.nick";
    };
  })).success;
# With mutableUsers a password can be set later, so a bare normal user is
# enough to stop the guard. Deliberate hole, documented as such.
assert
  (builtins.tryEval (mk {
    users.mutableUsers = true;
    users.users.nick.isNormalUser = true;
  })).success;
# Without mutableUsers that same user cannot get in, and the guard says so.
assert
  (builtins.tryEval (mk {
    users.mutableUsers = false;
    users.users.nick.isNormalUser = true;
  })).success == false;
# Opting out of the sshd hardening opts out of the guard with it.
assert (builtins.tryEval (mk { sovereign.harden.ssh = false; })).success;
pkgs.runCommand "lockout-guard-ok" { } "echo ok > $out"
