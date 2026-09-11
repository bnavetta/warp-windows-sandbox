#!/usr/bin/env bash
set -euo pipefail

resource_group=${ARC_RESOURCE_GROUP:-}
older_than_hours=24
dry_run=true

usage() {
    cat <<'EOF'
Usage: scripts/arc-sweep.sh --resource-group GROUP [options]

Delete stale Azure Arc machines tagged windows-sandbox=true.

Options:
  --older-than-hours N   Minimum disconnected age (default: 24)
  --execute              Perform deletions (default is dry-run)
  --dry-run              Print candidates without deleting
  -h, --help             Show this help
EOF
}

while (($#)); do
    case $1 in
        --resource-group)
            (($# >= 2)) || {
                printf 'error: --resource-group requires a value\n' >&2
                exit 2
            }
            resource_group=$2
            shift 2
            ;;
        --older-than-hours)
            (($# >= 2)) || {
                printf 'error: --older-than-hours requires a value\n' >&2
                exit 2
            }
            older_than_hours=$2
            shift 2
            ;;
        --execute)
            dry_run=false
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ -n $resource_group ]] || {
    printf 'error: set ARC_RESOURCE_GROUP or pass --resource-group\n' >&2
    exit 2
}
[[ $older_than_hours =~ ^[1-9][0-9]*$ ]] || {
    printf 'error: --older-than-hours must be a positive integer\n' >&2
    exit 2
}
command -v az >/dev/null 2>&1 || {
    printf 'error: Azure CLI (az) is required\n' >&2
    exit 2
}
command -v jq >/dev/null 2>&1 || {
    printf 'error: jq is required\n' >&2
    exit 2
}

cutoff_epoch=$(($(date -u +%s) - older_than_hours * 3600))
machines_json=$(az connectedmachine list --resource-group "$resource_group" --output json)
candidate_count=0

while IFS=$'\t' read -r name status changed_at; do
    [[ -n $name && -n $changed_at ]] || continue
    if changed_epoch=$(date -u -d "$changed_at" +%s 2>/dev/null); then
        :
    elif changed_epoch=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$changed_at" +%s 2>/dev/null); then
        :
    else
        printf 'warning: cannot parse status timestamp for %s: %s\n' "$name" "$changed_at" >&2
        continue
    fi
    ((changed_epoch < cutoff_epoch)) || continue
    candidate_count=$((candidate_count + 1))
    if [[ $dry_run == true ]]; then
        printf 'Would delete %s (%s since %s)\n' "$name" "$status" "$changed_at"
    else
        printf 'Deleting %s (%s since %s)\n' "$name" "$status" "$changed_at"
        az connectedmachine delete \
            --name "$name" \
            --resource-group "$resource_group" \
            --yes \
            --output none
    fi
done < <(
    jq -r '
        .[]
        | select(.tags["windows-sandbox"] == "true")
        | select((.properties.status // .status) == "Disconnected"
            or (.properties.status // .status) == "Expired")
        | [
            .name,
            (.properties.status // .status),
            (.properties.lastStatusChange // .properties.lastConnectivityTime // "")
          ]
        | @tsv
    ' <<<"$machines_json"
)

if ((candidate_count == 0)); then
    printf 'No stale Windows sandbox Arc machines found.\n'
elif [[ $dry_run == true ]]; then
    printf '%s candidate(s) found; rerun with --execute to delete them.\n' "$candidate_count"
else
    printf 'Deleted %s stale Arc machine(s).\n' "$candidate_count"
fi
