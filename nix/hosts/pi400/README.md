# `pi400` — NixOS host on a Raspberry Pi 400

A declaratively-managed NixOS server running on a Raspberry Pi 400, deployed from this flake. The Pi sits on the LAN + Tailscale tailnet and runs:

- **Obsidian Sync** (`obsidian-sync.service`) — official headless `ob` daemon mirroring the vault at `/home/nelson/obsidian`
- **vault-mcp** (`vault-mcp.service`) — local-only Streamable HTTP MCP server (loopback :8787) exposing Obsidian vault tools to `claude-code` on the Pi
- **Tailscale** with `--ssh --accept-routes` — joins the tailnet at first boot via a sops-encrypted auth key
- **NetworkManager** with declarative WiFi profiles (PSKs encrypted in repo)
- **OpenSSH** (keys only)

## Hardware

| | |
|---|---|
| SoC | BCM2711 (Pi 4 / 400) — 4-core Cortex-A72 @ 1.8 GHz |
| RAM | 4 GB LPDDR4 |
| Boot | microSD card, extlinux-compatible bootloader |
| Networking | gigabit ethernet + onboard BCM43455 WiFi |

The Pi 400's only meaningful hardware difference from a Pi 4B is form factor and stock clock; nothing here is Pi-400-specific.

## File map

```
nix/hosts/pi400/
├── default.nix     ← Pi-specific NixOS module (services, packages, users, sops wiring)
├── hardware.nix    ← bootloader + filesystem config (rarely changes)
└── README.md       ← this file

nix/secrets/
└── pi400.yaml      ← sops-encrypted secrets (tailscale authkey, WiFi PSKs)

.sops.yaml          ← (repo root) age recipients + creation rules
```

## Architecture: how the pieces fit

```
        ┌──────────────────────────────────────────────┐
        │                this flake                    │
        │  flake.nix → nixosConfigurations.pi400       │
        │  ├─ nixos-hardware/raspberry-pi-4 module     │
        │  ├─ sops-nix module                          │
        │  ├─ vault-mcp-src (source-only input)        │
        │  │   → callPackage'd in default.nix          │
        │  │     to produce aarch64-linux closure      │
        │  └─ flake.lock pins everything               │
        └──────────────────┬───────────────────────────┘
                           │
                  nixos-rebuild
                  --target-host nelson@pi400
                           │
                           ▼
        ┌──────────────────────────────────────────────┐
        │                 the Pi                       │
        │                                              │
        │  /run/secrets/                               │
        │  ├─ tailscale-authkey   (0400 root, ramfs)   │
        │  └─ wifi-env            (0400 root, ramfs)   │
        │   ▲                                          │
        │   │ decrypted by sops-nix at activation,     │
        │   │ using /etc/ssh/ssh_host_ed25519_key      │
        │   │                                          │
        │  systemd:                                    │
        │  ├─ sshd                    (key-only)         │
        │  ├─ tailscaled              (reads authkey)    │
        │  ├─ NetworkManager          (reads wifi-env)   │
        │  ├─ obsidian-sync           (ob sync --continuous) │
        │  └─ vault-mcp               (127.0.0.1:8787)   │
        │                                              │
        │  /home/nelson/obsidian    (vault, synced)    │
        └──────────────────────────────────────────────┘
```

The encryption identity is the Pi's SSH host key — **no second secret-management plane**. The same key sshd already uses for host authentication doubles as the sops decryption identity (`sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]`). Re-flashing rotates this key, which is why step 4 of the reflash recipe below updates `.sops.yaml`.

## Building from the Mac (no Nix on the Mac)

There is no Nix toolchain installed on the Mac. Instead, a NixOS aarch64 VM running under UTM (`Linux` VM, `192.168.64.10`) acts as the remote builder. The workflow is always:

```sh
# 1. push the current flake to the VM
rsync -av --exclude '.git' ~/repos/dotfiles/nix/ root@192.168.64.10:/root/nix-config/

# 2. build + switch on the Pi via the VM
ssh root@192.168.64.10 \
  'cd /root/nix-config && nixos-rebuild switch \
     --flake .#pi400 \
     --target-host nelson@pi400 \
     --use-remote-sudo'

# 3. pull back the updated flake.lock (only needed when inputs changed)
scp root@192.168.64.10:/root/nix-config/flake.lock ~/repos/dotfiles/nix/flake.lock
```

