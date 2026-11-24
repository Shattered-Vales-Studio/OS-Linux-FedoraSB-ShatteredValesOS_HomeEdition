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

# latest_tag
#   Prints the tag of the latest release by following GitHub's
#   /releases/latest web redirect. Unlike the REST API, this is not subject
#   to the anonymous API rate limit that CI runners share, which failed
#   builds with HTTP 403.
#   Arguments: none
#   Output: the tag, for example v0.19.2
#   Returns: non-zero if GitHub cannot be reached
latest_tag() {
    local url
    url="$(curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 -o /dev/null \
        -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")" || return 1
    [[ "${url}" == */releases/tag/* ]] || return 1
    printf '%s' "${url##*/}"
}

# find_rpm_url
#   Prints the download URL of the latest x86_64 RPM. The asset name is
#   built from the release tag (artcraft-launcher-<version>-linux-x86_64.rpm);
#   if that file is missing, for example after an upstream rename, the REST
#   API's asset list is used instead.
#   Arguments: none
#   Output: asset URL on stdout
#   Returns: non-zero if no asset could be found
find_rpm_url() {
    local tag url auth=()
    if tag="$(latest_tag)"; then
        url="https://github.com/${REPO}/releases/download/${tag}/artcraft-launcher-${tag#v}-linux-x86_64.rpm"
        if curl -fsSL --retry 3 --retry-delay 5 -o /dev/null -r 0-0 "${url}"; then
            printf '%s\n' "${url}"
            return 0
        fi
    fi
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 15 "${auth[@]}" \
        "https://api.github.com/repos/${REPO}/releases/latest" \
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
