#!/usr/bin/env bash
#
# first-login.sh
#
# Purpose:
#   Per-person setup that cannot live in the read-only image. Runs from the
#   desktop autostart at every login but only does work for steps that have
#   not completed yet, so steps added in later images reach existing
#   accounts automatically. On a person's first login it also opens the
#   Welcome window (text size, and Family Setup for administrators).
#
# Usage:
#   Runs automatically at login. Can be re-run manually with `sv-first-login`.
#
# State:
#   ~/.local/state/shatteredvales/<step>.done marks a finished step.
#
# Exit codes:
#   0 always; failed steps are retried at the next login.

set -uo pipefail

readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/shatteredvales"
readonly LOG_FILE="${STATE_DIR}/first-login.log"
readonly FAMILY_SETUP=/usr/libexec/shatteredvales/family-setup
readonly DOCS_DIR=/usr/share/shatteredvales/docs

# notify
#   Shows a desktop notification when a graphical session is available.
#   Arguments: $1 summary, $2 body
#   Returns: 0 always
notify() {
    if command -v notify-send >/dev/null && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        notify-send --app-name="Shattered Vales" --icon=shatteredvales-logo "$1" "$2" || true
    fi
}

# run_step
#   Runs a setup function once per user and records success.
#   Arguments: $1 step id, $2 function name
#   Returns: the function's exit status; failures are retried next login
run_step() {
    local id="$1" fn="$2"
    [[ -f "${STATE_DIR}/${id}.done" ]] && return 0
    echo "== ${id} ($(date -Is))"
    if "${fn}"; then
        touch "${STATE_DIR}/${id}.done"
    else
        echo "Step ${id} failed; it will retry on next login"
        return 1
    fi
}

# wait_for_network
#   Waits up to two minutes for connectivity, since autostart can fire
#   before Wi-Fi or Tailscale is up.
#   Returns: 0 when online, 1 on timeout
wait_for_network() {
    nm-online -q -t 120
}

# install_craft_app
#   Installs one Craft app as a user Flatpak bundle from its latest GitHub
#   release, after checking the bundle against the release's SHA256SUMS.txt.
#   Uses github.com download URLs rather than the API, which allows only 60
#   unauthenticated requests an hour per IP and would run out when a whole
#   office logs in at once.
#   Arguments: $1 app id, $2 GitHub owner/repo, $3 work directory
#   Returns: 0 on success, 1 on download, checksum or install failure
install_craft_app() {
    local id="$1" repo="$2" work="$3" base sums line file sum
    base="https://github.com/${repo}/releases/latest/download"
    sums="$(curl -fsSL --retry 2 "${base}/SHA256SUMS.txt")" || return 1
    line="$(grep -E "  ${id}-[0-9][^ ]*-linux-x86_64\.flatpak$" <<<"${sums}" | head -n1)"
    [[ -n "${line}" ]] || { echo "No x86_64 Flatpak in the latest ${repo} release"; return 1; }
    file="${line##* }"
    sum="${line%% *}"
    curl -fsSL --retry 2 -o "${work}/${file}" "${base}/${file}" || return 1
    echo "${sum}  ${work}/${file}" | sha256sum -c --quiet - || return 1
    # The same command ArtCraft Launcher runs, so it recognises and updates
    # these installs as its own.
    flatpak install --user -y --noninteractive --reinstall --bundle "${work}/${file}" || return 1
    rm -f "${work:?}/${file}"
}

