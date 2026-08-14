{ pkgs, self }:
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
    assert machine.succeed("sysctl -n kernel.kptr_restrict").strip() == "2"
    assert machine.succeed("sysctl -n kernel.dmesg_restrict").strip() == "1"
    assert machine.succeed("sysctl -n kernel.unprivileged_bpf_disabled").strip() == "1"
    assert machine.succeed("sysctl -n kernel.yama.ptrace_scope").strip() == "1"
    machine.succeed("grep -q 'init_on_alloc=1' /proc/cmdline")
    machine.succeed("grep -q 'init_on_free=1' /proc/cmdline")
    machine.wait_for_unit("sshd.service")
    machine.succeed("grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config")
    machine.succeed("grep -q 'PermitRootLogin no' /etc/ssh/sshd_config")
  '';
}
