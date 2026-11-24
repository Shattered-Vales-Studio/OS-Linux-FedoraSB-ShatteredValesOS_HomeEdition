#!/usr/bin/env bash
#
# render-branding.sh
#
# Purpose:
#   Renders Home Edition's artwork with Core Edition's renderer, fonts and
#   logo, so every edition is drawn from one set of sources. Fetches (or
#   updates) a shallow copy of the Core Edition repository in build/core
#   and runs its scripts/render-branding.sh with this repository as the
#   target. Only edition-specific artwork is written into files/system;
#   everything else comes from Core's image.
#
# Inputs:
#   branding/brand.env, branding/icons/*.glyph
#   CORE_REF (optional environment variable): the Core branch or tag to
#   render with, default main.
#
# Usage:
#   scripts/render-branding.sh            (from the repo root, or `just branding`)
#
# Requirements:
#   git, and docker or podman on the host.
#
# Exit codes:
#   0 on success, non-zero if Core cannot be fetched or rendering fails.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly CORE_URL="https://github.com/Shattered-Vales-Studio/OS-Linux-FedoraSB-ShatteredValesOS_CoreEdition.git"
readonly CORE_DIR="${ROOT}/build/core"

# fetch_core
#   Clones Core into build/core, or updates an existing clone, at CORE_REF.
#   Arguments: none
#   Returns: git's exit status
fetch_core() {
    local ref="${CORE_REF:-main}"
    if [[ -d "${CORE_DIR}/.git" ]]; then
        git -C "${CORE_DIR}" fetch -q --depth 1 origin "${ref}"
        git -C "${CORE_DIR}" checkout -q --detach FETCH_HEAD
    else
        mkdir -p "$(dirname "${CORE_DIR}")"
        git clone -q --depth 1 --branch "${ref}" "${CORE_URL}" "${CORE_DIR}"
    fi
}

# main
#   Fetches Core and renders this repository's artwork with it.
#   Arguments: none
#   Returns: the renderer's exit status
main() {
    fetch_core
    "${CORE_DIR}/scripts/render-branding.sh" "${ROOT}"
}

main "$@"
