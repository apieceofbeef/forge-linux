#!/usr/bin/env bash
#
# test/smoke-test.sh -- QEMU boot smoke test for FORGE Linux ISOs.
#
# Usage:
#     test/smoke-test.sh                          # serial-console boot benchmark
#     test/smoke-test.sh --gui                    # GTK display, manual inspection
#     test/smoke-test.sh --bios                   # BIOS boot path instead of UEFI
#     test/smoke-test.sh --iso path/to/forge.iso  # explicit ISO
#     test/smoke-test.sh --timeout 240            # cap test runtime (seconds)
#
# Exit codes:
#   0  PASS  (boot string detected within timeout)
#   1  FAIL  (timeout reached without seeing the boot string)
#   2  Misconfiguration (missing dependency, missing ISO, bad args)

set -Eeuo pipefail
shopt -s extglob

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ISO=""
MODE="uefi"        # uefi | bios
DISPLAY_MODE="serial"  # serial | gui
TIMEOUT=300
MEM_MB=4096
SMP=4
EXPECT='\b(forge login:|Hyprland|reached target Graphical Interface|Welcome to FORGE)\b'

#-----------------------------------------------------------------------------#
# Pretty
#-----------------------------------------------------------------------------#
if [[ -t 1 && -z ${NO_COLOR-} ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
    C_AMBER=$'\033[38;2;245;158;11m'; C_GREEN=$'\033[38;2;34;197;94m'
    C_RED=$'\033[38;2;239;68;68m';   C_MUTED=$'\033[38;2;148;163;184m'
else
    C_RESET= C_BOLD= C_AMBER= C_GREEN= C_RED= C_MUTED=
fi
say()  { printf '%s%s[smoke]%s %s\n' "$C_AMBER" "$C_BOLD" "$C_RESET" "$*"; }
ok()   { printf '%s%s[ pass ]%s %s\n' "$C_GREEN" "$C_BOLD" "$C_RESET" "$*"; }
fail() { printf '%s%s[ fail ]%s %s\n' "$C_RED" "$C_BOLD" "$C_RESET" "$*" >&2; }
muted(){ printf '%s%s%s\n' "$C_MUTED" "$*" "$C_RESET"; }

usage() {
    sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

#-----------------------------------------------------------------------------#
# Args
#-----------------------------------------------------------------------------#
while (( $# )); do
    case "$1" in
        --gui)          DISPLAY_MODE="gui";     shift ;;
        --serial)       DISPLAY_MODE="serial";  shift ;;
        --uefi)         MODE="uefi";            shift ;;
        --bios)         MODE="bios";            shift ;;
        --iso)          ISO="$2";               shift 2 ;;
        --iso=*)        ISO="${1#*=}";          shift ;;
        --timeout)      TIMEOUT="$2";           shift 2 ;;
        --timeout=*)    TIMEOUT="${1#*=}";      shift ;;
        --memory)       MEM_MB="$2";            shift 2 ;;
        --smp)          SMP="$2";               shift 2 ;;
        --expect)       EXPECT="$2";            shift 2 ;;
        -h|--help)      usage ;;
        *) fail "unknown argument: $1"; usage ;;
    esac
done

#-----------------------------------------------------------------------------#
# Dependency / artefact checks
#-----------------------------------------------------------------------------#
require() {
    command -v "$1" >/dev/null 2>&1 || {
        fail "missing dependency: $1"
        printf 'Install with: sudo pacman -S %s\n' "${2:-$1}" >&2
        exit 2
    }
}
require qemu-system-x86_64 qemu-base
require timeout coreutils

OVMF_CODE=""
OVMF_VARS_SRC=""
if [[ $MODE == "uefi" ]]; then
    for candidate in \
        /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
        /usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE_4M.fd
    do [[ -r $candidate ]] && OVMF_CODE="$candidate" && break; done
    for candidate in \
        /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
        /usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd \
        /usr/share/OVMF/OVMF_VARS.fd \
        /usr/share/OVMF/OVMF_VARS_4M.fd
    do [[ -r $candidate ]] && OVMF_VARS_SRC="$candidate" && break; done

    [[ -n $OVMF_CODE && -n $OVMF_VARS_SRC ]] || {
        fail "UEFI firmware (edk2-ovmf) not found"
        printf 'Install with: sudo pacman -S edk2-ovmf\n' >&2
        exit 2
    }
fi

if [[ -z $ISO ]]; then
    ISO="$(ls -1t "$ROOT/out"/forge-linux-*.iso 2>/dev/null | head -n1 || true)"
