{ pkgs, self }:
pkgs.testers.runNixOSTest {
  name = "sovereign-defaults";
  nodes.machine = {
    imports = [ self.nixosModules.sovereign ];
    sovereign.defaults.enable = true;
    networking.networkmanager.enable = true;
    # qemu-vm.nix disables timesyncd unconditionally (guest gets its clock
    # from KVM) — force it on here so the test can observe our NTP config.
    services.timesyncd.enable = pkgs.lib.mkForce true;
  };
  testScript = ''
    machine.wait_for_unit("systemd-resolved.service")
    machine.succeed("grep -q 'DNSOverTLS=true' /etc/systemd/resolved.conf")
    machine.succeed("grep -q '86.54.11.1#protective.joindns4.eu' /etc/systemd/resolved.conf")
    machine.succeed("grep -q '9.9.9.9#dns.quad9.net' /etc/systemd/resolved.conf")
    machine.succeed("grep -q 'Domains=~.' /etc/systemd/resolved.conf")
    machine.succeed("grep -q 'nl.pool.ntp.org' /etc/systemd/timesyncd.conf")
    # NetworkManager must not hand the DHCP resolvers to resolved: the link
    # scope carries the default route and its cleartext answer wins the race.
    machine.succeed("grep -q '^dns=none' /etc/NetworkManager/NetworkManager.conf")
    machine.succeed("grep -q '^systemd-resolved=false' /etc/NetworkManager/NetworkManager.conf")
  '';
}
