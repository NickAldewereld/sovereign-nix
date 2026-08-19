# AGENTS.md

The README describes what the modules do. This file describes the decisions:
what was claimed and withdrawn, what must keep failing, and which mistakes
have already been made here so they are not made again.

## The one rule

**A claim without a test is not shipped, and a test without a stated limit is
not finished.** Every row of the claims table in the README points at a check
in `checks/`. When you change a module or a check, walk that table. It has
drifted twice already: prose that was true when written and quietly stopped
being true is the most common defect in this repository, more common than
broken code.

If a measurement contradicts something in the README, the README loses. Say so
in the commit, in public, and keep the correction in the file.

## Claims that were withdrawn. Do not put them back.

- **"Every machine unique" / "different seed, different machine."** False. The
  derived values live in a small space (40000 ports, 41 swappiness values,
  6145 somaxconn values); two hosts share an SSH port with 50% probability at
  around 235 machines, and full collisions exist. A colliding pair is pinned in
  `checks/diversity-lib.nix`. Same seed gives the same values; the converse
  does not hold.
- **"An attack that fits one host does not fit the next."** False. Kernel, libc
  and every binary are identical across hosts. Nothing here stops a working
  exploit. What changes is the cost of untargeted, automated attacks.
- **MAC randomisation as a hardening measure.** It is privacy, and it is not
  derived from the seed at all: NetworkManager generates a fresh address per
  connection. It is the one value in that module that is deliberately not
  reproducible.
- **"Reserving the port stops the sshd port being taken."** It stops automatic
  allocation, not an explicit bind. An ESTABLISHED outbound connection does
  *not* block sshd from restarting, because sshd sets `SO_REUSEADDR`. What
  closes the window is socket activation, which `harden` switches on.
- **"dns0.eu did not answer from a major Dutch ISP."** The service is gone. A
  dead endpoint was read as a network problem, in the section of the README
  that exists to prevent exactly that.

## Guards that must keep stopping evaluation

Three configurations must fail to *evaluate*, never merely warn. Evaluation is
the only point that also stops `nixos-rebuild boot`; an activation script does
not, and by the time one runs, `/etc/ssh/sshd_config` has been rewritten.

| Guard | Stops | Way past |
|---|---|---|
| `checks/seed-guard.nix` | the sentinel seed reaching a machine | `allowExampleSeed` |
| `checks/lockout-guard.nix` | hardened sshd with nobody able to log in | a user with a key or a password, or `harden.ssh = false` |
| `checks/config-guard.nix` | a machine that wipes its own `/etc/nixos` | `allowEphemeralConfig` |

The lockout guard is deliberately loose in one place: with `users.mutableUsers`
on, any normal user clears it, because a password may have been set with
`passwd` and this module cannot know. Do not tighten that without a way out; a
guard that is too strict gets switched off entirely.

## Tests may not pass by accident

- `checks/mutation.nix` breaks every value in `lib/harden-policy.nix` on
  purpose and requires the comparison to notice. Add a hardening value to the
  policy and the mutation check covers it automatically.
- Every grep-based check carries a **positive control**: it must match a
  planted sample before it scans for real. A grep that matches nothing looks
  exactly like a grep that works.
- `lib/harden-policy.nix` is the single source for the module *and* the checks,
  so a prose summary cannot drift from what is applied. Do not restate the
  values in the README; link the file.

## Executable limits

`checks/limits.nix`, the collision assertion in `checks/diversity-lib.nix`, and
the `@home` assertion in `checks/impermanence.nix` assert that the **bad thing
still happens**. If one of them fails, a limit has become obsolete and the
README is wrong. Fix the README. Do not "repair" the test.

## Consumability

This is a module library. It has twice shipped something no outsider could
use, and `nix flake check` cannot see either failure, because it only ever
evaluates this flake as the root.

- **No relative `path:` inputs.** Nix refuses to read the whole lock file of a
  dependency that has one, so every consumer fails before evaluation starts.
  `checks/consumable.nix` fails the build if one returns.
- **Everything in `modules/` and `profiles/` must be a flake output.**
  `profiles/laptop.nix` was used by the example host for months while being
  unreachable to anyone else. `checks/default-module.nix` asserts the output
  names.
- Before publishing anything a reader is meant to run, run it. The install
  script, the "Use it" snippet and the flake input were all broken in ways that
  only appeared on a machine that was not the author's.

## Traps already paid for

- **`/boot` must be its own partition.** Inside `@root` the wipe deletes GRUB's
  modules: the machine installs, boots once, and lands in a rescue prompt.
- **`/etc/nixos` must be persisted**, or the machine cannot rebuild itself.
- **Reinstalling over an impermanent root** fails in the bootloader installer
  on the empty `/etc/machine-id` placeholder the wipe leaves behind. Copy the
  real one from `/persist` first.
- **`sshd -T` refuses to run without a host key**, and with socket activation
  the real keys appear on first connection. Hand it a throwaway.
- **`openssh.authorizedKeys.keyFiles` is read at evaluation time**, so an
  absolute path breaks pure evaluation. Use `keys` in checks.
- **No key-shaped or address-shaped literals anywhere in the tree.**
  `checks/no-personal-data.nix` scans for the shapes, and it excludes only
  itself.

## Working with reviewers

Outside review has outperformed the test suite three times. When someone
reports something: reproduce it first, on a machine, before agreeing or
disagreeing. Two of the reported problems turned out to be real with the wrong
consequence attached, and one of the author's own corrections was itself wrong
until it was measured. Credit reviewers by name in the README and in the commit
message.
