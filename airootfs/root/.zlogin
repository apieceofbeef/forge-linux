# /root/.zlogin
#
# FORGE Linux -- live-ISO login hook for the auto-logged-in root user.
#
# When root lands on tty1 (the autologin VT) and no graphical session is
# already running, automatically jump straight into Hyprland.  This makes
# the live ISO feel like a "live desktop" instead of a TTY.
#
# All other TTYs fall through to a normal zsh prompt.

if [[ -z $WAYLAND_DISPLAY && -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then
    # XDG runtime dir is required by Wayland clients; systemd's pam_systemd
    # creates it for normal logins but agetty --autologin doesn't, so make
    # sure it exists with the correct mode before exec'ing the compositor.
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    if [[ ! -d $XDG_RUNTIME_DIR ]]; then
        install -d -m 0700 -o "$(id -u)" -g "$(id -g)" "$XDG_RUNTIME_DIR"
    fi

    # Sensible Wayland environment.
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=Hyprland
    export XDG_SESSION_DESKTOP=Hyprland
    export QT_QPA_PLATFORM="wayland;xcb"
    export GDK_BACKEND="wayland,x11"
    export MOZ_ENABLE_WAYLAND=1

    # Greet, then launch.  Use exec so Hyprland inherits the controlling
    # terminal -- when it exits, the user lands back at the zsh prompt.
    if command -v Hyprland >/dev/null 2>&1; then
        printf '\n  Launching Hyprland on tty1... (Ctrl+Alt+F2 for a TTY shell)\n\n'
        exec Hyprland
    fi
fi