If the VM is stopped, start it with `utmctl start <UUID>` (UUID `0AC1C031-2E24-4289-97E3-9F3DD7618D26`). The VM has 64 GB disk (large enough for the vendor RPi kernel compile, which the cache misses) and 16 GB RAM. See "VM provisioning" below if it ever needs to be rebuilt.

## Daily operations

### Add a new package, change a service

Edit `default.nix`. Push + rebuild as above. The closure builds on the VM, gets copied to the Pi, and activates.

### Add/rotate a secret

```sh
cd ~/repos/dotfiles
sops nix/secrets/pi400.yaml   # opens $EDITOR with decrypted plaintext
# save + exit → file re-encrypts automatically
```

`sops` finds the policy via `.sops.yaml` at the repo root; uses the age identity at `~/.config/sops/age/keys.txt` (derived from `~/.ssh/id_ed25519` via `ssh-to-age -private-key`).

### Add a new WiFi network

1. `sops nix/secrets/pi400.yaml` — add a new line to `wifi-env`, e.g. `WIFI_CAFE_PSK=...`
2. Edit `default.nix` — add a profile under `networking.networkmanager.ensureProfiles.profiles`, referencing `$WIFI_CAFE_PSK`
3. Rebuild as above

### Read the current secrets from the Pi (debug)

```sh
ssh nelson@pi400 'sudo cat /run/secrets/tailscale-authkey'
ssh nelson@pi400 'sudo cat /run/secrets/wifi-env'
```

`/run/secrets/` is a tmpfs that only exists while the system is booted; the plaintext never lands on disk.

### Free up SD card space

```sh
ssh nelson@pi400 'sudo nix-collect-garbage -d'
```

### Check service health

```sh
ssh nelson@pi400 'systemctl status sshd tailscaled NetworkManager obsidian-sync vault-mcp'
ssh nelson@pi400 'curl -s http://127.0.0.1:8787/health'   # vault-mcp
```

## Reflash recipe (the "reflash math")

The minimum manual steps to go from a fresh microSD to a fully-configured Pi:

1. **Flash the SD card** — download the current NixOS aarch64 SD image from Hydra (`https://hydra.nixos.org/job/nixos/release-<ver>/nixos.sd_image.aarch64-linux/latest/download/1`), decompress, `dd` to `/dev/rdiskN`. Image is ~1.4 GB compressed, ~4 GB raw.

2. **First boot** — insert SD, plug in monitor + ethernet, power on. At the console, log in as `nixos` (no password). Set a temporary password: `sudo passwd nixos`. Find the LAN IP: `ip -4 addr show end0`.

3. **Copy your SSH key in:** from the Mac, `ssh-copy-id nixos@<ip>`.

4. **Re-key sops for the new host** — the Pi just generated a fresh ed25519 host key. Convert to an age recipient and update the repo:
   ```sh
   ssh nixos@<ip> 'cat /etc/ssh/ssh_host_ed25519_key.pub' | ssh-to-age
   # → age1...newpi...
   ```
   Edit `.sops.yaml`: replace the **age public key value** on the `&pi400` line with the new recipient. Keep the `&pi400` anchor label itself — it's referenced by `*pi400` in `creation_rules`. Then:
   ```sh
   cd ~/repos/dotfiles
   sops updatekeys nix/secrets/pi400.yaml
   git add .sops.yaml nix/secrets/pi400.yaml
   git commit -m "chore(sops): rekey pi400 after reflash"
   ```

5. **First switch** — push + rebuild as in "Building from the Mac" above. After this, the Pi has the `nelson` user, all services, and the new closure as boot default. `nixos` user stays around as a fallback.

