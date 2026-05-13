# /root/.zshrc -- live-ISO root shell.
#
# Re-export the same developer environment we ship to the live `forge`
# user so root sessions feel identical, but drop the fastfetch greeting
# (already shown by the live-ISO message-of-the-day) to keep TTYs clean.

if [[ -r /etc/skel/.zshrc ]]; then
    export FORGE_DISABLE_GREETING=1
    # shellcheck disable=SC1091
    source /etc/skel/.zshrc
fi

# Convenience for the auto-logged-in root user on the live ISO.
alias install-forge='forge-install'
alias setup='forge-install'
