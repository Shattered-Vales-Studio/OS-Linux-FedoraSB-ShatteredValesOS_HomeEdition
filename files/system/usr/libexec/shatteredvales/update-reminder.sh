#!/usr/bin/env bash
#
# update-reminder.sh
#
# Purpose:
#   Reminds the signed-in user to reboot when an OS update has been
#   downloaded and staged for several days. Updates are staged silently in
#   the background and only take effect at the next reboot, so a machine
#   that is never restarted would otherwise never receive security fixes.
#
# Usage:
#   Run daily by the shatteredvales-update-reminder.timer user unit.
#
# Inputs:
#   SV_REMIND_AFTER_DAYS (optional)  Days an update may wait before the
#                                    reminder appears. Default 3.
#
# Exit codes:
#   0 always; a reminder that cannot be shown is not an error.

set -euo pipefail

readonly REMIND_AFTER_DAYS="${SV_REMIND_AFTER_DAYS:-3}"

# staged_update_age_days
#   Prints how many days old the staged image is, based on its build
#   timestamp. Nightly builds are staged within hours of being built, so
#   this closely tracks how long the update has been waiting.
#   Arguments: none
#   Output: whole days on stdout
#   Returns: 1 if no update is staged
staged_update_age_days() {
    local built
    built="$(rpm-ostree status --json | jq -er '.deployments[] | select(.staged == true) | .timestamp')" || return 1
    echo $(( ($(date +%s) - built) / 86400 ))
}

# main
#   Shows a notification when a staged update is older than the threshold.
#   Arguments: none
#   Returns: 0 always
main() {
    local age
    age="$(staged_update_age_days)" || exit 0
    (( age >= REMIND_AFTER_DAYS )) || exit 0
    notify-send --app-name="Shattered Vales" --icon=shatteredvales-logo \
        --urgency=normal \
        "Restart to finish updating" \
        "An update has been ready for ${age} days. Save your work and restart when convenient, or run: sv-update" \
        || true
}

main "$@"
