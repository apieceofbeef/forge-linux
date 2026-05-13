<div align="center">

# FORGE Linux

**A developer-focused Linux distribution — Arch base, `linux-zen` kernel, Hyprland desktop, a unified `fuse` package manager, and a one-command build pipeline.**

[![CI](https://github.com/apieceofbeef/forge-linux/actions/workflows/build-iso.yml/badge.svg)](https://github.com/apieceofbeef/forge-linux/actions/workflows/build-iso.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-f59e0b.svg)](LICENSE)

</div>

---

## What is FORGE?

FORGE is an **opinionated** Arch Linux derivative shipped as a `.iso`. The
repository **is** the archiso build profile — there's no separate build
system, no out-of-tree patches. `mkarchiso` runs over `profiledef.sh` and
emits `out/forge-linux-YYYY.MM.DD-x86_64.iso`.

It's aimed squarely at developers who want to skip the "spend three
weekends configuring Arch + Hyprland" step and start writing code.

### Headline features

| Layer | What you get |
|---|---|
| **Kernel** | `linux-zen` with `apparmor=1 security=apparmor zswap.enabled=0 mitigations=auto nowatchdog`, fast initramfs (`systemd` hooks + `zstd`), pre-loaded `amdgpu`/`i915`/`nvidia` modules |
| **Memory** | `zram0` (lz4, 50 % of RAM, priority 100) + curated `sysctl.d/99-forge.conf` (swappiness 10, BBR + cake qdisc, inotify watches 1 Mi, full hardening + scheduler tuning) |
| **Package manager** | `fuse` — one CLI over `pacman` + `yay` + `flatpak` + `mise`. Auto-snapshots before upgrades, locked operations, millisecond-timed, logged to `/var/log/forge/fuse.log` |
| **Updates** | `forge-update` orchestrates reflector → snapshot → pacman → AUR → flatpak → mise with a clean diff and orphan check |
| **Desktop** | Hyprland (Wayland) + Waybar + Dunst + Rofi + Wlogout + hyprlock/hypridle/hyprpaper, all pre-themed in the FORGE palette |
| **Shell** | zsh + Starship + zoxide + mise + fzf with `eza`/`bat`/`rg`/`fd`/`btop`/`hx` aliases and a `new-project` scaffolder |
| **Login** | `greetd` + `tuigreet` on the installed system; passwordless tty1 autologin on the live ISO |
| **Security** | AppArmor profiles for Firefox and `fuse`, `ufw`, `clamav`, `pam-u2f`, `auditd` |
| **Installer** | `forge-install` — interactive bash installer (btrfs subvolumes or ext4, UEFI or BIOS, snapper integration) |
| **CI** | GitHub Actions builds the ISO in an `archlinux:latest` container on every push and uploads it as an artifact |

### Branding palette

| Token | Hex | Use |
|---|---|---|
| `bg`     | `#0d0e10` | Window backgrounds |
| `bg-alt` | `#111318` | Module backgrounds |
| `fg`     | `#e8e6df` | Foreground text |
| `muted`  | `#94a3b8` | Secondary text, borders |
| `amber`  | `#f59e0b` | Primary accent (active, selected) |
| `green`  | `#22c55e` | Success, OK |
| `red`    | `#ef4444` | Errors, critical |

---

## Prerequisites

| Build path | What you need |
|---|---|
| **Local (Arch host)** | An Arch (or Arch-derived) Linux machine with `sudo`, ~8 GiB free disk under `./work` and ~2 GiB under `./out`. `make deps` will install the toolchain. |
| **GitHub Actions** | Just `git push` — the workflow runs `mkarchiso` inside `archlinux:latest` and uploads the ISO + SHA-256 as a 7-day artifact. |
| **QEMU smoke test** | `qemu-system-x86_64`, `edk2-ovmf`, `/dev/kvm` (optional, falls back to TCG). |

The build doesn't work on non-Arch hosts directly — `mkarchiso` and
`pacstrap` are Arch-specific. Use the CI workflow or an Arch container if
you don't have an Arch host handy.

---

## Quick start

```bash
git clone https://github.com/apieceofbeef/forge-linux.git
cd forge-linux
make all          # installs deps, builds the ISO, boots it in QEMU
```

That's the entire happy path. Output lands at
`out/forge-linux-YYYY.MM.DD-x86_64.iso` and a GTK QEMU window opens so you
can poke at the live system.

### Step-by-step (if you don't want `make all`)

```bash
# 1. Install build/test deps
make deps

# 2. Build the ISO
make build          # == sudo ./build.sh --clean --verbose

# 3. Hash it
make sha            # prints SHA-256 of out/forge-linux-*.iso

# 4. Smoke-test in QEMU
make smoke          # headless, prints PASS/FAIL + boot time
make test           # GTK window, manual click-around

# 5. Iterate
make fast           # incremental build (no --clean)
make clean          # remove work/ and out/
```

### Manual build (no Makefile)

```bash
sudo pacman -S --needed archiso arch-install-scripts squashfs-tools \
    libisoburn dosfstools mtools grub edk2-shell \
    qemu-base qemu-system-x86 edk2-ovmf
sudo ./build.sh --clean --verbose
```

`build.sh` understands `--clean`, `--verbose`, `-o OUTDIR`, `-w WORKDIR`,
and verifies host dependencies + `profiledef.sh` syntax before invoking
`mkarchiso`.

---

## Booting the ISO

### QEMU — UEFI (recommended)

```bash
# Headless boot benchmark, prints PASS + boot time
test/smoke-test.sh --iso out/forge-linux-*.iso

# Interactive GTK window
test/smoke-test.sh --gui --iso out/forge-linux-*.iso

# BIOS path
test/smoke-test.sh --bios --gui --iso out/forge-linux-*.iso
```

Internally:

```bash
cp /usr/share/edk2-ovmf/x64/OVMF_VARS.fd /tmp/forge_VARS.fd
qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4G \
    -machine q35,smm=on,accel=kvm:tcg \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    -drive if=pflash,format=raw,file=/tmp/forge_VARS.fd \
    -drive file=out/forge-linux-*.iso,media=cdrom,readonly=on \
    -boot d -device virtio-net-pci,netdev=net0 -netdev user,id=net0 \
    -device virtio-vga-gl -display gtk,gl=on
```

### QEMU — BIOS

Drop both `-drive if=pflash,...` lines from the command above. The live
ISO ships both UEFI (GRUB) and BIOS (syslinux) boot paths.

### Real hardware (USB)

```bash
# Find the device
lsblk -d -e 7,11

# Flash (replace /dev/sdX with your USB device)
sudo dd if=out/forge-linux-*.iso of=/dev/sdX \
    bs=4M conv=fsync status=progress oflag=direct
```

The ISO is hybrid (BIOS + UEFI) and will boot on either firmware mode.

### Live credentials

The live ISO autologs **root** into tty1 and immediately launches
Hyprland. There's also a `forge` user with password `forge` and the root
password is `forge` — these are documented intentional weaknesses for the
live image only. The installer (`forge-install`) will prompt you to set
proper credentials for the installed system.

---

## First steps after install

```bash
# Update the system using the FORGE pipeline (reflector → snapshot → all package managers → diff)
fuse update

# Install a Node toolchain via mise (the per-user runtime manager)
mise use --global node@lts

# Scaffold a new project in the current directory
new-project rust   my-cli
new-project node   my-web
new-project go     my-api
new-project python my-lib

# Roll back if an update breaks something
fuse snapshot list
fuse rollback pre-update-2025-05-13_14-22-07
```

`fastfetch` runs on the first interactive zsh shell of each TTY, giving
you a quick system overview.

---

## `fuse` command reference

`fuse` is the single entry point for all package-management operations.
Every command is timed in milliseconds and logged to
`/var/log/forge/fuse.log`. Operations that mutate state acquire a lock at
`/run/forge-fuse.lock`.

| Command | What it does |
|---|---|
| `fuse install PKG ...`           | Resolves to `pacman` for official packages, `yay` for AUR |
| `fuse remove PKG ...`            | `pacman -Rns` then drops orphans |
| `fuse search QUERY`              | Combined `pacman -Ss` + `yay -Ss` results |
| `fuse info PKG`                  | `pacman -Si`/`-Qi` with a fallback to AUR metadata |
| `fuse list [--explicit]`         | `pacman -Q[e]` |
| `fuse update [...]`              | Auto-snapshots, then delegates to `forge-update` |
| `fuse upgrade [...]`             | Alias for `update` |
| `fuse clean`                     | Orphan removal + `paccache -r` |
| `fuse snapshot create [NAME]`    | Zstd-tarballs `pacman -Qqe`, `-Qqm`, `/etc` to `/var/cache/forge/snapshots/` |
| `fuse snapshot list`             | Tabular list of available snapshots with size + timestamp |
| `fuse snapshot rm NAME`          | Delete a snapshot |
| `fuse rollback NAME`             | Reinstall the exact package set and `/etc` from a snapshot |
| `fuse runtime use LANG@VER`      | Delegates to `mise use --global` |
| `fuse status`                    | One-shot system overview (kernel/CPU/RAM/disk/uptime/pkg counts) |
| `fuse why PKG`                   | `pactree -r` reverse dependency graph |
| `fuse help` / `fuse version`     | Help and version banner |

### `forge-update` flags

```
forge-update [--country COUNTRY] [--top N]
             [--dry-run]
             [--skip-aur] [--skip-flatpak] [--skip-mise]
```

- `--country` picks reflector mirrors from a specific country
- `--top` picks the fastest N mirrors (default 10)
- `--dry-run` prints what would be done without touching anything
- `--skip-*` disables the corresponding stage

---

## Hyprland keybindings cheatsheet

`SUPER` is the modifier (Mod4 / "Windows" key). Full list lives in
`airootfs/etc/skel/.config/hypr/hyprland.conf`.

| Action | Binding |
|---|---|
| Launch terminal (ghostty)         | `SUPER` + `Return` |
| App launcher (rofi)               | `SUPER` + `Space` |
| Close active window               | `SUPER` + `Q` |
| Toggle floating                   | `SUPER` + `V` |
| Fullscreen                        | `SUPER` + `F` |
| Toggle split direction            | `SUPER` + `J` |
| Pseudo-tile                       | `SUPER` + `P` |
| Lock screen (hyprlock)            | `SUPER` + `L` |
| Power menu (wlogout)              | `SUPER` + `Escape` |
| Move focus                        | `SUPER` + `H`/`J`/`K`/`L` |
| Move window                       | `SUPER` + `Shift` + `H`/`J`/`K`/`L` |
| Resize window                     | `SUPER` + `Ctrl`  + `H`/`J`/`K`/`L` |
| Workspace 1–10                    | `SUPER` + `1` ... `0` |
| Send window to workspace          | `SUPER` + `Shift` + `1` ... `0` |
| Cycle workspaces                  | `SUPER` + `Mouse wheel` |
| Screenshot region → clipboard     | `SUPER` + `Shift` + `S` |
| Screenshot region → edit (swappy) | `SUPER` + `Shift` + `Print` |
| Toggle scratchpad                 | `SUPER` + `Grave` |
| Reload Hyprland                   | `SUPER` + `Shift` + `R` |
| Volume / brightness               | XF86 media keys |

`Caps Lock` is remapped to `Escape` system-wide (vim/helix-friendly).

---

## Repository layout

```
forge-linux/
├── profiledef.sh                          # archiso profile metadata
├── packages.x86_64                        # package list pacstrap'd into airootfs
├── pacman.conf                            # pacman.conf used at build time
├── build.sh                               # host-side wrapper around mkarchiso
├── Makefile                               # one-command pipeline
├── LICENSE                                # MIT
├── README.md                              # this file
│
├── airootfs/                              # → / on the live ISO
│   ├── etc/
│   │   ├── apparmor.d/                    # Firefox + fuse profiles
│   │   ├── forge/                         # logo.txt + fastfetch.jsonc
│   │   ├── greetd/config.toml             # tuigreet config
│   │   ├── issue                          # TTY banner
│   │   ├── mkinitcpio.conf                # systemd hooks + zstd
│   │   ├── os-release                     # ID=forge, ID_LIKE=arch
│   │   ├── skel/                          # default user dotfiles
│   │   │   ├── .zshrc
│   │   │   └── .config/
│   │   │       ├── dunst/dunstrc
│   │   │       ├── ghostty/config
│   │   │       ├── helix/{config.toml,themes/forge.toml}
│   │   │       ├── hypr/{hyprland,hyprlock,hypridle,hyprpaper}.conf
│   │   │       ├── hypr/wallpaper.png       (generated by tools/gen-wallpaper.py)
│   │   │       ├── rofi/{config,forge}.rasi
│   │   │       ├── starship.toml
│   │   │       ├── waybar/{config.jsonc,style.css}
│   │   │       ├── wlogout/{layout,style.css}
│   │   │       └── zellij/config.kdl
│   │   ├── sysctl.d/99-forge.conf
│   │   ├── systemd/
│   │   │   ├── system/getty@tty1.service.d/autologin.conf
│   │   │   └── zram-generator.conf
│   │   └── (more)
│   ├── boot/grub/themes/forge/theme.txt   # GRUB theme for installed system
│   ├── root/
│   │   ├── customize_airootfs.sh          # post-pacstrap hooks
│   │   ├── .zlogin                        # autologin → Hyprland on tty1
│   │   └── .zshrc                         # sources /etc/skel/.zshrc
│   └── usr/local/bin/
│       ├── fuse                           # the unified package manager
│       ├── forge-update                   # update orchestrator
│       └── forge-install                  # interactive installer
│
├── grub/                                  # GRUB config + theme for the live ISO
├── syslinux/                              # BIOS bootloader config
├── efiboot/                               # systemd-boot config for UEFI live boot
│
├── test/smoke-test.sh                     # QEMU smoke test (boot benchmark / GUI)
├── tools/gen-wallpaper.py                 # generates the dark dot-grid wallpaper
└── .github/workflows/build-iso.yml        # CI: build ISO + lint on push/PR
```

---

## Contributing

1. **Fork and branch.** Trunk is `main`; PRs target `main`.
2. **Run lint locally:** `make lint` (bash + TOML).
3. **Open a PR.** CI will build the ISO in a container and upload it as an
   artifact you can download and boot.
4. **Discuss changes** that touch `packages.x86_64`, `customize_airootfs.sh`,
   or kernel cmdline in an issue first — these have wide blast radius.

### What still needs work

- The two optional binary assets that the desktop references but tolerates
  missing: `airootfs/boot/grub/themes/forge/{background.png,logo.png}` and
  a `.pf2` font for GRUB. The configs cope gracefully when these are
  absent.
- AppArmor profiles ship in `complain` mode. Flip them to `enforce` after
  validating against real-world workflows.
- The `# VERIFY` comments in `packages.x86_64` mark packages whose Arch
  repo location has shifted in the past — confirm they're still in
  `[extra]` before each release.

---

## License

[MIT](LICENSE) — see the LICENSE file. Third-party packages bundled into
the ISO retain their respective upstream licenses; FORGE Linux only
licenses the build profile itself.
