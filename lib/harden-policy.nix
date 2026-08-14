# What sovereign.harden must produce, as data. The module sets these values
# and the checks read them back, so a claim and its evidence cannot drift
# apart by editing one of the two.
#
# The VM check reads them off a booted machine, which is the part that matters:
# it catches the case where something later in the boot overrides us. The
# mutation check breaks each one on purpose and requires the comparison to
# notice, which is what stops these assertions from being vacuous.
{
  sysctls = {
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

  kernelParams = [
    "init_on_alloc=1"
    "init_on_free=1"
    "page_alloc.shuffle=1"
  ];

  # NixOS option names, because these are declared options: a lower-case key
  # would be merged in as a *second* freeform directive next to the declared
  # default, and sshd takes the first occurrence. The check lower-cases them
  # itself to compare against `sshd -T`, which is the configuration sshd
  # actually resolved rather than the file it was handed.
  sshd = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };
}
