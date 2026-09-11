#!/usr/bin/env bash

log() {
    printf '[windows-vm] %s\n' "$*" >&2
}

warn() {
    printf '[windows-vm] warning: %s\n' "$*" >&2
}

die() {
    printf '[windows-vm] error: %s\n' "$*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

resolve_state_dir() {
    if [[ -n ${VM_STATE_DIR:-} && $VM_STATE_DIR != /run/windows-vm ]]; then
        printf '%s\n' "$VM_STATE_DIR"
        return
    fi

    if [[ -d /run && -w /run ]]; then
        printf '%s\n' /run/windows-vm
    else
        printf '%s\n' /tmp/windows-vm
    fi
}

resolve_cache_dir() {
    if [[ -n ${VM_CACHE_DIR:-} ]]; then
        printf '%s\n' "$VM_CACHE_DIR"
    elif [[ -n ${WARP_BUILD_CACHE_ROOT:-} ]]; then
        printf '%s/windows\n' "${WARP_BUILD_CACHE_ROOT%/}"
    else
        return 1
    fi
}

require_image_version() {
    [[ -n ${VM_IMAGE_VERSION:-} ]] ||
        die "VM_IMAGE_VERSION must be set (for example, 20260911)"
}

image_filename() {
    require_image_version
    printf 'win-base-%s.qcow2\n' "$VM_IMAGE_VERSION"
}

image_path() {
    local cache_dir

    cache_dir=$(resolve_cache_dir) ||
        die "set VM_CACHE_DIR or WARP_BUILD_CACHE_ROOT before using the image cache"
    printf '%s/%s\n' "${cache_dir%/}" "$(image_filename)"
}

validate_forward_spec() {
    local spec=${1:-}
    local host_port
    local guest_port

    [[ $spec =~ ^([0-9]+):([0-9]+)$ ]] || return 1
    host_port=${BASH_REMATCH[1]}
    guest_port=${BASH_REMATCH[2]}
    ((host_port >= 1 && host_port <= 65535)) || return 1
    ((guest_port >= 1 && guest_port <= 65535)) || return 1
}

forward_host_port() {
    validate_forward_spec "$1" || return 1
    printf '%s\n' "${1%%:*}"
}

forward_guest_port() {
    validate_forward_spec "$1" || return 1
    printf '%s\n' "${1##*:}"
}

pid_is_running() {
    local pid_file=$1
    local pid

    [[ -s $pid_file ]] || return 1
    read -r pid <"$pid_file"
    [[ $pid =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

safe_remove_state_dir() {
    local state_dir=$1

    [[ -n $state_dir && $state_dir != / && $state_dir != /tmp && $state_dir != /run ]] ||
        die "refusing to remove unsafe state directory: $state_dir"
    rm -rf -- "$state_dir"
}

sha256_file() {
    if command_exists sha256sum; then
        sha256sum "$1" | awk '{print $1}'
    elif command_exists shasum; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        die "sha256sum or shasum is required to verify the VM image"
    fi
}

prepare_ssh_key() {
    local source_key=$1
    local destination_key=$2

    [[ -f $source_key ]] || die "SSH private key not found: $source_key"
    cp "$source_key" "$destination_key"
    chmod 0600 "$destination_key"
}

qmp_exchange() {
    local socket=$1
    local command_json=$2
    local payload

    [[ -S $socket ]] || die "QMP socket is unavailable: $socket"
    payload=$(printf '%s\n%s\n' '{"execute":"qmp_capabilities"}' "$command_json")

    if command_exists socat; then
        printf '%s\n' "$payload" | socat -t 2 - "UNIX-CONNECT:$socket"
        return
    fi

    if { exec 9<>"/dev/unix/$socket"; } 2>/dev/null; then
        printf '%s\n' "$payload" >&9
        while IFS= read -r -t 2 line <&9; do
            printf '%s\n' "$line"
        done
        exec 9>&-
        return
    fi

    die "socat is required to communicate with QEMU QMP"
}

qmp_execute() {
    local socket=$1
    local execute=$2
    local arguments=${3:-}
    local command_json
    local response

    if [[ -n $arguments ]]; then
        command_json=$(jq -cn \
            --arg execute "$execute" \
            --argjson arguments "$arguments" \
            '{execute: $execute, arguments: $arguments}')
    else
        command_json=$(jq -cn --arg execute "$execute" '{execute: $execute}')
    fi
    response=$(qmp_exchange "$socket" "$command_json")
    if jq -e 'select(.error != null)' <<<"$response" >/dev/null; then
        die "QMP command '$execute' failed: $response"
    fi
    printf '%s\n' "$response"
}

qmp_human_command() {
    local socket=$1
    local command_line=$2
    local arguments

    arguments=$(jq -cn --arg command_line "$command_line" \
        '{"command-line": $command_line}')
    qmp_execute "$socket" human-monitor-command "$arguments"
}

shell_join() {
    local output=
    local value

    for value in "$@"; do
        output+="${output:+ }$value"
    done
    printf '%s\n' "$output"
}

powershell_quote() {
    local value=${1//\'/\'\'}
    printf "'%s'" "$value"
}
