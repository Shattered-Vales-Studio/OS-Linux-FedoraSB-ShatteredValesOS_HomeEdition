#!/usr/bin/env bash
#
# grub-theme.sh
#
# Purpose:
#   Installs the Shattered Vales OS boot menu theme. Image-based Fedora boots
#   through bootupd's fixed GRUB configuration, which lives in /boot (outside
#   the image) and sources /boot/grub2/custom.cfg last, so the theme files
#   are copied to /boot/grub2/themes/shatteredvales and custom.cfg gets a
#   marked block that loads them. Files are only rewritten when the image's
#   theme has changed; anything else in custom.cfg is left alone. If the
#   theme cannot load (no graphics mode, missing fonts), GRUB shows its
#   plain menu and boots as usual.
#
# Usage:
#   Run at boot by shatteredvales-grub-theme.service.
#
# Exit codes:
#   0 on success or when there is no GRUB in /boot; 1 on a copy failure.

set -euo pipefail

readonly SOURCE=/usr/share/shatteredvales/grub-theme
readonly GRUB=/boot/grub2
readonly TARGET="${GRUB}/themes/shatteredvales"
readonly CUSTOM="${GRUB}/custom.cfg"
readonly BEGIN="# >>> shatteredvales boot menu theme >>>"
readonly END="# <<< shatteredvales boot menu theme <<<"

# install_files
#   Copies the theme into /boot when it differs, replacing the old copy in
#   one rename so GRUB never sees a half-written theme.
#   Arguments: none
#   Returns: non-zero if the copy fails
install_files() {
    if diff -rq "${SOURCE}" "${TARGET}" >/dev/null 2>&1; then
        return 0
    fi
    rm -rf "${TARGET}.new"
    mkdir -p "${GRUB}/themes"
    cp -r "${SOURCE}" "${TARGET}.new"
    rm -rf "${TARGET}"
    mv "${TARGET}.new" "${TARGET}"
    echo "Installed the boot menu theme in ${TARGET}"
}

# install_hook
#   Adds the block that loads the theme to custom.cfg once. The check for
#   theme.cfg keeps GRUB quiet if the theme is ever removed.
#   Arguments: none
#   Returns: 0 always
install_hook() {
    if grep -qxF "${BEGIN}" "${CUSTOM}" 2>/dev/null; then
        return 0
    fi
    # GRUB's own variables ($prefix) must reach the file unexpanded.
    # shellcheck disable=SC2016
    printf '%s\n' "${BEGIN}" \
        'if [ -f "$prefix/themes/shatteredvales/theme.cfg" ]; then' \
        '  source "$prefix/themes/shatteredvales/theme.cfg"' \
        'fi' \
        "${END}" >> "${CUSTOM}"
    echo "Enabled the boot menu theme in ${CUSTOM}"
}

# main
#   Installs the theme when this machine boots through GRUB in /boot.
#   Arguments: none
#   Returns: 0 unless copying fails
main() {
    [[ -d "${GRUB}" && -d "${SOURCE}" ]] || exit 0
    install_files
    install_hook
}

main "$@"
