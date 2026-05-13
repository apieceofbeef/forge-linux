#!/usr/bin/env bash
#
# build.sh -- build the FORGE Linux ISO.
#
# Run this from the repository root on an Arch Linux host:
#
#     ./build.sh                  # build into ./out/ using ./work/ as scratch
#     ./build.sh -o /tmp/out      # custom output directory
#     ./build.sh -w /tmp/work     # custom work directory
#     ./build.sh --clean          # wipe work/ and out/ before building
#     ./build.sh --verbose        # pass -v to mkarchiso
#
# Requires: archiso, arch-install-scripts, squashfs-tools, libisoburn,
#           dosfstools, mtools, erofs-utils (optional), grub (for UEFI), edk2-shell.
#
# The script does NOT require an Arch Linux host strictly, but mkarchiso
# is only packaged for Arch and Arch-derivatives.

set -euo pipefail

###############################################################################
# Configuration
###############################################################################
PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${PROFILE_DIR}/work"
OUT_DIR="${PROFILE_DIR}/out"
VERBOSE=0
CLEAN=0

REQUIRED_PKGS=(archiso arch-install-scripts squashfs-tools libisoburn dosfstools mtools grub)
REQUIRED_CMDS=(mkarchiso pacstrap mksquashfs xorriso mkfs.fat mformat grub-mkrescue)

###############################################################################
# Pretty printing
###############################################################################
c_reset=$'\033[0m'; c_red=$'\033[1;31m'; c_grn=$'\033[1;32m'
c_ylw=$'\033[1;33m'; c_blu=$'\033[1;34m'; c_bld=$'\033[1m'

info() { printf '%s[forge]%s %s\n'  "$c_blu" "$c_reset" "$*"; }
ok()   { printf '%s[forge]%s %s\n'  "$c_grn" "$c_reset" "$*"; }
warn() { printf '%s[forge]%s %s\n'  "$c_ylw" "$c_reset" "$*" >&2; }
die()  { printf '%s[forge]%s %s\n'  "$c_red" "$c_reset" "$*" >&2; exit 1; }

usage() {
    sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

###############################################################################
# Argument parsing
###############################################################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--out)     OUT_DIR="$(readlink -f -- "$2")";  shift 2 ;;
        -w|--work)    WORK_DIR="$(readlink -f -- "$2")"; shift 2 ;;
        --clean)      CLEAN=1; shift ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help)    usage 0 ;;
        *) die "Unknown option: $1 (try --help)" ;;
    esac
done

###############################################################################
# Sanity checks
###############################################################################
[[ $EUID -eq 0 ]] || die "build.sh must run as root (mkarchiso requires it). Re-run with: sudo $0 $*"

if [[ ! -f /etc/arch-release ]]; then
    warn "This host does not look like Arch Linux (/etc/arch-release missing)."
    warn "mkarchiso is only officially supported on Arch / Arch-derived hosts."
fi

info "Checking required commands"
missing_cmds=()
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing_cmds+=("$cmd")
done

if (( ${#missing_cmds[@]} )); then
    warn "Missing commands: ${missing_cmds[*]}"
    if command -v pacman >/dev/null 2>&1; then
        warn "Install the required Arch packages with:"
        warn "    sudo pacman -S --needed ${REQUIRED_PKGS[*]}"
    fi
    die "Aborting: install the missing tooling and re-run."
fi
ok "All required commands present"

###############################################################################
# Disk-space pre-flight (mkarchiso needs ~8 GiB free for a releng-sized build)
###############################################################################
needed_kib=$((8 * 1024 * 1024))
mkdir -p "$WORK_DIR" "$OUT_DIR"
avail_kib="$(df -Pk "$WORK_DIR" | awk 'NR==2 {print $4}')"
if (( avail_kib < needed_kib )); then
    warn "Only $((avail_kib / 1024)) MiB free under $WORK_DIR; need at least $((needed_kib / 1024)) MiB."
fi

###############################################################################
# Profile validation
###############################################################################
for f in profiledef.sh packages.x86_64 pacman.conf airootfs/root/customize_airootfs.sh; do
    [[ -e "${PROFILE_DIR}/${f}" ]] || die "Profile is incomplete: missing ${f}"
done

# shellcheck disable=SC1091
( cd "$PROFILE_DIR" && bash -n profiledef.sh ) || die "profiledef.sh has syntax errors"

###############################################################################
# Clean (optional)
###############################################################################
if (( CLEAN )); then
    info "Wiping previous build artefacts"
    rm -rf -- "$WORK_DIR" "$OUT_DIR"
    mkdir -p -- "$WORK_DIR" "$OUT_DIR"
fi

###############################################################################
# Invoke mkarchiso
###############################################################################
mkarchiso_args=( -w "$WORK_DIR" -o "$OUT_DIR" )
(( VERBOSE )) && mkarchiso_args=( -v "${mkarchiso_args[@]}" )

info "Building FORGE Linux ISO"
info "  profile : $PROFILE_DIR"
info "  work    : $WORK_DIR"
info "  output  : $OUT_DIR"

start_ts="$(date +%s)"
mkarchiso "${mkarchiso_args[@]}" "$PROFILE_DIR"
end_ts="$(date +%s)"

###############################################################################
# Report
###############################################################################
iso_path="$(find "$OUT_DIR" -maxdepth 1 -type f -name 'forge-linux-*.iso' | sort | tail -n 1)"
if [[ -n "$iso_path" ]]; then
    iso_size="$(du -h "$iso_path" | awk '{print $1}')"
    ok "Built $(basename "$iso_path") (${iso_size}) in $((end_ts - start_ts))s"
    info "ISO checksum:"
    ( cd "$OUT_DIR" && sha256sum "$(basename "$iso_path")" )
else
    die "Build finished but no forge-linux-*.iso was produced under $OUT_DIR"
fi