fi
[[ -n $ISO && -r $ISO ]] || {
    fail "no FORGE ISO found.  Build one with: sudo ./build.sh"
    exit 2
}

say "ISO     : $ISO"
say "Mode    : $MODE / $DISPLAY_MODE"
say "RAM     : ${MEM_MB} MiB,  vCPU : $SMP"
say "Timeout : ${TIMEOUT}s"
say "Expect  : /${EXPECT}/"

OVMF_VARS=""
if [[ $MODE == "uefi" ]]; then
    OVMF_VARS="$(mktemp -t forge_VARS.XXXXXXXX.fd)"
    cp -- "$OVMF_VARS_SRC" "$OVMF_VARS"
    say "OVMF    : $OVMF_CODE"
fi

#-----------------------------------------------------------------------------#
# Build QEMU args
#-----------------------------------------------------------------------------#
QEMU_BIN=qemu-system-x86_64
QEMU_ARGS=(
    -machine q35,smm=on,accel=kvm:tcg
    -cpu host
    -smp "$SMP"
    -m "${MEM_MB}"
    -device virtio-net-pci,netdev=net0
    -netdev user,id=net0
    -drive   "file=$ISO,media=cdrom,readonly=on,id=cdrom0"
    -boot    d
    -rtc     base=utc
    -no-reboot
)

# KVM if available, otherwise software accel.
if [[ -w /dev/kvm ]]; then
    QEMU_ARGS=( -enable-kvm "${QEMU_ARGS[@]}" )
else
    say "/dev/kvm not writable -- falling back to TCG (slow)."
fi

if [[ $MODE == "uefi" ]]; then
    QEMU_ARGS+=(
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
        -drive if=pflash,format=raw,file="$OVMF_VARS"
    )
fi

if [[ $DISPLAY_MODE == "gui" ]]; then
    QEMU_ARGS+=( -device virtio-vga-gl -display gtk,gl=on )
else
    # Serial-only nographic boot: pipe QEMU stdout to our matcher.
    QEMU_ARGS+=(
        -vga none
        -display none
        -nographic
        -serial mon:stdio
    )
fi

#-----------------------------------------------------------------------------#
# Run
#-----------------------------------------------------------------------------#
LOG="$(mktemp -t forge-smoke.XXXXXXXX.log)"
trap '_cleanup' EXIT
_cleanup() {
    [[ -f $OVMF_VARS ]] && rm -f -- "$OVMF_VARS"
    [[ -f $LOG       ]] && rm -f -- "$LOG"
}

say "Booting in ${C_BOLD}$DISPLAY_MODE${C_RESET} mode (Ctrl-A x to abort serial)..."
T0=$(date +%s%3N 2>/dev/null || date +%s)

if [[ $DISPLAY_MODE == "gui" ]]; then
    # GUI mode -- the user clicks around manually.
    timeout --foreground "${TIMEOUT}s" "$QEMU_BIN" "${QEMU_ARGS[@]}" \
        || true
    T1=$(date +%s%3N 2>/dev/null || date +%s)
    elapsed=$(( T1 - T0 ))
    muted "(GUI session ended after ${elapsed} ms)"
    ok "GUI session terminated cleanly."
    exit 0
fi

# Serial / nographic mode -- stream output, grep for EXPECT, kill on match.
set +e
"$QEMU_BIN" "${QEMU_ARGS[@]}" 2>&1 \
    | tee "$LOG" \
    | (
        # Stream stdin and exit 0 as soon as we see the expected pattern.
        while IFS= read -r line; do
            printf '%s\n' "$line"
            if [[ $line =~ $EXPECT ]]; then
                exit 0
            fi
        done
        exit 1
    )
match_rc=$?
set -e

# Reap qemu so it doesn't hang around if the matcher returned early.
pkill -P $$ -f "qemu-system-x86_64.*$ISO" 2>/dev/null || true

T1=$(date +%s%3N 2>/dev/null || date +%s)
elapsed=$(( T1 - T0 ))

# Convert ms -> s with one decimal place when applicable.
if (( elapsed > 999 )); then
    pretty="$(awk -v ms="$elapsed" 'BEGIN{printf "%.2fs", ms/1000}')"
else
    pretty="${elapsed}ms"
fi

if (( match_rc == 0 )); then
    ok  "Boot string matched in ${C_BOLD}${pretty}${C_RESET}"
    exit 0
else
    fail "Timeout (${TIMEOUT}s) reached without matching ${C_BOLD}/${EXPECT}/${C_RESET}"
    fail "Last 40 lines of QEMU output:"
    tail -n 40 -- "$LOG" | sed 's/^/    /'
    exit 1
fi
