# sovereign-nix

NixOS modules for machines that are hard to attack **at scale**.

Every machine unique, every boot clean, every line auditable.

An exploit is cheap because it fits millions of identical systems. These
modules attack that economy: hardening shrinks the target, deterministic
diversity makes each host different in reproducible ways, and an ephemeral
root throws away whatever an attacker left behind. Defaults point at European
infrastructure rather than US clouds.

**This is defence in depth, not magic.** Nothing here stops phishing, a weak
passphrase, or an unpatched public service. Nothing here is unhackable.

Status: v1, running on one reference host. Interfaces may still change.
Licence: [EUPL-1.2](LICENSE).

## Claims and the tests that back them

Every claim below is checked by `nix flake check`. If a claim has a limit, it
is stated here rather than left for you to discover.

| Claim | Evidence |
|---|---|
| Hardening is actually applied | [`checks/harden.nix`](checks/harden.nix) reads the sysctls and `/proc/cmdline` inside a booted VM |
| Two machines, two configurations | [`checks/diversity.nix`](checks/diversity.nix) boots two VMs with different seeds and finds SSH on different ports; port 22 is closed |
| Same seed, same machine | [`checks/diversity-lib.nix`](checks/diversity-lib.nix) asserts the derivation is deterministic and stays in range |
| The root really is thrown away | [`checks/impermanence.nix`](checks/impermanence.nix) wipes a scratch btrfs disk twice, including nested subvolumes, and proves `/persist` survives |
| EU resolvers over TLS, EU time | [`checks/sovereign.nix`](checks/sovereign.nix) reads the generated `resolved.conf` and `timesyncd.conf` |
| The four modules compose | [`checks/default-module.nix`](checks/default-module.nix) forces a full system evaluation |
| The seed is an input, not a file read at eval time | [`checks/seed-input.nix`](checks/seed-input.nix) reads the seed back out of the evaluated host and asserts `hosts/example/default.nix` contains no `pathExists`/`readFile` |
| The example seed cannot reach a machine by accident | [`checks/seed-guard.nix`](checks/seed-guard.nix) proves a system on the sentinel seed fails to *evaluate*, and that `allowExampleSeed` is the only way past it |
| No real identity is published | [`checks/no-personal-data.nix`](checks/no-personal-data.nix) greps the whole tree for SSH key types, e-mail addresses, disk serials and the author's own names |

Two things the test suite cannot prove, and how they were verified instead:

- **A real boot cycle.** The impermanence check exercises the wipe logic on a
  scratch disk, not a reboot. On the reference host, a file created in `/`
  was gone after reboot while `/persist` and `/home` were intact.
- **Reachable resolvers.** A test can only assert what was configured. The DoT
  endpoints were verified by hand: `dns0.eu` did not answer on port 853 from a
  major Dutch ISP, which is why the defaults are DNS4EU and Quad9.

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
port, MAC randomisation, and harmless kernel tuning. Same seed, same machine —
so a config is still auditable and diffable. Different seed, different
machine — so an attack that fits one host does not fit the next.

The seed is defence in depth, not a secret. If it leaks you lose a layer, not
the system. Keep it out of public repositories anyway.

### `sovereign.impermanence`

btrfs `@root` is rolled back to an empty subvolume in the initrd on every
boot. Only `/nix`, `/home` and the paths you list in `persistPaths` survive.
Malware persistence, stray config drift and forgotten debug edits die at the
next reboot.

Failures are loud: if the wipe cannot run, the machine says so on the console
and boots the old root rather than silently pretending.

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
    url = "path:./example-seed";
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

The seed is a flake input, so evaluation stays pure. The default points at
`example-seed/`, which holds the sentinel value `__example__`:

```nix
inputs.hostSeed = {
  url = "path:./example-seed";
  flake = false;
};
```

A real machine overrides it at rebuild time:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#example \
  --override-input hostSeed path:/persist/etc/sovereign/seed.d
```

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
