# The throwaway VM

`nix flake check` proves most of the claims in a VM it builds and discards.
Two things it cannot show you are a real boot cycle and a machine you can log
into and poke at. This host is that machine, and it is a file rather than a
favour: nobody has to give you access to theirs.

It runs all four modules on plain btrfs. **Treat it as public.** The seed is
published in `default.nix`, so the SSH port is 43581 for everyone, and the
console password is in the same file. That is fine for a machine you are going
to delete and wrong for anything else.

## Boot it

Any hypervisor will do; this is plain QEMU, no firmware flags needed.

```bash
qemu-img create -f qcow2 disk.qcow2 20G
qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
  -drive file=disk.qcow2,if=virtio \
  -cdrom nixos-minimal-25.11-x86_64-linux.iso \
  -boot d -nic user,hostfwd=tcp::4322-:43581
```

In the installer:

```bash
curl -O https://raw.githubusercontent.com/NickAldewereld/sovereign-nix/master/hosts/vm/install.sh
sudo bash install.sh /dev/vda
```

Then remove `-cdrom` and `-boot d`, and boot from the disk.

## Check the claims yourself

Log in on the console as `demo` / `sovereign`. SSH will answer on 43581 but
will not let you in: `harden` accepts keys only, and this host ships with
none. Add your own to `hosts/vm/default.nix` if you want a shell over the
network. The console is the way in by default, which is the point of the
`hostfwd` line above being only enough to see that the port answers.

```bash
# the derived port, and 22 closed
ss -tln | grep 43581
ss -tln | grep ':22 ' || echo "22 is closed"

# the port is reserved, so the kernel never hands it out as a source port
cat /proc/sys/net/ipv4/ip_local_reserved_ports

# PID 1 owns the socket, sshd itself is idle until someone connects
systemctl status sshd.socket

# hardening, as sshd resolved it rather than as the file spells it
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication'
sudo sysctl kernel.kptr_restrict kernel.yama.ptrace_scope
```

The interesting one, because no test in this repository can do it:

```bash
sudo touch /this-should-not-survive
touch ~/this-should-survive
sudo reboot
# after the reboot
ls /this-should-not-survive          # gone
ls ~/this-should-survive             # still there, and that is a documented limit
sudo mount -o subvol=@root_prev,ro /dev/disk/by-label/sovereign /mnt
ls /mnt/this-should-not-survive      # the previous root, kept for one boot
```

## Things worth trying to break

The README states limits rather than hiding them, and the fastest way to find
the next mistake is to attack the claims rather than the code:

- Two different seeds already produce identical machines. Look for a pair that
  collides on more than the three derived values.
- `/home` survives the wipe, so user-level persistence does. What else
  survives that the README does not mention?
- The lockout guard, the seed guard and the config guard all stop evaluation.
  Find a configuration that gets past one of them and still ends up
  unreachable, unseeded or unrebuildable.

If you find something, an issue with the reproduction is worth more than a
patch.
