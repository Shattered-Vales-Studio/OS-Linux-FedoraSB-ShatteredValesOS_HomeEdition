#!/usr/bin/env bash
#
# signed-switch.sh
#
# Purpose:
#   Finishes a migration onto Shattered Vales OS. A machine moved over with
#   sv-migrate.sh (or the README's manual command) first boots the image
#   from `ostree-unverified-registry:`, because a stock Fedora machine does
#   not have the image's signing key yet. Once booted the image has it, so
#   this switches the machine to the signature-verified reference for the
#   same image and channel. The switch is staged for the next restart; the
#   layers are already on disk, so it downloads almost nothing.
#
# Usage:
#   Run at boot by shatteredvales-signed-switch.service.
#
# Exit codes:
#   0 when nothing needs doing or the switch is staged, 1 if staging failed
#   (the service retries at the next boot).

set -euo pipefail

readonly PREFIX="ostree-unverified-registry:ghcr.io/shattered-vales-studio/"

# main
#   Stages a rebase to the signed reference when the booted deployment uses
#   the unverified one and nothing has already been staged for it.
#   Arguments: none
#   Returns: rpm-ostree's exit status, or 0 when nothing needs doing
main() {
    local status booted staged target
    status="$(rpm-ostree status --json)"
    booted="$(jq -r '.deployments[] | select(.booted) | ."container-image-reference" // empty' <<<"${status}")"
    [[ "${booted}" == "${PREFIX}"* ]] || exit 0

    target="ostree-image-signed:docker://${booted#ostree-unverified-registry:}"
    staged="$(jq -r '.deployments[] | select(.staged) | ."container-image-reference" // empty' <<<"${status}")"
    if [[ "${staged}" == ostree-image-signed:* ]]; then
        echo "Already staged: ${staged}"
        exit 0
    fi
    echo "Switching ${booted} to ${target}"
    rpm-ostree rebase "${target}"
}

main "$@"
