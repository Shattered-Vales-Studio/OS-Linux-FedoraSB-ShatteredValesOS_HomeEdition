#!/usr/bin/env bash
#
# install-artcraft-launcher.sh
#
# Purpose:
#   Installs the latest ArtCraft Launcher RPM from its GitHub releases into
#   the image. The project publishes no RPM repository, so the build resolves
#   the newest release itself. If the RPM installs into /opt, BlueBuild
#   relocates it into /usr/lib/opt automatically after the module runs.
#
# Usage:
#   Run by the BlueBuild script module during the image build.
#
# Inputs:
#   GITHUB_TOKEN (optional)  Raises the GitHub API rate limit in CI.
#
# Exit codes:
#   0 on success, non-zero if no matching release asset is found or the
#   install fails (the build must fail rather than ship without the app).

set -euo pipefail

readonly REPO="storytold/craft-launcher"
readonly ASSET_PATTERN='linux-x86_64\.rpm$'

# find_rpm_url
#   Queries the latest GitHub release and prints the download URL of the
#   x86_64 RPM asset.
#   Arguments: none
#   Output: asset URL on stdout
#   Returns: non-zero if the API call fails or no asset matches
find_rpm_url() {
    local auth=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    curl -fsSL "${auth[@]}" "https://api.github.com/repos/${REPO}/releases/latest" \
        | jq -r --arg pat "${ASSET_PATTERN}" \
            '.assets[] | select(.name | test($pat)) | .browser_download_url' \
        | head -n1
}

# main
#   Resolves the newest x86_64 RPM and installs it.
#   Arguments: none
#   Returns: non-zero if no asset is found or the install fails
main() {
    local url
    url="$(find_rpm_url)"
    if [[ -z "${url}" ]]; then
        echo "No RPM matching ${ASSET_PATTERN} in the latest ${REPO} release" >&2
        exit 1
    fi
    echo "Installing ArtCraft Launcher from ${url}"
    dnf -y install "${url}"
}

main "$@"
