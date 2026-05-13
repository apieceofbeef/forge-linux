#!/usr/bin/env bash
# shellcheck disable=SC2034

# archiso profile definition for FORGE Linux.
# Reference: /usr/share/archiso/configs/releng/profiledef.sh

iso_name="forge-linux"
iso_label="FORGE_$(date --utc +%Y%m)"
iso_publisher="FORGE Linux <https://forgelinux.org>"
iso_application="FORGE Linux Live/Install ISO"
iso_version="$(date --utc +%Y.%m.%d)"
install_dir="forge"
buildmodes=('iso')
bootmodes=(
    'bios.syslinux.mbr'
    'bios.syslinux.eltorito'
    'uefi-ia32.grub.esp'
    'uefi-x64.grub.esp'
    'uefi-ia32.grub.eltorito'
    'uefi-x64.grub.eltorito'
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=(
    '-comp' 'zstd'
    '-Xcompression-level' '22'
    '-b' '1M'
)
# NOTE: -Xbcj is an XZ-only filter; mksquashfs rejects it when -comp is
# zstd.  If you switch back to xz, restore -Xbcj x86 to recover ~5-10%
# additional compression on i386 instruction streams.
bootstrap_tarball_compression=(zstd -c -T0 --auto-threads=logical --long -19)

declare -A file_permissions=(
    ["/etc/shadow"]="0:0:0400"
    ["/etc/gshadow"]="0:0:0400"
    ["/root"]="0:0:0750"
    ["/root/.automated_script.sh"]="0:0:0755"
    ["/root/.gnupg"]="0:0:0700"
    ["/root/customize_airootfs.sh"]="0:0:0755"
    ["/etc/sudoers.d"]="0:0:0750"
    ["/etc/polkit-1/rules.d"]="0:0:0750"
    ["/usr/local/bin/fuse"]="0:0:0755"
    ["/usr/local/bin/forge-install"]="0:0:0755"
    ["/usr/local/bin/forge-update"]="0:0:0755"
    ["/usr/local/bin/choose-mirror"]="0:0:0755"
    ["/usr/local/bin/livecd-sound"]="0:0:0755"
    ["/etc/forge/logo.txt"]="0:0:0644"
    ["/etc/forge/fastfetch.jsonc"]="0:0:0644"
    ["/etc/greetd/config.toml"]="0:0:0644"
    ["/etc/mkinitcpio.conf"]="0:0:0644"
    ["/etc/apparmor.d/usr.bin.firefox"]="0:0:0644"
    ["/etc/apparmor.d/usr.local.bin.fuse"]="0:0:0644"
    ["/etc/systemd/system/getty@tty1.service.d/autologin.conf"]="0:0:0644"
    ["/root/.zlogin"]="0:0:0600"
    ["/root/.zshrc"]="0:0:0600"
)
