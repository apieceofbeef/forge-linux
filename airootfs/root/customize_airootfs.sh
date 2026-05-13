#!/usr/bin/env bash
#
# /root/customize_airootfs.sh
#
# Executed by mkarchiso inside the live root filesystem (via arch-chroot)
# after pacstrap has installed the package set listed in packages.x86_64.
#
# Everything here happens *at build time*, on the build host -- it shapes
# the image that will be booted by the user.  Keep the script idempotent:
# mkarchiso may re-enter this hook on incremental rebuilds.
#

set -euo pipefail

log() { printf '\033[1;33m[forge-customize]\033[0m %s\n' "$*"; }

##############################################################################
# 1. Locale, timezone, hostname
##############################################################################
log "Configuring locale, timezone, hostname"

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc --utc || true

sed -i 's/^#\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
printf 'KEYMAP=us\nFONT=ter-v18n\n' > /etc/vconsole.conf

printf 'forge\n' > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   forge.localdomain forge
EOF

##############################################################################
# 2. Default shell -> zsh (for root and for all newly-created users)
##############################################################################
log "Setting zsh as the default shell"

if [[ -x /usr/bin/zsh ]]; then
    chsh -s /usr/bin/zsh root
    sed -i 's|^SHELL=.*|SHELL=/usr/bin/zsh|' /etc/default/useradd 2>/dev/null || true
    if [[ -f /etc/default/useradd ]] && ! grep -q '^SHELL=' /etc/default/useradd; then
        printf 'SHELL=/usr/bin/zsh\n' >> /etc/default/useradd
    fi
else
    log "WARNING: /usr/bin/zsh is missing -- keeping bash as default shell"
fi

##############################################################################
# 3. Skeleton configs (Hyprland, Waybar, Helix, Zellij, Starship, Ghostty, zsh)
##############################################################################
log "Installing skeleton configs into /etc/skel and root's home"

