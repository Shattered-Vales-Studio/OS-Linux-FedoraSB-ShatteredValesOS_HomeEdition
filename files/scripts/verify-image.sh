#!/usr/bin/env bash
#
# verify-image.sh
#
# Purpose:
#   Final build gate. Fails the build when the image is not a valid bootc
#   image, when anything Home Edition depends on is missing, or when studio
#   developer tooling slipped in, so a broken image is never published to
#   family machines.
#
# Exit codes:
#   0 when every check passes, 1 otherwise.

set -euo pipefail

readonly REQUIRED_RPMS=(
    tailscale firefox thunderbird nano python3-gobject libadwaita openssl
    gnome-shell-extension-dash-to-dock gnome-shell-extension-appindicator
    jq pciutils libnotify fastfetch
)

# Developer tooling from the studio edition that must never reach a family
# machine: each would bring updates, services or attack surface nobody at
# home needs.
readonly FORBIDDEN_RPMS=(
    docker-ce code unityhub claude-desktop-unofficial
    nodejs26 dotnet-sdk-10.0 golang virt-manager
)

readonly REQUIRED_PATHS=(
    # Terminal colours, system summary logo and sign-in banners.
    /usr/share/shatteredvales/ptyxis/ShatteredVales.palette
    /usr/share/shatteredvales/fastfetch/logo.txt
    /etc/xdg/fastfetch/config.jsonc
    /etc/issue.d/50-shatteredvales.issue
    /usr/lib/motd.d/50-shatteredvales
    # Wallpapers offered in Settings > Appearance.
    /usr/share/backgrounds/shatteredvales/space.jpg
    /usr/share/backgrounds/shatteredvales/earth.jpg
    /usr/share/backgrounds/shatteredvales/vale.jpg
    /usr/share/backgrounds/shatteredvales/circuit.jpg
    /usr/share/gnome-background-properties/shatteredvales.xml
    /usr/bin/artcraft-launcher
    /etc/firewalld/zones/FedoraWorkstation.xml
    /etc/shatteredvales/network-shares
    /usr/share/fonts/google-fonts/Cinzel
    /usr/share/fonts/google-fonts/Lato
    "/usr/share/fonts/google-fonts/JetBrains Mono"
    # Support and update tools
    /usr/bin/sv-doctor
    /usr/bin/sv-update
    /usr/bin/sv-gpu-image
    /usr/bin/sv-first-login
    /usr/libexec/shatteredvales/update-reminder.sh
    /usr/lib/systemd/user/shatteredvales-update-reminder.timer
    /usr/libexec/shatteredvales/signed-switch.sh
    /usr/lib/systemd/system/shatteredvales-signed-switch.service
    /usr/share/applications/shatteredvales-update.desktop
    /usr/share/icons/hicolor/scalable/apps/shatteredvales-update.svg
    # Family Setup, Welcome and per-person setup
    /usr/libexec/shatteredvales/family-setup
    /usr/share/applications/io.shatteredvales.FamilySetup.desktop
    /usr/share/icons/hicolor/scalable/apps/shatteredvales-family-setup.svg
    /usr/libexec/shatteredvales/first-login.sh
    /etc/xdg/autostart/shatteredvales-first-login.desktop
    "/usr/share/shatteredvales/docs/Getting Remote Help.html"
    /usr/share/shatteredvales/artcraft-apps.list
    # Defaults and managed bookmarks (Streaming folder)
    /etc/xdg/mimeapps.list
    /etc/firefox/policies/policies.json
    /etc/chromium/policies/managed/shatteredvales-bookmarks.json
    # Desktop files referenced by favorite-apps in the dconf defaults.
    /usr/share/applications/org.mozilla.firefox.desktop
    /usr/share/applications/org.gnome.Nautilus.desktop
    /usr/share/applications/org.gnome.Settings.desktop
    # Branding
    /usr/share/plymouth/themes/shatteredvales/watermark.png
    /usr/share/backgrounds/shatteredvales/wallpaper.png
    /usr/share/shatteredvales/lockscreen-header.png
    /usr/share/shatteredvales/avatar.png
    /usr/share/shatteredvales/avatar-admin.png
    /etc/dconf/db/local
    /etc/dconf/db/gdm
)

# check_home_scope
#   Confirms nothing from the studio edition leaked in: no developer RPMs,
#   no app grid folders (Home Edition keeps a flat, phone-like grid) and no
#   SSH server listening (remote help goes through Tailscale SSH instead).
#   Arguments: none
#   Returns: 0 when the image is in scope, 1 otherwise
check_home_scope() {
    local item status=0
    for item in "${FORBIDDEN_RPMS[@]}"; do
        if rpm -q "${item}" >/dev/null 2>&1; then
            echo "UNEXPECTED RPM: ${item}"
            status=1
        fi
    done
    if [[ -e /etc/dconf/db/local.d/20-shatteredvales-app-folders ]]; then
        echo "UNEXPECTED: app grid folders"
        status=1
    fi
    if [[ "$(systemctl is-enabled sshd.service 2>/dev/null)" == enabled ]]; then
        echo "UNEXPECTED: sshd is enabled"
        status=1
    fi
    return "${status}"
}

# check_family_setup
#   Parses the Family Setup app, so a syntax error fails the build instead
#   of leaving a family without the account wizard. ast.parse writes no
#   bytecode into the read-only /usr.
#   Arguments: none
#   Returns: 0 when it parses, 1 otherwise
check_family_setup() {
    python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' \
        /usr/libexec/shatteredvales/family-setup \
        || { echo "Family Setup does not parse"; return 1; }
}

# main
#   Checks required RPMs and paths, the Plymouth theme, the edition's
#   scope, the Family Setup app and bootc lint.
#   Arguments: none
#   Returns: 0 when every check passes, 1 otherwise
main() {
    local failed=0 item

    for item in "${REQUIRED_RPMS[@]}"; do
        rpm -q "${item}" >/dev/null || { echo "MISSING RPM: ${item}"; failed=1; }
    done
    for item in "${REQUIRED_PATHS[@]}"; do
        [[ -e "${item}" ]] || { echo "MISSING PATH: ${item}"; failed=1; }
    done
    grep -q '^Theme=shatteredvales' /etc/plymouth/plymouthd.conf \
        || { echo "Plymouth theme not set"; failed=1; }
    check_home_scope || failed=1
    check_family_setup || failed=1

    bootc container lint || failed=1

    if (( failed )); then
        echo "Image verification failed" >&2
        exit 1
    fi
    echo "Image verification passed"
}

main "$@"