# step_artcraft_apps
#   Installs the edition's Craft apps (listed in
#   /usr/share/shatteredvales/artcraft-apps.list) for this user. Apps the
#   user already has are skipped; failures are retried at the next login.
#   Returns: 0 if every app is installed, 1 otherwise
step_artcraft_apps() {
    local list=/usr/share/shatteredvales/artcraft-apps.list id flatpak_id repo work failed=0
    wait_for_network || return 1
    # Bundles pull their runtime from the user's Flathub remote.
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
    notify "Installing ArtCraft apps" "About 1 GB in the background; ArtCraft Launcher keeps them updated afterwards."
    work="$(mktemp -d)"
    while read -r id flatpak_id repo; do
        [[ -z "${id}" || "${id}" == \#* ]] && continue
        if flatpak info --user "${flatpak_id}" >/dev/null 2>&1 \
            || flatpak info --system "${flatpak_id}" >/dev/null 2>&1; then
            continue
        fi
        echo "Installing ${id} from ${repo}"
        install_craft_app "${id}" "${repo}" "${work}" || { echo "Failed: ${id}"; failed=1; }
    done < "${list}"
    rm -rf "${work}"
    (( failed == 0 )) || return 1
    notify "ArtCraft apps installed" "Open ArtCraft Launcher to see the suite and check for updates."
}

# is_generated_avatar
#   Tells a picture the user chose apart from the initials avatar GNOME
#   Initial Setup generates. Generated avatars are drawn as a circle with
#   transparent corners; photos and GNOME's stock pictures are opaque
#   squares, which GNOME crops to a circle only when displaying them.
#   Arguments: $1 path to the current account picture
#   Returns: 0 if the picture is a generated initials avatar, 1 otherwise
is_generated_avatar() {
    python3 -I - "$1" <<'PY'
import sys
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
try:
    pixbuf = GdkPixbuf.Pixbuf.new_from_file(sys.argv[1])
except Exception:
    sys.exit(1)
if not pixbuf.get_has_alpha():
    sys.exit(1)
pixels = pixbuf.get_pixels()
# Alpha of the top-left pixel (RGBA, so byte 3).
sys.exit(0 if pixels[3] == 0 else 1)
PY
}

# is_admin
#   Tells whether this account is an administrator (a member of wheel).
#   Arguments: none
#   Returns: 0 for administrators, 1 otherwise
is_admin() {
    id -nG | tr ' ' '\n' | grep -qx wheel
}

# sync_user_icon
#   Gives the account the studio logo as its picture when it has none, only
#   GNOME's generated initials avatar, or one of the studio's own defaults:
#   red for administrators, gold for everyone else, so the login screen
#   shows which accounts can change the computer. Runs at every login so the
#   colour follows the account when it is made or unmade an administrator.
#   Pictures the user chose are never replaced.
#   Arguments: none
#   Returns: 0 when the picture is set or kept, 1 if setting it failed
sync_user_icon() {
    local user_path icon default=/usr/share/shatteredvales/avatar.png
    local admin=/usr/share/shatteredvales/avatar-admin.png picture
    user_path="$(busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts \
        org.freedesktop.Accounts FindUserById x "$(id -u)" | cut -d'"' -f2)" || return 1
    icon="$(busctl --system get-property org.freedesktop.Accounts "${user_path}" \
        org.freedesktop.Accounts.User IconFile | cut -d'"' -f2)" || return 1
    picture="${default}"
    is_admin && picture="${admin}"
    # AccountsService stores a copy, so the current picture is compared by
    # content with the defaults rather than by path.
    if [[ -s "${icon}" ]]; then
        cmp -s "${icon}" "${picture}" && return 0
        if ! cmp -s "${icon}" "${default}" && ! cmp -s "${icon}" "${admin}" \
            && ! is_generated_avatar "${icon}"; then
            return 0
        fi
    fi
    busctl --system call org.freedesktop.Accounts "${user_path}" \
        org.freedesktop.Accounts.User SetIconFile s "${picture}" >/dev/null
}

# sync_share_bookmarks
#   Adds the shares listed in /etc/shatteredvales/network-shares to the
#   Files sidebar. Runs at every login rather than once, so shares an admin
#   adds later reach existing users. Windows paths (\\server\share) are
#   converted to smb:// addresses; bookmarks already present are left alone.
#   Arguments: none
#   Returns: 0 always
sync_share_bookmarks() {
    local list=/etc/shatteredvales/network-shares
    local bookmarks="${XDG_CONFIG_HOME:-${HOME}/.config}/gtk-3.0/bookmarks"
    local address name url
    [[ -r "${list}" ]] || return 0
    mkdir -p "$(dirname "${bookmarks}")"
    touch "${bookmarks}"
    while read -r address name; do
        [[ -z "${address}" || "${address}" == \#* ]] && continue
        if [[ "${address}" == \\\\* ]]; then
            url="smb://$(sed -e 's#^\\\\##' -e 's#\\#/#g' <<<"${address}")"
        else
            url="${address}"
        fi
        # Compared as a whole first field, since addresses contain dots and
        # other characters grep would treat as a pattern.
        awk -v u="${url}" '$1 == u {found = 1} END {exit !found}' "${bookmarks}" && continue
        echo "${url}${name:+ ${name}}" >> "${bookmarks}"
        echo "Added share bookmark ${url}"
    done < "${list}"
}

# step_remote_help_doc
#   Copies the "Getting Remote Help" guide into the person's Documents
#   folder, where whoever helps them can find it. An existing copy is kept.
#   Returns: cp exit status
step_remote_help_doc() {
    local documents
    documents="$(xdg-user-dir DOCUMENTS 2>/dev/null)"
    # xdg-user-dir falls back to $HOME when the folder is not configured;
    # never drop documents loose in the home folder.
    [[ -n "${documents}" && "${documents}" != "${HOME}" ]] || documents="${HOME}/Documents"
    mkdir -p "${documents}"
    cp -n "${DOCS_DIR}/Getting Remote Help.html" "${documents}/"
}

# open_welcome
#   Opens the Welcome window once per person, without waiting for it, so
#   the installs below run while the person reads it. The window records
#   its own completion (welcome.done) when the person finishes or chooses
#   "Not now", so closing it early shows it again at the next login.
#   Arguments: none
#   Returns: 0 always
open_welcome() {
    [[ -f "${STATE_DIR}/welcome.done" ]] && return 0
    [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] || return 0
    setsid -f "${FAMILY_SETUP}" --welcome >/dev/null 2>&1 || true
}

# step_terminal_palette
#   Makes the Shattered Vales palette the default colours of the user's
#   Ptyxis profile. Ptyxis reads custom palettes only from the user's data
#   folder, so the palette is copied there. A profile is created when the
#   user has never opened Ptyxis, and a palette the user already chose is
#   left alone.
#   Arguments: none
#   Returns: non-zero if the palette cannot be installed or applied
step_terminal_palette() {
    local dir="${XDG_DATA_HOME:-${HOME}/.local/share}/org.gnome.Ptyxis/palettes"
    local uuid path current
    mkdir -p "${dir}"
    cp /usr/share/shatteredvales/ptyxis/ShatteredVales.palette "${dir}/" || return 1
    uuid="$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'")" || return 1
    if [[ -z "${uuid}" ]]; then
        # Ptyxis profile ids are 32 hex digits, the same shape it generates.
        uuid="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
        gsettings set org.gnome.Ptyxis profile-uuids "['${uuid}']" || return 1
        gsettings set org.gnome.Ptyxis default-profile-uuid "${uuid}" || return 1
    fi
    path="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/${uuid}/"
    current="$(gsettings get "${path}" palette | tr -d "'")" || return 1
    [[ "${current}" == gnome ]] || return 0
    gsettings set "${path}" palette ShatteredVales
}

# main
#   Opens the Welcome window and runs every pending setup step, logging to
#   the state directory.
#   Arguments: none
#   Returns: 0 always; failed steps are retried at the next login
main() {
    mkdir -p "${STATE_DIR}"
    exec >>"${LOG_FILE}" 2>&1

    local failed=0
    open_welcome
    sync_user_icon || failed=1
    sync_share_bookmarks
    run_step remote-help-doc-v1 step_remote_help_doc || failed=1
    run_step terminal-palette-v1 step_terminal_palette || failed=1
    # Last, because it downloads several hundred MB.
    run_step artcraft-apps-v1 step_artcraft_apps || failed=1

    if (( failed )); then
        notify "Setup not finished yet" "It will try again the next time you sign in."
    fi
}

main "$@"