# /etc/skel is populated from airootfs/etc/skel during mkarchiso's copy
# stage.  We mirror it into /root so the live "root" account benefits from
# the same defaults the first time it logs in.
if [[ -d /etc/skel ]]; then
    shopt -s dotglob nullglob
    for entry in /etc/skel/*; do
        name="$(basename "$entry")"
        # Don't clobber files explicitly placed under /root by airootfs/.
        if [[ ! -e "/root/$name" ]]; then
            cp -aT "$entry" "/root/$name"
        fi
    done
    shopt -u dotglob nullglob
    chown -R root:root /root
    chmod 0750 /root
fi

##############################################################################
# 4. Service enablement
##############################################################################
log "Enabling system services"

services=(
    NetworkManager.service
    systemd-resolved.service
    systemd-timesyncd.service
    docker.socket
    apparmor.service
    auditd.service
    fstrim.timer
    paccache.timer
    reflector.timer
    pkgfile-update.timer
    bluetooth.service
    iwd.service
)

for svc in "${services[@]}"; do
    if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
        systemctl enable "$svc" || log "WARNING: could not enable $svc"
    else
        log "Skipping $svc (unit not present in image)"
    fi
done

# Greeter (display manager) -- enabled only if greetd is installed.
if systemctl list-unit-files greetd.service >/dev/null 2>&1; then
    systemctl enable greetd.service || true
fi

# zram swap device.
if systemctl list-unit-files systemd-zram-setup@.service >/dev/null 2>&1; then
    systemctl enable systemd-zram-setup@zram0.service || true
fi

##############################################################################
# 5. AppArmor: load FORGE's default profile set in enforce mode
##############################################################################
log "Configuring AppArmor"

if [[ -d /etc/apparmor.d ]]; then
    # Make sure the kernel cmdline carries the LSM hint.  This file is read
    # by /etc/default/grub when mkinitcpio/grub-mkconfig runs at first boot.
    if [[ -f /etc/default/grub ]]; then
        if ! grep -q 'lsm=' /etc/default/grub; then
            sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"|GRUB_CMDLINE_LINUX_DEFAULT="\1 lsm=landlock,lockdown,yama,integrity,apparmor,bpf"|' /etc/default/grub
        fi
    fi
fi

##############################################################################
# 6. Docker: rootless-friendly defaults
##############################################################################
log "Writing /etc/docker/daemon.json"

install -d -m 0755 /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "journald",
  "log-opts": {
    "tag": "{{.Name}}/{{.ID}}"
  },
  "storage-driver": "overlay2",
  "default-address-pools": [
    { "base": "10.201.0.0/16", "size": 24 }
  ],
  "features": {
    "buildkit": true
  },
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false
}
EOF

# Pre-create the docker group so users added via wheel inherit it cleanly.
getent group docker >/dev/null 2>&1 || groupadd -r docker

##############################################################################
# 7. sudo / wheel
##############################################################################
log "Configuring sudoers"

install -d -m 0750 /etc/sudoers.d
cat > /etc/sudoers.d/10-forge-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
Defaults pwfeedback
Defaults env_keep += "EDITOR VISUAL PAGER LANG LC_ALL"
EOF
chmod 0440 /etc/sudoers.d/10-forge-wheel
visudo -cf /etc/sudoers >/dev/null

##############################################################################
# 8. Live user "forge" (used by the ISO's auto-login)
##############################################################################
log "Creating live user 'forge'"

if ! id -u forge >/dev/null 2>&1; then
    useradd -m -G wheel,docker,audio,video,input,storage,network -s /usr/bin/zsh forge
    # Password is "forge" -- documented in README; this is a live ISO.
    echo 'forge:forge' | chpasswd
fi
echo 'root:forge' | chpasswd

##############################################################################
# 9. Build yay (AUR helper) from source as the live user
##############################################################################
log "Building yay from AUR"

build_yay() {
    local builddir
    builddir="$(mktemp -d)"
    chown forge:forge "$builddir"
    sudo -u forge -H bash -euo pipefail -c "
        cd '$builddir'
        git clone --depth=1 https://aur.archlinux.org/yay-bin.git
        cd yay-bin
        makepkg -s --noconfirm --noprogressbar
    "
    pacman -U --noconfirm "$builddir"/yay-bin/yay-bin-*.pkg.tar.*
    rm -rf "$builddir"
}

if ! command -v yay >/dev/null 2>&1; then
    # Allow the build user to run pacman/sudo non-interactively just for
    # this step; the rule is removed immediately afterwards.
    cat > /etc/sudoers.d/99-forge-yay-build <<'EOF'
forge ALL=(ALL) NOPASSWD: /usr/bin/pacman
EOF
    chmod 0440 /etc/sudoers.d/99-forge-yay-build

    if build_yay; then
        log "yay installed successfully"
    else
        log "WARNING: yay build failed -- continuing without it"
    fi

    rm -f /etc/sudoers.d/99-forge-yay-build
fi

##############################################################################
# 10. fuse + forge-install: ensure FORGE's CLIs are executable
##############################################################################
# The actual scripts ship via airootfs/usr/local/bin/.  Here we only verify
# they are present and runnable; permissions are pinned via
# `file_permissions` in profiledef.sh.
log "Verifying /usr/local/bin/fuse and /usr/local/bin/forge-install"

for bin in /usr/local/bin/fuse /usr/local/bin/forge-install; do
    if [[ -f $bin ]]; then
        chmod 0755 "$bin"
        bash -n "$bin" || log "WARNING: $bin failed syntax check"
    else
        log "WARNING: $bin missing (was it copied from airootfs/usr/local/bin?)"
    fi
done

install -d -m 0755 /var/cache/forge/snapshots /var/log/forge

##############################################################################
# 11. mkinitcpio: rebuild for the linux-zen kernel
##############################################################################
log "Regenerating initramfs"

if [[ -f /etc/mkinitcpio.conf ]]; then
    # Use systemd-based hooks for faster, more reliable boot.
    sed -i 's|^HOOKS=.*|HOOKS=(base systemd autodetect modconf kms keyboard sd-vconsole block filesystems fsck)|' /etc/mkinitcpio.conf
fi

if pacman -Qi linux-zen >/dev/null 2>&1; then
    mkinitcpio -P
fi

##############################################################################
# 12. Cleanup
##############################################################################
log "Pruning caches"

pacman -Scc --noconfirm || true
rm -rf /var/cache/pacman/pkg/* /tmp/* /root/.cache /home/forge/.cache 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} + 2>/dev/null || true

##############################################################################
# 13. Branding: /etc/issue + ensure fastfetch config is in place
##############################################################################
if [[ -f /etc/forge/logo.txt ]]; then
    log "FORGE branding assets present"
fi

log "customize_airootfs.sh complete"
