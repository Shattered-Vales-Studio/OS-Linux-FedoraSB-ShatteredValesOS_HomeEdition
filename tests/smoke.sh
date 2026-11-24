#!/usr/bin/env bash
#
# smoke.sh
#
# Purpose:
#   Fast checks against a built image without booting it. Runs the image as
#   a container and inspects its filesystem, which works on macOS where the
#   x86_64 OS itself cannot be booted.
#
# Usage:
#   tests/smoke.sh <image-ref>
#
# Exit codes:
#   0 when all checks pass, 1 otherwise.

set -euo pipefail

readonly IMAGE="${1:?usage: smoke.sh <image-ref>}"

# Counts the branding marker in each GNOME Shell stylesheet; exits non-zero
# unless every one has it exactly once.
readonly THEME_CHECK='
from gi.repository import Gio
r = Gio.Resource.load("/usr/share/gnome-shell/gnome-shell-theme.gresource")
p = "/org/gnome/shell/theme/"
sheets = [n for n in r.enumerate_children(p, 0) if n.startswith("gnome-shell") and n.endswith(".css")]
counts = {n: r.lookup_data(p + n, 0).get_data().count(b"Shattered Vales branding") for n in sheets}
print(counts)
raise SystemExit(0 if sheets and all(c == 1 for c in counts.values()) else 1)
'

# in_image
#   Runs a shell snippet inside the image.
#   Arguments: $1 command string
#   Returns: the command's exit status
in_image() {
    docker run --rm --platform linux/amd64 "${IMAGE}" bash -c "$1"
}

# main
#   Runs every smoke check against the image and reports the result.
#   Arguments: none (the image comes from IMAGE)
#   Returns: 0 when all checks pass, 1 otherwise
main() {
    local failed=0

    echo "-> bootc container lint"
    in_image 'bootc container lint' || failed=1

    echo "-> branding applied to os-release"
    in_image 'grep -q "^NAME=\"Shattered Vales OS\"" /usr/lib/os-release' || failed=1

    echo "-> edition recorded in os-release"
    in_image 'grep -q "^VARIANT=\"Home Edition\"" /usr/lib/os-release' || failed=1

    echo "-> no developer tooling or app folders"
    in_image '! rpm -q docker-ce code nodejs26 >/dev/null 2>&1 && test ! -e /etc/dconf/db/local.d/20-shatteredvales-app-folders' || failed=1

    echo "-> every shell stylesheet carries the brand CSS exactly once"
    # GNOME Shell's theme holds one stylesheet per variant (dark, light,
    # high contrast) and each gets the branding. Exactly once, because
    # editions re-run Core's patch and it must replace Core's branding
    # rather than add a second copy. Read with GIO, since the gresource
    # tooling is removed from the image after patching.
    in_image "python3 -I -c '${THEME_CHECK}'" || failed=1

    echo "-> Home's edition name replaced Core's in the banners and About logo"
    in_image 'grep -q "Home Edition" /etc/issue.d/50-shatteredvales.issue && grep -q "Home Edition" /usr/lib/motd.d/50-shatteredvales && ! grep -rq "Core Edition" /etc/issue.d /usr/lib/motd.d' \
        || failed=1

    echo "-> Home's desktop defaults layered over Core's"
    in_image 'test -s /etc/dconf/db/local.d/10-shatteredvales-desktop && test -s /etc/dconf/db/local.d/50-shatteredvales-home' \
        || failed=1

    echo "-> dconf defaults compiled with brand values"
    in_image 'test -s /etc/dconf/db/local && test -s /etc/dconf/db/gdm && ! grep -rq "@BRAND_" /etc/dconf/db/local.d /etc/dconf/db/gdm.d' || failed=1

    echo "-> Plymouth theme baked into initramfs"
    in_image 'lsinitrd /usr/lib/modules/*/initramfs.img | grep -q "plymouth/themes/shatteredvales"' || failed=1

    echo "-> no unrendered placeholders anywhere in /usr/share/shatteredvales"
    in_image '! grep -rq "@BRAND_" /usr/share/plymouth/themes/shatteredvales' || failed=1

    if (( failed )); then
        echo "SMOKE TESTS FAILED" >&2
        exit 1
    fi
    echo "All smoke tests passed"
}

main "$@"
