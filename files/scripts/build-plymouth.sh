#!/usr/bin/env bash
#
# build-plymouth.sh
#
# Purpose:
#   Installs the branded boot splash and regenerates the initramfs so the
#   splash is actually shown. Plymouth runs from the initramfs, so changing
#   the theme without rebuilding it has no visible effect.
#
# Inputs:
#   /usr/share/shatteredvales/brand.env
#   /usr/share/plymouth/themes/shatteredvales/ (theme file + watermark.png)
#
# Exit codes:
#   Non-zero if the image does not contain exactly one kernel or dracut
#   fails; an unbootable initramfs must never be published.

set -euo pipefail

# shellcheck source=/dev/null
source /usr/share/shatteredvales/brand.env

readonly THEME_DIR=/usr/share/plymouth/themes/shatteredvales
readonly SPINNER_DIR=/usr/share/plymouth/themes/spinner

# single_kernel_version
#   Prints the one kernel version present in the image.
#   Returns: non-zero if zero or several kernels are installed
single_kernel_version() {
    local versions
    mapfile -t versions < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n')
    if (( ${#versions[@]} != 1 )); then
        echo "Expected one kernel, found: ${versions[*]:-none}" >&2
        return 1
    fi
    echo "${versions[0]}"
}

# main
#   Completes the theme, makes it the default and rebuilds the initramfs.
#   Arguments: none
#   Returns: non-zero if artwork is missing or dracut fails
main() {
    if [[ ! -f "${THEME_DIR}/watermark.png" ]]; then
        echo "Missing ${THEME_DIR}/watermark.png; run 'just branding' first" >&2
        exit 1
    fi

    # The two-step module needs throbber, entry and lock artwork. Reusing
    # Fedora's spinner set keeps disk-unlock prompts consistent with stock.
    local png
    for png in "${SPINNER_DIR}"/*.png; do
        [[ "$(basename "${png}")" == watermark.png ]] && continue
        cp -n "${png}" "${THEME_DIR}/"
    done

    local bg_hex="0x${BRAND_BG#\#}"
    sed -i "s|@BRAND_BG_HEX@|${bg_hex}|g" "${THEME_DIR}/shatteredvales.plymouth"

    plymouth-set-default-theme shatteredvales

    local kver
    kver="$(single_kernel_version)"
    # Extended attributes cannot be set in the build sandbox.
    export DRACUT_NO_XATTR=1
    dracut --no-hostonly --kver "${kver}" --reproducible --zstd -v \
        --add ostree -f "/usr/lib/modules/${kver}/initramfs.img"
    chmod 0600 "/usr/lib/modules/${kver}/initramfs.img"
}

main "$@"