6. **One-time `ob login`** — Obsidian Sync requires interactive auth (email/password/MFA). On the Pi:
   ```sh
   ssh nelson@pi400
   ob login                                                   # interactive
   ob sync-list-remote                                        # prints vault name(s)
   cd ~/obsidian && ob sync-setup --vault "<name>" --device-name pi400
   sudo systemctl restart obsidian-sync
   ```
   `<name>` is whichever vault you have under Obsidian Sync — currently `obsidian`, but `sync-list-remote` is the authoritative answer at the time of reflash.

That's everything that can't be pulled from the flake. The Tailscale authkey, WiFi PSKs, user account, package set, service configs all flow from the repo.

## Outstanding imperative bits

These pieces don't live in the flake yet:

- **`obsidian-headless` (`ob`)** — installed via `npm install -g obsidian-headless` under `nelson`. Blocked on upstream's pnpm-lock incompatibility with `buildNpmPackage`. The fallback documented in [vault-mcp's repo](https://github.com/nelsonlove/obsidian-vault-mcp-server) is to keep this imperative with a version pin.
- **Obsidian Sync auth state** at `~/.config/obsidian-headless/` — interactive 2FA login, by design.
- **The Pi's SSH host ed25519 key** — generated by sshd on first boot. Doubles as the sops decryption identity, so it's load-bearing (re-flashing means re-keying sops; see step 4 above).

## Architecture decisions, briefly

- **Why a Pi 400, not a Pi 4B or a cloud VM?** I wanted a desktop-resident NixOS box for the vault-side tooling without paying for hosting. The Pi 400's keyboard form factor was incidental; it's the cheapest 4 GB Pi 4 variant on hand.
- **Why NixOS, not Raspberry Pi OS?** Declarative reproducibility. The Pi-OS-with-Nix path (Nix as a package manager on top of Raspbian) was considered but rejected — I wanted the OS itself in the flake.
- **Why a builder VM, not native Mac builds?** No Nix on the Mac; setting up `nix-darwin` + `linux-builder` was a deferred decision unrelated to the Pi. The UTM aarch64 NixOS VM (which already existed) is a fine substitute.
- **Why the vendor RPi kernel?** Better support for hardware features (HW video decode, vc4 GPU, future HAT support). Not strictly required for this Pi's workload but doesn't cost anything to run — only costs *building* it from source when nixpkgs's unstable channel drifts ahead of the binary cache.
- **Why local-only vault-mcp?** This Pi runs `claude-code` for itself; it doesn't need to be a public MCP endpoint. The same vault-mcp repo IS deployed as a publicly-reachable endpoint elsewhere (`obsidian.nelson.love`) for Claude.ai connector use; the Pi just consumes the *same codebase* locally over loopback to avoid Anthropic-cloud round-trips.
- **Why sops-nix over agenix?** Both work; sops-nix has slightly broader tooling (sops CLI works on YAML/JSON/ENV natively, not just blob files) and Mic92's sshKeyPath integration means the Pi's host SSH key doubles as the age identity with zero ceremony.
- **Why a worktree-per-PR development style?** Multi-file changes that span weeks risk colliding with concurrent work. Worktrees + per-PR review let each change land atomically without disturbing the main checkout.

## VM provisioning (if the builder VM ever needs rebuilding)

The UTM `Linux` VM is a NixOS 24.11 aarch64 install with Apple Virtualization backend, 8 cores, 16 GB RAM, 64 GB disk (originally 20 GB, expanded via `truncate -s 64G` + `sfdisk -N 2 + resize2fs` because the vendor RPi kernel compile needs ~10 GB scratch). nix-conf has flakes enabled.

The flake is sync'd to `/root/nix-config/` via rsync from the Mac when needed. The VM has SSH access to the Pi using a generated key (`/root/.ssh/id_ed25519` → added to `nelson@pi400:~/.ssh/authorized_keys` once).

## See also

- [vault-mcp upstream repo](https://github.com/nelsonlove/obsidian-vault-mcp-server) — TypeScript source + the `nix/pkgs/vault-mcp.nix` derivation this flake pulls in
- `nix/secrets/pi400.yaml` — encrypted secrets, edit with `sops`
- `.sops.yaml` at repo root — age recipients + creation rules
