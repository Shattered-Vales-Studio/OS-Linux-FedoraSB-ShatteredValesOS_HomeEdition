#!/usr/bin/env bash
#
# set-os-release.sh
#
# Purpose:
#   Brands the OS name, edition and logo shown in Settings > About and boot
#   menus. ID and VERSION_ID stay Fedora's, because package tooling and
#   third-party installers key off them. NAME stays the plain OS name so
#   tools that match on it treat every edition alike; the edition goes in
#   VARIANT and PRETTY_NAME.
#
# Inputs:
#   /usr/share/shatteredvales/brand.env

set -euo pipefail

# shellcheck source=/dev/null
source /usr/share/shatteredvales/brand.env

readonly OS_RELEASE=/usr/lib/os-release

# set_key
#   Replaces or appends a KEY="value" line in os-release.
#   Arguments: $1 key, $2 value
#   Returns: 0 always
set_key() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "${OS_RELEASE}"; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "${OS_RELEASE}"
    else
        echo "${key}=\"${value}\"" >> "${OS_RELEASE}"
    fi
}

# accent_sgr
#   Converts BRAND_ACCENT (#rrggbb) into an SGR colour sequence.
#   Arguments: none
#   Output: "38;2;<r>;<g>;<b>" on stdout
#   Returns: 0 always
accent_sgr() {
    local hex="${BRAND_ACCENT#\#}"
    printf '38;2;%d;%d;%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# main
#   Rewrites the branded os-release keys.
#   Arguments: none
#   Returns: 0 on success
main() {
    local version
    version="$(sed -n 's/^VERSION_ID=//p' "${OS_RELEASE}" | tr -d '"')"
    set_key NAME "${BRAND_OS_NAME}"
    set_key PRETTY_NAME "${BRAND_OS_NAME} ${BRAND_EDITION} (Fedora ${version})"
    set_key VARIANT "${BRAND_EDITION}"
    set_key VARIANT_ID "shatteredvales-${BRAND_EDITION_ID}"
    # GNOME Settings resolves LOGO as an icon name from the hicolor theme.
    set_key LOGO "shatteredvales-logo"
    set_key HOME_URL "${BRAND_URL}"
    # Fedora's support, bug and documentation links would send people to
    # Fedora for problems in this image's own configuration.
    set_key SUPPORT_URL "${BRAND_URL}"
    set_key DOCUMENTATION_URL "${BRAND_DOCS_URL}"
    set_key BUG_REPORT_URL "${BRAND_REPO_URL}/issues"
    set_key DEFAULT_HOSTNAME "shatteredvales"
    # Tools such as systemd colour the OS name with this; it is the brand
    # gold as a 24-bit SGR sequence.
    set_key ANSI_COLOR "$(accent_sgr)"
}

main "$@"
