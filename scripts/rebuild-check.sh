#!/usr/bin/env bash
set -euo pipefail

version=${1:-${VM_IMAGE_VERSION:-}}
evaluation_days=180
warning_days=30

if [[ $version =~ ([0-9]{8}) ]]; then
    build_date=${BASH_REMATCH[1]}
else
    printf 'error: expected VM image version containing YYYYMMDD\n' >&2
    exit 2
fi

date_to_epoch() {
    local date_value=$1

    if date -u -d 19700101 +%s >/dev/null 2>&1; then
        date -u -d "$date_value" +%s
    else
        date -j -u -f %Y%m%d "$date_value" +%s
    fi
}

if ! build_epoch=$(date_to_epoch "$build_date" 2>/dev/null); then
    printf 'error: invalid build date in image version: %s\n' "$build_date" >&2
    exit 2
fi

now_epoch=$(date -u +%s)
elapsed_days=$(((now_epoch - build_epoch) / 86400))
remaining_days=$((evaluation_days - elapsed_days))

printf 'Image version: %s\n' "$version"
printf 'Build date: %s\n' "$build_date"
printf 'Evaluation days elapsed: %s\n' "$elapsed_days"
printf 'Evaluation days remaining: %s\n' "$remaining_days"

if ((remaining_days < warning_days)); then
    printf 'Rebuild required: fewer than %s days remain.\n' "$warning_days" >&2
    exit 1
fi
