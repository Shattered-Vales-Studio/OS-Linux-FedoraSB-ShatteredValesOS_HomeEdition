#!/usr/bin/env bash
#
# patch-shell-theme.sh
#
# Purpose:
#   Appends brand CSS to GNOME Shell's built-in theme resource. The login
#   screen (GDM) and the lock screen both render with this default theme and
#   ignore user themes, so patching the resource is the only way to brand
#   their colors, fonts and the lock-screen header.
#
# Inputs:
#   /usr/share/shatteredvales/brand.env
#   /usr/share/shatteredvales/theme/shell-overrides.css.in
#
# Usage:
#   Run by the BlueBuild script module during the image build.
#
# Exit codes:
#   Non-zero if the resource cannot be extracted or rebuilt; shipping a
#   half-written gresource would break the login screen.

set -euo pipefail

# shellcheck source=/dev/null
source /usr/share/shatteredvales/brand.env

readonly GRESOURCE=/usr/share/gnome-shell/gnome-shell-theme.gresource
readonly PREFIX=/org/gnome/shell/theme
readonly TEMPLATE=/usr/share/shatteredvales/theme/shell-overrides.css.in

# hex_to_rgb
#   Converts a #rrggbb colour into the "r, g, b" form used inside rgba().
#   Arguments: $1 colour in #rrggbb form
#   Output: "r, g, b" on stdout
#   Returns: 0 always
hex_to_rgb() {
    local hex="${1#\#}"
    printf '%d, %d, %d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# render_css
#   Substitutes every @BRAND_*@ placeholder in the CSS template with the
#   matching brand.env value, plus the derived @BRAND_ACCENT_RGB@. Fails if
#   any placeholder is left, so a typo can never ship unstyled.
#   Arguments: none
#   Output: rendered CSS on stdout
#   Returns: non-zero if a placeholder has no matching brand value
render_css() {
    local BRAND_ACCENT_RGB css var
    # Read through the ${!var} indirection below, which shellcheck cannot see.
    # shellcheck disable=SC2034
    BRAND_ACCENT_RGB="$(hex_to_rgb "${BRAND_ACCENT}")"
    css="$(<"${TEMPLATE}")"
    for var in $(compgen -v BRAND_); do
        css="${css//@${var}@/${!var}}"
    done
    if grep -o '@BRAND_[A-Z_]*@' <<<"${css}"; then
        echo "Unresolved placeholders in ${TEMPLATE}" >&2
        return 1
    fi
    printf '%s\n' "${css}"
}

# main
#   Extracts the shell theme resource, appends the brand CSS to every
#   stylesheet in it and recompiles it in place.
#   Arguments: none
#   Returns: non-zero on any failure
main() {
    # glib2-devel provides the gresource tooling. If an earlier module already
    # installed it (the desktop-app headers depend on it), it must stay;
    # otherwise it is removed again below so build-only tools never reach
    # machines. Removing it unconditionally would also remove every
    # -devel package that depends on it.
    local installed_here=0
    if ! rpm -q glib2-devel >/dev/null; then
        dnf -y install glib2-devel
        installed_here=1
    fi

    local work css
    work="$(mktemp -d)"
    css="$(render_css)"

    local res
    while read -r res; do
        mkdir -p "${work}$(dirname "${res}")"
        gresource extract "${GRESOURCE}" "${res}" > "${work}${res}"
    done < <(gresource list "${GRESOURCE}")

    # GNOME ships separate light, dark and high-contrast stylesheets; the
    # login and lock screens may use any of them.
    local sheet patched=0
    for sheet in "${work}${PREFIX}"/gnome-shell*.css; do
        printf '\n/* Shattered Vales branding */\n%s\n' "${css}" >> "${sheet}"
        patched=$((patched + 1))
    done
    if (( patched == 0 )); then
        echo "No gnome-shell*.css found in ${GRESOURCE}; GNOME layout changed" >&2
        exit 1
    fi

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo "<gresources><gresource prefix=\"${PREFIX}\">"
        (cd "${work}${PREFIX}" && find . -type f -printf '<file>%P</file>\n' | sort)
        echo '</gresource></gresources>'
    } > "${work}/theme.gresource.xml"

    glib-compile-resources --sourcedir="${work}${PREFIX}" \
        --target="${GRESOURCE}" "${work}/theme.gresource.xml"

    rm -rf "${work}"
    if (( installed_here )); then
        dnf -y remove glib2-devel
    fi
    echo "Patched ${patched} shell stylesheet(s)"
}

main "$@"
