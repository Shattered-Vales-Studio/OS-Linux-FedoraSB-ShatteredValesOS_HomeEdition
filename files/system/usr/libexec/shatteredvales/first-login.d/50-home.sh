# shellcheck shell=bash
#
# 50-home.sh
#
# Purpose:
#   Home Edition's per-person setup, sourced by Core's first-login.sh:
#   opens the Welcome window (text size, and Family Setup for
#   administrators) on a person's first login and copies the "Getting
#   Remote Help" guide into their Documents folder.
#
# Inputs:
#   Core's first-login.sh helpers and registration arrays (STATE_DIR,
#   documents_dir, LOGIN_HOOKS, STEPS).
#
# Usage:
#   Sourced by /usr/libexec/shatteredvales/first-login.sh; not run directly.
#
# Exit codes:
#   Not applicable; it only defines and registers functions.

readonly FAMILY_SETUP=/usr/libexec/shatteredvales/family-setup
readonly DOCS_DIR=/usr/share/shatteredvales/docs

# open_welcome
#   Opens the Welcome window once per person, without waiting for it, so
#   the installs that follow run while the person reads it. The window
#   records its own completion (welcome.done) when the person finishes or
#   chooses "Not now", so closing it early shows it again at the next login.
#   Arguments: none
#   Returns: 0 always
open_welcome() {
    [[ -f "${STATE_DIR}/welcome.done" ]] && return 0
    [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] || return 0
    setsid -f "${FAMILY_SETUP}" --welcome >/dev/null 2>&1 || true
}

# step_remote_help_doc
#   Copies the "Getting Remote Help" guide into the person's Documents
#   folder, where whoever helps them can find it. An existing copy is kept.
#   Arguments: none
#   Returns: cp exit status
step_remote_help_doc() {
    cp -n "${DOCS_DIR}/Getting Remote Help.html" "$(documents_dir)/"
}

LOGIN_HOOKS+=(open_welcome)
STEPS+=("remote-help-doc-v1 step_remote_help_doc")
