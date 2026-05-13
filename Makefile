# FORGE Linux build pipeline.
#
# Usage:
#     make deps       Install Arch-side build/test dependencies
#     make build      Clean build of the ISO via build.sh
#     make fast       Incremental build (skips --clean)
#     make test       Boot the most recent ISO in QEMU with a GTK display
#     make smoke      Boot the most recent ISO in QEMU headless (boot benchmark)
#     make sha        Print the SHA-256 of the most recent ISO
#     make clean      Remove work/ and out/
#     make all        deps + build + test (full happy path)
#
# All targets are .PHONY -- there are no file-based dependencies to track
# because mkarchiso owns the build graph.  We just orchestrate.

SHELL          := /bin/bash
.SHELLFLAGS    := -eu -o pipefail -c
.ONESHELL:

ROOT           := $(CURDIR)
OUT_DIR        := $(ROOT)/out
WORK_DIR       := $(ROOT)/work
BUILD_SH       := $(ROOT)/build.sh
SMOKE_SH       := $(ROOT)/test/smoke-test.sh
LATEST_ISO     := $(shell ls -1t $(OUT_DIR)/forge-linux-*.iso 2>/dev/null | head -n1)

# Colours -- only emitted when stdout is a terminal.
ifdef NO_COLOR
COLOR_AMBER  :=
COLOR_GREEN  :=
COLOR_BOLD   :=
COLOR_RESET  :=
else
COLOR_AMBER  := \033[38;2;245;158;11m
COLOR_GREEN  := \033[38;2;34;197;94m
COLOR_BOLD   := \033[1m
COLOR_RESET  := \033[0m
endif

.PHONY: help all deps build fast test smoke sha clean distclean tarball lint

help:
	@printf "$(COLOR_AMBER)$(COLOR_BOLD)FORGE Linux build targets$(COLOR_RESET)\n"
	@printf "  make deps     install archiso + qemu deps via pacman\n"
	@printf "  make build    clean build of the ISO (sudo)\n"
	@printf "  make fast     incremental build, skips --clean (sudo)\n"
	@printf "  make test     boot latest ISO in QEMU (GTK display)\n"
	@printf "  make smoke    headless boot benchmark of latest ISO\n"
	@printf "  make lint     run bash -n + tomllib lint on configs\n"
	@printf "  make sha      print SHA-256 of latest ISO\n"
	@printf "  make clean    remove work/ and out/\n"
	@printf "  make all      deps + build + test\n"

##############################################################################
# Dependencies
##############################################################################
deps:
	@if ! command -v pacman >/dev/null 2>&1; then
	    printf "$(COLOR_BOLD)pacman not found.$(COLOR_RESET)  This target is Arch-only.\n" >&2
	    exit 2
	fi
	@printf "$(COLOR_AMBER)Installing archiso + QEMU build/test dependencies...$(COLOR_RESET)\n"
	sudo pacman -S --needed --noconfirm \
	    archiso arch-install-scripts squashfs-tools libisoburn \
	    dosfstools mtools grub edk2-shell \
	    qemu-base qemu-system-x86 edk2-ovmf

##############################################################################
# Build
##############################################################################
build:
	@chmod +x $(BUILD_SH)
	sudo $(BUILD_SH) --clean --verbose

fast:
	@chmod +x $(BUILD_SH)
	sudo $(BUILD_SH) --verbose

##############################################################################
# Test
##############################################################################
test:
	@chmod +x $(SMOKE_SH)
	@$(if $(LATEST_ISO),,printf "No ISO found in out/; run 'make build' first.\n" >&2 && exit 2)
	@printf "Booting $(COLOR_GREEN)$(LATEST_ISO)$(COLOR_RESET) in QEMU (GUI)...\n"
	$(SMOKE_SH) --gui --iso "$(LATEST_ISO)"

smoke:
	@chmod +x $(SMOKE_SH)
	@$(if $(LATEST_ISO),,printf "No ISO found in out/; run 'make build' first.\n" >&2 && exit 2)
	$(SMOKE_SH) --iso "$(LATEST_ISO)" --timeout 300

##############################################################################
# Hash + clean
##############################################################################
sha:
	@$(if $(LATEST_ISO),,printf "No ISO found in out/\n" >&2 && exit 2)
	@printf "$(COLOR_AMBER)$(LATEST_ISO)$(COLOR_RESET)\n"
	@sha256sum -- "$(LATEST_ISO)" | awk '{printf "  SHA256  %s\n", $$1}'

clean:
	@printf "$(COLOR_AMBER)Removing $(WORK_DIR) and $(OUT_DIR)...$(COLOR_RESET)\n"
	sudo rm -rf -- "$(WORK_DIR)"
	rm -rf -- "$(OUT_DIR)"

distclean: clean
	sudo rm -rf -- "$(ROOT)/work"

##############################################################################
# Lint
##############################################################################
lint:
	@printf "$(COLOR_AMBER)bash -n on shell scripts$(COLOR_RESET)\n"
	@for f in profiledef.sh build.sh \
	          airootfs/root/customize_airootfs.sh \
	          airootfs/usr/local/bin/fuse \
	          airootfs/usr/local/bin/forge-install \
	          airootfs/usr/local/bin/forge-update \
	          test/smoke-test.sh \
	          airootfs/root/.zlogin \
	          airootfs/root/.zshrc; do
	    if bash -n "$$f"; then printf "  PASS  %s\n" "$$f"; \
	    else                    printf "  FAIL  %s\n" "$$f"; exit 1; fi
	done
	@printf "$(COLOR_AMBER)tomllib lint$(COLOR_RESET)\n"
	@python3 -c 'import tomllib, sys; \
	    [tomllib.loads(open(p).read()) for p in sys.argv[1:]]; print("  OK")' \
	    airootfs/etc/skel/.config/starship.toml \
	    airootfs/etc/skel/.config/helix/config.toml \
	    airootfs/etc/skel/.config/helix/themes/forge.toml \
	    airootfs/etc/greetd/config.toml

##############################################################################
# Tarball (for sharing the profile without rebuilding the ISO)
##############################################################################
tarball:
	tar czf forge-linux-profile.tar.gz \
	    --exclude='./out' --exclude='./work' --exclude='./.git' .
	@printf "Wrote $(COLOR_GREEN)forge-linux-profile.tar.gz$(COLOR_RESET)\n"

##############################################################################
# Convenience aggregator
##############################################################################
all: deps build test
