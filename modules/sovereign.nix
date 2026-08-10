# Sovereign defaults: EU resolvers over TLS, EU time servers. Mostly this
# module is about absence — no default points at a US cloud service.
{ config, lib, ... }:
let
  cfg = config.sovereign.defaults;
in
{
  options.sovereign.defaults = {
    enable = lib.mkEnableOption "sovereign EU defaults (DNS-over-TLS, EU NTP)";
  };

  config = lib.mkIf cfg.enable {
    services.resolved = {
      enable = true;
      dnssec = "allow-downgrade";
      dnsovertls = "true";
      # Send every query to the servers below instead of whatever DHCP put on
      # the link. ISP resolvers do not speak DoT, so under strict DoT their
      # scope fails — and because the link scope carries the default route it
      # is tried first, leaving the machine without working DNS.
      domains = [ "~." ];
      fallbackDns = [
        "9.9.9.9#dns.quad9.net"
        "149.112.112.112#dns.quad9.net"
      ];
    };
    # Without this, NetworkManager hands the DHCP resolvers to resolved as
    # link servers. The link carries the default route, so it is queried in
    # parallel with ours and its plaintext answer usually wins the race —
    # encrypted DNS in the config, unencrypted DNS on the wire. Per-connection
    # defaults are not enough: they do not apply to existing profiles.
    # Trade-off: ISP-local names (router hostnames, captive portals) no
    # longer resolve.
    # Two separate knobs: `dns` only decides who writes resolv.conf, while
    # `systemd-resolved` is what pushes the DHCP servers to resolved over
    # D-Bus ("Bus client set DNS server list to ..."). Both have to go.
    # mkForce because enabling resolved hard-sets `dns` to "systemd-resolved".
    networking.networkmanager.dns = lib.mkForce "none";
    networking.networkmanager.settings.main."systemd-resolved" = false;

    # DNS4EU (EU-funded, EU-operated) first, Quad9 (Swiss foundation) second.
    # Both verified to answer DoT on 853 with these TLS names.
    networking.nameservers = [
      "86.54.11.1#protective.joindns4.eu"
      "86.54.11.201#protective.joindns4.eu"
      "9.9.9.9#dns.quad9.net"
    ];

    services.timesyncd.servers = [
      "0.nl.pool.ntp.org"
      "1.nl.pool.ntp.org"
      "2.nl.pool.ntp.org"
      "3.nl.pool.ntp.org"
    ];
  };
}
