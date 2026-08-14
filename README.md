# sovereign-nix

NixOS modules for machines that are hard to attack **at scale**.

Every machine unique in *configuration*, every boot clean, every line
auditable.

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

Status: v1, running on one reference host. Interfaces may still change.
Licence: [EUPL-1.2](LICENSE).

## Claims and the tests that back them

Every claim below is checked by `nix flake check`. If a claim has a limit, it
is stated here rather than left for you to discover.

| Claim | Evidence |
|---|---|
| Hardening is actually applied | [`checks/harden.nix`](checks/harden.nix) reads the sysctls and `/proc/cmdline` inside a booted VM |
| Two seeds, two configurations (not: two attack surfaces) | [`checks/diversity.nix`](checks/diversity.nix) boots two VMs with different seeds and finds SSH on different ports; port 22 is closed |
| The derived SSH port cannot be stolen by an ephemeral socket | [`checks/diversity.nix`](checks/diversity.nix) reads `ip_local_reserved_ports` in both booted VMs |
| Same seed, same machine | [`checks/diversity-lib.nix`](checks/diversity-lib.nix) asserts the derivation is deterministic and stays in range |
| The root really is thrown away | [`checks/impermanence.nix`](checks/impermanence.nix) wipes a scratch btrfs disk twice, including nested subvolumes, and proves `/persist` survives |
| One previous root survives for inspection | [`checks/impermanence.nix`](checks/impermanence.nix) finds the old root under `@root_prev` after a wipe, and gone after the next one |
| Incident response can stop the wipe | [`checks/impermanence.nix`](checks/impermanence.nix) runs the wipe with `sovereign.nowipe` on the command line and finds both roots intact |
| EU resolvers over TLS, EU time | [`checks/sovereign.nix`](checks/sovereign.nix) reads the generated `resolved.conf` and `timesyncd.conf` |
| The four modules compose | [`checks/default-module.nix`](checks/default-module.nix) forces a full system evaluation |
| The seed is an input, not a file read at eval time | [`checks/seed-input.nix`](checks/seed-input.nix) reads the seed back out of the evaluated host and asserts `hosts/example/default.nix` contains no `pathExists`/`readFile` |
| The example seed cannot reach a machine by accident | [`checks/seed-guard.nix`](checks/seed-guard.nix) proves a system on the sentinel seed fails to *evaluate*, and that `allowExampleSeed` is the only way past it |
| No real identity is published | [`checks/no-personal-data.nix`](checks/no-personal-data.nix) greps the whole tree for SSH key types, e-mail addresses, disk serials and the author's own names |
| Someone else can actually take this flake as an input | [`checks/consumable.nix`](checks/consumable.nix) fails the build if `flake.lock` ever contains a `path` input again |

## Limits: what the tests cannot prove

Two things were verified by hand instead:

- **A real boot cycle.** The impermanence check exercises the wipe logic on a
  scratch disk, not a reboot. On the reference host, a file created in `/`
  was gone after reboot while `/persist` and `/home` were intact.
- **Reachable resolvers.** A test can only assert what was configured. The DoT
  endpoints were verified by hand: `dns0.eu` did not answer on port 853 from a
  major Dutch ISP, which is why the defaults are DNS4EU and Quad9.

Four things are not proven at all, and are not claimed:

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

Kernel sysctls (`kptr_restrict`, `dmesg_restrict`, unprivileged BPF off, Yama
ptrace scope), boot parameters (`init_on_alloc`, `init_on_free`), a key-only
sshd with modern crypto, a default-deny firewall, and the Nix sandbox on.

`harden.firewall = false` means "do not touch the firewall", not "disable it".

### `sovereign.diversity`

One pure function turns a per-host seed into reproducible values: the SSH
port and harmless kernel tuning. Same seed, same machine, so a config is still
auditable, diffable and reproducible after a reinstall. That determinism is
the point: uniqueness you cannot reconstruct is uniqueness you cannot audit.

What this buys, stated narrowly: a host that does not answer where a mass
scanner expects it, and a fleet where one hardcoded shape does not fit every
member. It does **not** make an exploit fail on the next host. See
[Limits](#limits-what-the-tests-cannot-prove).

The derived port is also added to `net.ipv4.ip_local_reserved_ports`. Without
that, the range (20000-59999) overlaps the kernel's ephemeral source-port
range (32768-60999), so an outbound connection can be holding the sshd port at
the moment sshd restarts.

MAC randomisation is enabled here too, but it is **privacy, not security**: it
stops a network from tracking the host across visits. It does not shrink the
attack surface, and it is listed under this module only because it is derived
from the same "each host looks different" idea.

The seed is defence in depth, not a secret. If it leaks you lose a layer, not
the system. Keep it out of public repositories anyway.

### `sovereign.impermanence`

btrfs `@root` is rolled back to an empty subvolume in the initrd on every
boot. Only `/nix`, `/home` and the paths you list in `persistPaths` survive.
Malware persistence in the system root, stray config drift and forgotten debug
edits die at the next reboot. Persistence in `/home` does not: see
[Limits](#limits-what-the-tests-cannot-prove).

Failures are loud: if the wipe cannot run, the machine says so on the console
and boots the old root rather than silently pretending.

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

Impermanence expects a btrfs filesystem with `@root`, `@nix`, `@persist` and
`@home` subvolumes. [`hosts/example/disko.nix`](hosts/example/disko.nix) is a
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
evaluates it like any other input. Two hosts with different seeds produce
different derivations and different store paths — there is no collision.

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

## Reference host

[`hosts/example/`](hosts/example/) is a complete laptop configuration running
all four modules on LUKS + btrfs with GNOME: a working disko layout you can
copy, not a sketch. It carries placeholder values for the disk, the user and
the keys.

The author runs this configuration on a ThinkPad X270. That machine's own
config is kept private, because publishing a host's username, authorised keys
and port range would undo what the diversity module is for.

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
