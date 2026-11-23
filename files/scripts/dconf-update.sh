#!/usr/bin/env bash
#
# dconf-update.sh
#
# Purpose:
#   Renders brand values into the dconf defaults, makes sure the user and
#   GDM profiles read the system databases, and compiles them. System
#   databases provide defaults only; users can still change any setting.
#
# Inputs:
#   /usr/share/shatteredvales/brand.env
#   /etc/dconf/db/local.d/*, /etc/dconf/db/gdm.d/*

set -euo pipefail

# shellcheck source=/dev/null
source /usr/share/shatteredvales/brand.env

# ensure_profile_line
#   Appends a line to a dconf profile if it is not already present, creating
#   the profile when needed. Base images may or may not ship these profiles.
#   Arguments: $1 profile path, $2 line
#   Returns: 0 always
ensure_profile_line() {
    local profile="$1" line="$2"
    mkdir -p "$(dirname "${profile}")"
    touch "${profile}"
    grep -qxF "${line}" "${profile}" || echo "${line}" >> "${profile}"
}

# ensure_user_db_first
#   Guarantees the profile starts with the per-user database, creating the
#   profile if the base image does not ship one.
#   Arguments: $1 profile path
#   Returns: 0 always
ensure_user_db_first() {
    local profile="$1"
    mkdir -p "$(dirname "${profile}")"
    if [[ ! -s "${profile}" ]]; then
        echo 'user-db:user' > "${profile}"
    elif ! grep -qx 'user-db:user' "${profile}"; then
        sed -i '1i user-db:user' "${profile}"
    fi
}

# main
#   Fills brand placeholders, wires the dconf profiles and compiles the
#   system databases.
#   Arguments: none
#   Returns: non-zero if dconf update fails
main() {
    # Only regular files: base images may ship subdirectories such as locks/.
    find /etc/dconf/db/local.d /etc/dconf/db/gdm.d -maxdepth 1 -type f -print0 \
        | xargs -0 -r sed -i \
            -e "s|@BRAND_GNOME_ACCENT@|${BRAND_GNOME_ACCENT}|g" \
            -e "s|@BRAND_FONT_FAMILY@|${BRAND_FONT_FAMILY}|g" \
            -e "s|@BRAND_MONO_FONT_FAMILY@|${BRAND_MONO_FONT_FAMILY}|g" \
            -e "s|@BRAND_BG@|${BRAND_BG}|g"

    # The user db must come first so personal changes override defaults.
    ensure_user_db_first /etc/dconf/profile/user
    ensure_profile_line /etc/dconf/profile/user 'system-db:local'
    ensure_profile_line /etc/dconf/profile/gdm 'system-db:gdm'

    dconf update
}

main "$@"
