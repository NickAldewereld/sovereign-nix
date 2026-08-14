# Kernel, sshd and firewall hardening. Independent of the other modules.
{ config, lib, ... }:
let
  cfg = config.sovereign.harden;

  # Somebody who can actually get in: a key or a password, declared here so
  # the configuration itself proves it.
  canLogIn =
    u:
    u.openssh.authorizedKeys.keys != [ ]
    || u.openssh.authorizedKeys.keyFiles != [ ]
    || u.hashedPassword != null
    || u.hashedPasswordFile != null
    || u.initialPassword != null
    || u.initialHashedPassword != null
    || u.password != null;

  humans = lib.filter (u: u.isNormalUser) (lib.attrValues config.users.users);

  # With mutableUsers (the NixOS default) a password can be set later with
  # `passwd`, so a user without declared credentials might still get in and
  # this module cannot prove otherwise. Note that on an ephemeral root such a
  # password only survives if /etc/shadow is persisted.
  someoneCanLogIn = lib.any canLogIn humans || (config.users.mutableUsers && humans != [ ]);

  rootIsLockedOut =
    cfg.ssh
    && config.services.openssh.enable
    && config.services.openssh.settings.PermitRootLogin == "no";
in
{
  options.sovereign.harden = {
    enable = lib.mkEnableOption "kernel, sshd and firewall hardening";
    ssh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Harden sshd (key-only, modern crypto).";
    };
    firewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the default-deny firewall.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Locking yourself out should not compile. This module closes root's
        # SSH door; if nothing else opens, the machine is unreachable the
        # moment it reboots, and on an ephemeral root a password set by hand
        # does not survive to save you. Stopped at evaluation, like the seed
        # guard, because that is the only point that also stops
        # `nixos-rebuild boot`.
        assertions = [
          {
            assertion = !rootIsLockedOut || someoneCanLogIn;
            message = ''
              sovereign.harden: this configuration locks you out. Root cannot
              log in over SSH (PermitRootLogin = "no") and there is no normal
              user who can, so nothing can reach this machine.

              Pick one:
                users.users.<name> = {
                  isNormalUser = true;
                  extraGroups = [ "wheel" ];
                  openssh.authorizedKeys.keys = [ "<your public key>" ];
                };

              or give a user `hashedPasswordFile` for console access, or set
              `sovereign.harden.ssh = false` if you harden sshd yourself.
            '';
          }
        ];

        boot.kernel.sysctl = {
          "kernel.kptr_restrict" = 2;
          "kernel.dmesg_restrict" = 1;
          "kernel.unprivileged_bpf_disabled" = 1;
          "net.core.bpf_jit_harden" = 2;
          "kernel.yama.ptrace_scope" = 1;
          "net.ipv4.conf.all.rp_filter" = 1;
          "net.ipv4.conf.default.rp_filter" = 1;
          "net.ipv4.tcp_syncookies" = 1;
          "fs.protected_symlinks" = 1;
          "fs.protected_hardlinks" = 1;
          "fs.protected_fifos" = 2;
          "fs.protected_regular" = 2;
        };
        boot.kernelParams = [
          "init_on_alloc=1"
          "init_on_free=1"
          "page_alloc.shuffle=1"
        ];
        nix.settings.sandbox = true;
        security.sudo.execWheelOnly = true;
      }
      (lib.mkIf cfg.ssh {
        services.openssh.settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
          Ciphers = [
            "chacha20-poly1305@openssh.com"
            "aes256-gcm@openssh.com"
          ];
          KexAlgorithms = [
            "sntrup761x25519-sha512@openssh.com"
            "curve25519-sha256"
          ];
          Macs = [
            "hmac-sha2-512-etm@openssh.com"
            "hmac-sha2-256-etm@openssh.com"
          ];
        };
      })
      (lib.mkIf cfg.firewall { networking.firewall.enable = true; })
    ]
  );
}
