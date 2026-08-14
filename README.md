# sovereign-nix

NixOS modules for machines that are hard to attack **at scale**.

Every boot clean, every line auditable, and every machine configured a little
differently. Not *uniquely*: see the limits below.

An exploit is cheap because it fits millions of identical systems. These
modules attack that economy: hardening shrinks the target, deterministic
diversity makes each host different in reproducible ways, and an ephemeral
root throws away whatever an attacker left in the system root. Defaults point
at European infrastructure rather than US clouds.

**This is defence in depth, not magic.** Nothing here stops phishing, a weak
passphrase, or an unpatched public service. Nothing here is unhackable.

**And to be precise about the diversity claim:** what differs between two
hosts is configuration, not binaries. The kernel image, libc and every
executable are byte-identical across hosts, by design of Nix. A working
exploit is not stopped by anything in this repository. What changes is the
cost of *untargeted, automated* attacks that assume one shape fits every host.
A targeted attacker pays nothing extra. See
[Limits](#limits-what-the-tests-cannot-prove).

Status: v1. Running on the author's laptop and on a throwaway VM that anyone
can recreate from [`hosts/vm/`](hosts/vm/). Interfaces may still change.
Licence: [EUPL-1.2](LICENSE).

## Claims and the tests that back them

Every claim below is checked by `nix flake check`. If a claim has a limit, it
is stated here rather than left for you to discover.

| Claim | Evidence |
|---|---|
| Hardening is actually applied | [`checks/harden.nix`](checks/harden.nix) reads every value from [`lib/harden-policy.nix`](lib/harden-policy.nix) back off a booted VM: the sysctls, `/proc/cmdline`, and the sshd settings as `sshd -T` resolved them rather than as the file spells them |
| Two seeds, two configurations (not: two attack surfaces) | [`checks/diversity.nix`](checks/diversity.nix) boots two VMs with different seeds and finds SSH on different ports; port 22 is closed |
| The derived SSH port cannot be stolen by an ephemeral socket | [`checks/diversity.nix`](checks/diversity.nix) reads `ip_local_reserved_ports` in both booted VMs |
| Same seed, same derived values | [`checks/diversity-lib.nix`](checks/diversity-lib.nix) asserts the derivation is deterministic and stays in range. The converse does not hold, and the same check pins a colliding pair of seeds to prove it |
| The root really is thrown away | [`checks/impermanence.nix`](checks/impermanence.nix) wipes a scratch btrfs disk twice, including nested subvolumes, and proves `/persist` survives |
| One previous root survives for inspection | [`checks/impermanence.nix`](checks/impermanence.nix) finds the old root under `@root_prev` after a wipe, and gone after the next one |
| Incident response can stop the wipe | [`checks/impermanence.nix`](checks/impermanence.nix) runs the wipe with `sovereign.nowipe` on the command line and finds both roots intact |
| EU resolvers over TLS, EU time | [`checks/sovereign.nix`](checks/sovereign.nix) reads the generated `resolved.conf` and `timesyncd.conf` |
| The four modules compose | [`checks/default-module.nix`](checks/default-module.nix) forces a full system evaluation |
| The host reads no files at evaluation time | [`checks/seed-input.nix`](checks/seed-input.nix) reads the seed back out of the evaluated host and asserts `hosts/example/default.nix` contains no `pathExists`/`readFile`. The seed reaches the host from the flake; in *your* flake it comes from an input, in this one it is the sentinel in the source tree |
| The hardening assertions are not vacuous | [`checks/mutation.nix`](checks/mutation.nix) breaks every value in [`lib/harden-policy.nix`](lib/harden-policy.nix) on purpose, one at a time, and requires the comparison to catch each one |
| A machine cannot wipe its own configuration | [`checks/config-guard.nix`](checks/config-guard.nix) proves a system that does not persist `/etc/nixos` fails to *evaluate*, and that `allowEphemeralConfig` is the only other way past it |
| PID 1 owns the SSH socket, so the port cannot be taken | [`checks/limits.nix`](checks/limits.nix) boots one machine each way and shows an unprivileged user taking the port on the old arrangement and failing on the new one |
| A configuration that locks you out does not build | [`checks/lockout-guard.nix`](checks/lockout-guard.nix) proves that hardening sshd with no way in fails to *evaluate*, that root keys do not count once root login is off, and that a user with a key or a password clears it |
| The example seed cannot reach a machine by accident | [`checks/seed-guard.nix`](checks/seed-guard.nix) proves a system on the sentinel seed fails to *evaluate*, and that `allowExampleSeed` is the only way past it |
| No real identity is published | [`checks/no-personal-data.nix`](checks/no-personal-data.nix) greps the whole tree for the *shapes* of SSH key types, e-mail addresses and disk serials, and first proves each pattern matches a planted sample so it cannot pass by matching nothing. Deliberately not names or domains: a check that spelled those out would publish the very thing it guards |
| Someone else can actually take this flake as an input | [`checks/consumable.nix`](checks/consumable.nix) fails the build if `flake.lock` ever contains a `path` input again, and refuses to pass if the lock file is missing or if its own pattern matches nothing |

## Limits: what the tests cannot prove

Two things were verified by hand instead:

- **A real boot cycle.** The impermanence check exercises the wipe logic on a
  scratch disk, not a reboot. Verified on two machines now: a file created in
  `/` was gone after reboot while `/persist` and `/home` were intact, and the
  root of the previous boot was still readable under `@root_prev`. The second
  machine was a plain VM, so anyone can repeat it.
- **Reachable resolvers.** A test can only assert what was configured, so the
  endpoints were checked by hand. An earlier version of this file said
  `dns0.eu` "did not answer on port 853 from a major Dutch ISP", which was a
  conclusion the measurement did not support: the service is simply gone.
  `zero.dns0.eu` no longer resolves and the domain now points at a parking
  host. A dead endpoint was read as a network problem. Thanks to Ryan
  Theunissen for catching it.

  What is verified, at the time of writing: both defaults complete a TLS
  handshake on port 853 with a valid certificate, and `protective.joindns4.eu`
  is in the DNS4EU certificate's SAN list, which is what `systemd-resolved`
  checks against. This is a fact about one day, not a property of the code.

These things are not proven at all, and are not claimed. Several of them are
*executable*: [`checks/limits.nix`](checks/limits.nix),
[`checks/diversity-lib.nix`](checks/diversity-lib.nix) and
[`checks/impermanence.nix`](checks/impermanence.nix) assert that the bad thing
still happens, so the day a limit stops being true the build says so instead of
the README quietly going stale.

- **Different seeds do not give different machines.** The derived values live
  in a small space: 40000 ports, 41 swappiness values, 6145 somaxconn values.
  Two hosts have a 50% chance of sharing an SSH port at around 235 machines,
  and full collisions across all three values exist:
  `john-balls-14333` and `john-balls-94081` both give port 33670, swappiness
  42 and somaxconn 3377. Found by brute force by Ryan Theunissen, and now
  pinned in [`checks/diversity-lib.nix`](checks/diversity-lib.nix) so the claim
  cannot quietly come back. Two hosts sharing a port is not a vulnerability;
  the wrong claim was the problem.
- **MAC randomisation is not derived from the seed.** It is
  `NetworkManager`'s own randomisation, a fresh address per connection. So it
  is the one value here that is deliberately *not* reproducible, and it is a
  privacy measure rather than a hardening one.
- **Binary diversity.** The diversity check proves two hosts are configured
  differently. It does not prove that an exploit working on one fails on the
  other, and it cannot: the kernel, libc and binaries are identical. Per-host
  binary diversity (a kernel built with a seed-derived `randstruct` layout, so
  struct offsets differ per host) is the open question, not a shipped feature.
  The test that would settle it is an offset-dependent proof of concept that
  succeeds on host A and fails on host B. Contributions welcome.
- **A changed SSH port as defence.** It removes the host from opportunistic
  scan and log noise. A targeted scan finds sshd in seconds, and key-only auth
  is what actually stops brute force. Treat the port as hygiene, not a control.
- **The port reservation does not stop squatting.** Measured on a test host:
  an ESTABLISHED outbound connection on the sshd port does *not* stop sshd from
  restarting, because sshd sets `SO_REUSEADDR`. What does stop it is a local
  unprivileged process that LISTENS on the port while sshd is down, which is
  possible exactly because the port is above 1023, and
  `ip_local_reserved_ports` does not prevent it: it excludes automatic
  allocation, not an explicit bind. What does close that window is socket
  activation, which this module now switches on: PID 1 binds the port at boot,
  so there is nothing to take. The limit is kept executable both ways in
  [`checks/limits.nix`](checks/limits.nix).
- **`/home` is not ephemeral.** The wipe covers the system root. `/home` is a
  separate subvolume and survives untouched, so user-level persistence
  (`~/.bashrc`, `~/.profile`, `~/.config/autostart`, a systemd user unit)
  survives a reboot. If your threat model includes an attacker who reaches a
  user account, impermanence does not evict them.
- **A reboot is not a patch.** The machine comes back in exactly the state that
  was exploitable before. What changes is that the attacker has to pay for the
  exploit again on every boot and cannot accumulate anything on the root.

## Modules

Each module is independent, has one `enable` option, and imports no other
module. Take one, take all four.

### `sovereign.harden`

Kernel sysctls, boot parameters, a key-only sshd with modern crypto, a
default-deny firewall, `sudo` restricted to the wheel group, and the Nix
sandbox on. The exact values live in
[`lib/harden-policy.nix`](lib/harden-policy.nix) rather than in this
paragraph, so a prose summary cannot drift away from what is applied.

`harden.firewall = false` means "do not touch the firewall", not "disable it".

sshd is socket-activated (`startWhenNeeded`), so PID 1 binds the port at boot
and hands sshd a ready socket. That is not a performance choice. Measured on a
test host: with sshd holding its own socket, an unprivileged local process can
take the port while sshd is down, after which sshd fails to bind `0.0.0.0`,
comes up on `::` alone, and systemd still reports the unit as `active`. A
half-listening sshd looks healthy. With the socket owned by PID 1 there is no
window to take. It costs a fork per connection; set
`services.openssh.startWhenNeeded = false` if that matters more to you.

Because this module closes root's SSH door, a configuration that leaves no
other way in **fails to evaluate**. That is not a courtesy: a hardened machine
with an ephemeral root and no user account is unreachable the moment it
reboots, and a password you set by hand does not survive the wipe to save you.
The guard is deliberately loose in one place: with `users.mutableUsers` on (the
NixOS default) a password can be set later with `passwd`, so any normal user
clears it. Turn `mutableUsers` off and the check gets strict again.

### `sovereign.diversity`

One pure function turns a per-host seed into reproducible values: the SSH
port and harmless kernel tuning. Same seed, same values, so a config is still
auditable, diffable and reproducible after a reinstall. That determinism is
the point: uniqueness you cannot reconstruct is uniqueness you cannot audit.

The reverse is not true and is not claimed. Those values live in a small
space, so two different seeds can produce an identical machine, and at fleet
scale a shared SSH port is likely rather than exotic. See
[Limits](#limits-what-the-tests-cannot-prove) for the numbers and for a
colliding pair.

What this buys, stated narrowly: a host that does not answer where a mass
scanner expects it, and a fleet where one hardcoded shape does not fit every
member. It does **not** make an exploit fail on the next host. See
[Limits](#limits-what-the-tests-cannot-prove).

The derived port is also added to `net.ipv4.ip_local_reserved_ports`, because
the range (20000-59999) overlaps the kernel's ephemeral source-port range
(32768-60999) and the kernel should never hand out the port sshd lives on.
What that does and does not buy you is measured, not assumed; see
[Limits](#limits-what-the-tests-cannot-prove).

MAC randomisation is enabled here too, and it is the odd one out twice over.
It is **privacy, not security**: it stops a network from tracking the host
across visits, it does not shrink the attack surface. And it is **not derived
from the seed at all**: NetworkManager generates a fresh address per
connection, so this is the one value in this module that is deliberately not
reproducible. It sits here only because it comes from the same "each host
looks different" idea.

The seed is defence in depth, not a secret. If it leaks you lose a layer, not
the system. Keep it out of public repositories anyway.

### `sovereign.impermanence`

btrfs `@root` is rolled back to an empty subvolume in the initrd on every
boot. What survives: the other subvolumes (`/nix`, `/persist`, `/home`), the
paths you list in `persistPaths`, and `/boot`, which is a separate partition
and is never touched by the wipe.
Malware persistence in the system root, stray config drift and forgotten debug
edits die at the next reboot. Persistence in `/home` does not: see
[Limits](#limits-what-the-tests-cannot-prove).

Failures are loud: if the wipe cannot run, the machine says so on the console
and boots the old root rather than silently pretending.

Two things that bite on a real install, both found the first time this was
installed on a machine other than the author's:

- **`/etc/nixos` has to be in `persistPaths`.** It lives on the root, so
  without it your configuration is gone at the first reboot and the machine
  cannot rebuild itself. This is now an evaluation error rather than advice.
  If the configuration genuinely lives elsewhere, set
  `allowEphemeralConfig = true` and the guard steps aside.
- **Reinstalling over an existing impermanent root fails at the bootloader**
  with `IndexError: list index out of range`. The wipe leaves an empty
  `/etc/machine-id` placeholder on the root while the real one is on
  `/persist`, and the systemd-boot installer reads the empty one. Copy it back
  first: `cp /mnt/persist/etc/machine-id /mnt/etc/machine-id`.

#### Forensics

Rolling the root back destroys evidence, so two things soften that:

- **One previous generation is kept.** The root of the boot that just ended is
  moved to `@root_prev` and is deleted at the *start of the next* boot. So
  after an incident you have exactly one boot to mount it read-only and image
  it. Set `keepPreviousRoot = false` if you would rather have a clean disk.
- **Add `sovereign.nowipe` to the kernel command line** (in systemd-boot press
  `e` at the menu) and that boot keeps its root. The `/persist` bind mounts are
  still set up, so the machine boots normally and you can work on the live
  root. Nothing needs to be rebuilt to reach this.

Also worth knowing: `/var/log` belongs on `persistPaths`, and is in the
reference host, so the audit trail survives the wipe. Volatile evidence
(memory, processes, open sockets) is gone at any reboot, with or without this
module. If it matters, capture it before you reboot.

### `sovereign.defaults`

DNS over TLS to DNS4EU with Quad9 as backup, `Domains=~.` so those servers
are actually used, NetworkManager told not to inject DHCP resolvers, and
European time servers. Mostly this module is about absence: no default here
points at a US cloud service.

Trade-off: ISP-local names (router hostnames, captive portals) stop
resolving. Scope note: the module governs *its* defaults. A desktop still
pulls in whatever your other packages talk to, and Nix itself substitutes
from `cache.nixos.org`.

## Use it

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  inputs.sovereign-nix.url = "github:NickAldewereld/sovereign-nix";

  # The per-host seed is an input, so evaluation stays pure. Point it at a
  # placeholder in your own repo and override it at rebuild time; see
  # "Where the seed comes from" below.
  inputs.hostSeed = {
    url = "path:./seed.d";
    flake = false;
  };

  outputs = { nixpkgs, sovereign-nix, hostSeed, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        sovereign-nix.nixosModules.default   # or pick individual modules
        ./hardware-configuration.nix
        {
          sovereign.harden.enable = true;
          sovereign.defaults.enable = true;

          sovereign.diversity = {
            enable = true;
            seed = nixpkgs.lib.removeSuffix "\n"
              (builtins.readFile "${hostSeed}/seed");
          };

          sovereign.impermanence = {
            enable = true;
            device = "/dev/mapper/cryptroot";
            persistPaths = [
              "/etc/NetworkManager/system-connections"
              "/var/lib/nixos"
              "/var/log"
            ];
          };
        }
      ];
    };
  };
}
```

Impermanence needs `@root` and `@persist`; the example layout also splits off
`@nix` and `@home`, and `/home` in particular has to be its own subvolume or
it goes with the root. [`hosts/example/disko.nix`](hosts/example/disko.nix) is a
working LUKS + btrfs layout you can copy.

### Where the seed comes from

The seed is a flake input **of your flake**, so evaluation stays pure and the
seed never has to live in your repository:

```nix
inputs.hostSeed = {
  url = "path:./seed.d";   # a placeholder in your own repo
  flake = false;
};
```

A real machine overrides it at rebuild time:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#myhost \
  --override-input hostSeed path:/persist/etc/sovereign/seed.d
```

This flake declares no seed input of its own. It cannot: a relative `path:`
input makes Nix refuse to read the entire lock file from the outside, so every
consumer fails with `lock file contains unlocked input` before evaluation
starts. `nix flake check` never sees it, because it only ever evaluates this
flake as the root. [`checks/consumable.nix`](checks/consumable.nix) now fails
the build if a path input ever comes back. The sentinel in `example-seed/` is
read straight from the flake source, which is pure for the same reason any
other file in the tree is.

**The overridden directory must contain a file named exactly `seed`, and
nothing else.** `--override-input ... path:` copies the *whole* directory into
`/nix/store`, which is world-readable, so anything sharing that directory is
published to every user on the machine. Give the seed a directory of its own:

```bash
sudo install -d -m 0700 /persist/etc/sovereign/seed.d
sudo mv /persist/etc/sovereign/seed /persist/etc/sovereign/seed.d/seed
```

Do not point the override at `/persist/etc/sovereign` itself — that is where
`hashedPasswordFile` and other host secrets live.

No `--impure` is involved: Nix copies the overridden path into the store and
evaluates it like any other input, so two hosts with different seeds get
different store paths and cannot overwrite each other's. That is a statement
about store paths only. The *values* derived from those seeds can collide; see
[Limits](#limits-what-the-tests-cannot-prove).

A system left on the sentinel seed fails to **evaluate**, so it is stopped
before anything is built, switched or set as the boot default:

```
Failed assertions:
- sovereign.diversity: the example seed is in use. Its SSH port is derivable
  from the public repository by anyone. Rebuild with the per-host seed: ...
```

An activation script could not do this job: `nixos-rebuild boot` runs no
activation at all, `switch-to-configuration` continues past a failed snippet,
and by the time it ran, `/etc/ssh/sshd_config` had already been rewritten.

`nix flake check` still works for everyone because the example host and the
checks set `sovereign.diversity.allowExampleSeed = true` explicitly. Delete
that line when you copy the host.

## Try it without trusting me

[`hosts/vm/`](hosts/vm/) is a throwaway machine that runs all four modules on
plain btrfs, with a published seed and a password in the file, so anyone can
boot it in QEMU and check the claims on a running system instead of taking
this file's word for them. [`hosts/vm/README.md`](hosts/vm/README.md) is the
runbook, including the reboot that no test in this repository can perform.

## Reference host

[`hosts/example/`](hosts/example/) is a complete laptop configuration running
all four modules on LUKS + btrfs with GNOME: a working disko layout you can
copy, not a sketch. It carries placeholder values for the disk, the user and
the keys.

The author runs these modules on a ThinkPad X270. That machine's own config is
kept private, because publishing a host's username, authorised keys and port
range would undo what the diversity module is for. It is a real daily machine
rather than a mirror of this repository, so do not assume it runs this exact
commit; the VM is the one you can reproduce.

## Development

```bash
nix flake check -L    # all checks, including VM tests (needs KVM)
nix fmt .
```

## Acknowledgements

The limits above are sharper than they were because people took the trouble to
review the claims in public:

- **Rick Okkersen** found the overlap between the derived SSH port and the
  kernel's ephemeral port range, pointed out that `@root_prev` was undocumented,
  that `/home` is an obvious persistence target the wipe never touches, and
  that MAC randomisation is privacy rather than security.
- **Daan Breur** pointed out that a test proving two configurations differ is
  not a test proving a security property, which is why the diversity claim is
  now labelled for what it actually demonstrates.
- **Ryan Theunissen** read the code rather than the README and took the
  remaining half of that claim apart: he brute-forced a pair of seeds that
  produce an identical machine, noticed that MAC randomisation never used the
  seed in the first place, found that this file promised four limits and then
  listed five, and established that `dns0.eu` has simply been gone since
  October 2025, so the note about it here was a conclusion the measurement did
  not support.
