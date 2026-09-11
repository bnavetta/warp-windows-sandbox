#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$repo_root/runtime/libexec/common.sh"
# shellcheck disable=SC1091
source "$repo_root/runtime/libexec/qemu-args.sh"

tests_run=0

fail() {
    printf 'not ok %s - %s\n' "$tests_run" "$*" >&2
    exit 1
}
test_state_dir_preserves_explicit_value() {
    local actual

    actual=$(VM_STATE_DIR=/custom/state resolve_state_dir)
    assert_equal /custom/state "$actual" "explicit state directory should be preserved"
}

assert_equal() {
    local expected=$1
    local actual=$2
    local message=$3

    [[ $actual == "$expected" ]] ||
        fail "$message (expected '$expected', got '$actual')"
}

assert_contains() {
    local haystack=$1
    local needle=$2
    local message=$3

    [[ $haystack == *"$needle"* ]] ||
        fail "$message (missing '$needle')"
}

run_test() {
    local name=$1
    shift

    tests_run=$((tests_run + 1))
    "$@" || fail "$name"
    printf 'ok %s - %s\n' "$tests_run" "$name"
}

test_cache_dir_prefers_explicit_value() {
    local actual

    actual=$(VM_CACHE_DIR=/custom/cache WARP_BUILD_CACHE_ROOT=/warp/cache resolve_cache_dir)
    assert_equal /custom/cache "$actual" "VM_CACHE_DIR should take precedence"
}

test_cache_dir_uses_warp_root() {
    local actual

    actual=$(unset VM_CACHE_DIR; WARP_BUILD_CACHE_ROOT=/build-cache/ resolve_cache_dir)
    assert_equal /build-cache/windows "$actual" "Warp cache root should gain windows suffix"
}

test_cache_dir_requires_configuration() {
    if (unset VM_CACHE_DIR WARP_BUILD_CACHE_ROOT; resolve_cache_dir >/dev/null); then
        return 1
    fi
}

test_image_path_uses_version() {
    local actual
    # shellcheck disable=SC2034

    actual=$(
        VM_CACHE_DIR=/cache
        VM_IMAGE_VERSION=20260911
        image_path
    )
    assert_equal /cache/win-base-20260911.qcow2 "$actual" \
        "image path should include the configured version"
}

test_forward_spec_accepts_valid_ports() {
    validate_forward_spec 18080:8080
    assert_equal 18080 "$(forward_host_port 18080:8080)" "host port parsing"
    assert_equal 8080 "$(forward_guest_port 18080:8080)" "guest port parsing"
}

test_forward_spec_rejects_invalid_ports() {
    local spec

    for spec in 0:80 80:0 65536:80 80:65536 abc:80 80 80:90:100; do
        if validate_forward_spec "$spec"; then
            return 1
        fi
    done
}

test_qemu_args_construct_expected_devices() {
    local joined
    # These globals are consumed by the sourced QEMU argument builder.
    # shellcheck disable=SC2034

    VM_SSH_PORT=2222
    VM_UUID=7b7f3b1e-6b3e-4f2a-9c1a-2d0e8a5c4f01
    VM_MAC=52:54:00:12:34:56
    VM_SMBIOS_SERIAL=WINSANDBOX-0001
    VM_OVMF_CODE_RESOLVED=/firmware/code.fd
    VM_OVMF_VARS_RUNTIME=/state/vars.fd
    VM_OVERLAY=/state/overlay.qcow2
    VM_QMP_SOCKET=/state/qmp.sock
    VM_SERIAL_LOG=/state/serial.log
    VM_PID_FILE=/state/qemu.pid

    build_qemu_args 4 6G none 13389:3389 15985:5985 18080:8080
    printf -v joined ' %s' "${QEMU_ARGS[@]}"
    assert_contains "$joined" '-machine q35,accel=kvm' "KVM q35 machine"
    assert_contains "$joined" '-smp 4' "CPU count"
    assert_contains "$joined" '-m 6G' "memory size"
    assert_contains "$joined" '-uuid 7b7f3b1e-6b3e-4f2a-9c1a-2d0e8a5c4f01' "fixed UUID"
    assert_contains "$joined" '-smbios type=1,serial=WINSANDBOX-0001' \
        "fixed SMBIOS serial"
    assert_contains "$joined" \
        'hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:13389-:3389,hostfwd=tcp:127.0.0.1:15985-:5985,hostfwd=tcp:127.0.0.1:18080-:8080' \
        "slirp forwards"
    assert_contains "$joined" '-device virtio-blk-pci,drive=osdisk' "virtio disk"
    assert_contains "$joined" '-device virtio-net-pci,netdev=n0,mac=52:54:00:12:34:56' \
        "fixed virtio NIC"
    assert_contains "$joined" '-display none' "headless display"
}

test_qemu_args_enable_vnc() {
    local joined

    build_qemu_args 2 4G vnc
    printf -v joined ' %s' "${QEMU_ARGS[@]}"
    assert_contains "$joined" '-vnc 127.0.0.1:0' "loopback VNC"
    [[ $joined != *'-display none'* ]]
}

run_test "cache dir prefers VM_CACHE_DIR" test_cache_dir_prefers_explicit_value
run_test "state dir preserves explicit override" test_state_dir_preserves_explicit_value
run_test "cache dir derives from WARP_BUILD_CACHE_ROOT" test_cache_dir_uses_warp_root
run_test "cache dir rejects missing configuration" test_cache_dir_requires_configuration
run_test "image path includes image version" test_image_path_uses_version
run_test "forward parser accepts valid ports" test_forward_spec_accepts_valid_ports
run_test "forward parser rejects invalid ports" test_forward_spec_rejects_invalid_ports
run_test "QEMU args include identity, devices, and forwards" test_qemu_args_construct_expected_devices
run_test "QEMU args select VNC" test_qemu_args_enable_vnc

printf '1..%s\n' "$tests_run"
