#!/usr/bin/env bash
# Usage: ./scripts/repo/report-runtime-support-windows.sh [--as-of YYYY-MM-DD] [--file PATH]
#
# Prints every runtime line in scripts/lib/runtime-support-windows.txt whose
# support end date has passed (PAST) or falls within 90 days (DUE), relative to
# --as-of (default: today, UTC). Uses no network; a person keeps the dates
# current during the quarterly review in docs/dependency-automation.md.
#
# Exit status: 0 when nothing is flagged, 1 when a line is flagged, 2 for a
# usage error or malformed inventory. It is a review aid, not a release gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SCRIPT_DIR}/../lib/runtime-support-windows.txt"
WINDOW_DAYS=90
AS_OF="$(date -u +%F)"

usage() {
    sed -n '2,10s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 2
}

# Prints the day number (days since the epoch) of a strict YYYY-MM-DD date.
day_number() {
    local value="$1" seconds
    [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    seconds=$(date -u -d "${value} 00:00:00" +%s 2>/dev/null) || return 1
    [[ "$(date -u -d "@${seconds}" +%F)" == "$value" ]] || return 1
    printf '%s\n' "$((seconds / 86400))"
}

while (($# > 0)); do
    case "$1" in
        --as-of)
            (($# >= 2)) || die "--as-of requires a date"
            AS_OF="$2"
            shift 2
            ;;
        --file)
            (($# >= 2)) || die "--file requires a path"
            INVENTORY="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

today=$(day_number "$AS_OF") || die "--as-of must be a valid YYYY-MM-DD date: ${AS_OF}"
[[ -f "$INVENTORY" ]] || die "inventory not found: ${INVENTORY}"

entries=0
flagged=0
line_no=0
while IFS= read -r row || [[ -n "$row" ]]; do
    line_no=$((line_no + 1))
    [[ -z "${row//[[:space:]]/}" || "$row" == \#* ]] && continue

    # Tab is IFS whitespace, so split on a non-whitespace separator to keep
    # empty columns in place.
    IFS=$'\x1f' read -r runtime line support_end selected_in source _note <<<"${row//$'\t'/$'\x1f'}"
    for field in runtime line support_end selected_in source; do
        [[ -n "${!field:-}" ]] || die "${INVENTORY}:${line_no}: missing ${field}"
    done
    [[ "$source" == https://* ]] || die "${INVENTORY}:${line_no}: source must be an https URL"
    end=$(day_number "$support_end") \
        || die "${INVENTORY}:${line_no}: support_end must be a valid YYYY-MM-DD date: ${support_end}"
    entries=$((entries + 1))

    remaining=$((end - today))
    if ((remaining < 0)); then
        printf 'PAST  %s %s: support ended %s (%d days ago)\n' \
            "$runtime" "$line" "$support_end" "$((-remaining))"
    elif ((remaining <= WINDOW_DAYS)); then
        printf 'DUE   %s %s: support ends %s (in %d days)\n' \
            "$runtime" "$line" "$support_end" "$remaining"
    else
        continue
    fi
    printf '      selected in: %s\n      source: %s\n' "$selected_in" "$source"
    flagged=$((flagged + 1))
done <"$INVENTORY"

((entries > 0)) || die "${INVENTORY}: no runtime lines found"

printf '%d of %d runtime lines past or within %d days of support end as of %s.\n' \
    "$flagged" "$entries" "$WINDOW_DAYS" "$AS_OF"
((flagged == 0))
