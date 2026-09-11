#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031
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

test_vm_resolves_source_tree_layout() {
    local output

    output=$(env -u VM_LIBEXEC -u VM_SSH_KEY "$repo_root/runtime/bin/vm" help)
    assert_contains "$output" "Usage: vm <command>" \
        "vm should load support files relative to its source-tree location"
}

test_start_failure_preserves_diagnostics() {
    local temporary

    temporary=$(mktemp -d)
    (
        export VM_LIBEXEC="$repo_root/runtime/libexec"
        export VM_STATE_DIR="$temporary"
        # shellcheck disable=SC1091
        source "$repo_root/runtime/bin/vm"

        printf 'QEMU diagnostic\n' >"$VM_QEMU_LOG"
        record_start_failure "simulated launch failure" 2>/dev/null

        assert_equal "simulated launch failure" "$(cat "$VM_FAILURE_FILE")" \
            "failure reason should be retained"
        assert_equal "QEMU diagnostic" "$(cat "$VM_QEMU_LOG")" \
            "QEMU log should be retained"
    )
    # shellcheck disable=SC2031
    rm -rf "$temporary"
}

test_run_dispatches_to_ssh() {
    local output

    output=$(
        export VM_LIBEXEC="$repo_root/runtime/libexec"
        # shellcheck disable=SC1091
        source "$repo_root/runtime/bin/vm"
        require_running() { :; }
        vm_ssh() {
            printf 'user=%s timeout=%s command=' "$1" "$2"
            shift 2
            printf '%s|' "$@"
        }

        command_run --transport ssh --user ssh-user --timeout 12 --shell cmd -- ver
    )
    assert_equal "user=ssh-user timeout=12 command=cmd.exe|/c|ver|" "$output" \
        "SSH transport should preserve its command path"
}

test_run_dispatches_to_winrm() {
    local output

    output=$(
        export VM_LIBEXEC="$repo_root/runtime/libexec"
        export VM_WINRM_USER=winrm-user
        # shellcheck disable=SC1091
        source "$repo_root/runtime/bin/vm"
        require_running() { :; }
        vm_winrm() {
            printf 'user=%s timeout=%s shell=%s script=' "$1" "$2" "$3"
            cat
        }

        command_run --transport winrm --timeout 25 -- Get-ComputerInfo
    )
    assert_equal \
        "user=winrm-user timeout=25 shell=pwsh script=Get-ComputerInfo" \
        "$output" "WinRM transport should use its default user and script runner"
}

test_run_uses_transport_environment_default() {
    local output

    output=$(
        export VM_LIBEXEC="$repo_root/runtime/libexec"
        export VM_TRANSPORT=winrm
        export VM_WINRM_USER=environment-user
        # shellcheck disable=SC1091
        source "$repo_root/runtime/bin/vm"
        require_running() { :; }
        vm_winrm() {
            printf '%s:%s:' "$1" "$3"
            cat
        }

        command_run -- Write-Output transport
    )
    assert_equal "environment-user:pwsh:Write-Output transport" "$output" \
        "VM_TRANSPORT should select WinRM"
}

test_winrm_runner_uses_password_file() {
    local cmd_output
    local output
    local temporary

    temporary=$(mktemp -d)
    mkdir -p "$temporary/winrm"
    cat >"$temporary/winrm/__init__.py" <<'PYTHON'
class Response:
    status_code = 0
    std_out = b"winrm output"
    std_err = b""


class Session:
    def __init__(self, endpoint, auth, **kwargs):
        assert endpoint == "http://127.0.0.1:15985/wsman"
        assert auth == ("Administrator", "test-password")
        assert kwargs["transport"] == "basic"

    def run_ps(self, script):
        assert script == "Get-Date"
        return Response()

    def run_cmd(self, command, arguments):
        assert command == "cmd.exe"
        assert arguments == ["/Q", "/D", "/C", "ver"]
        return Response()
PYTHON
    printf '%s\n' test-password >"$temporary/administrator_password"

    output=$(
        printf '%s' Get-Date |
            PYTHONPATH="$temporary" \
            VM_WINRM_PASSWORD_FILE="$temporary/administrator_password" \
            python3 "$repo_root/runtime/libexec/winrm-run.py" \
                --endpoint http://127.0.0.1:15985/wsman \
                --user Administrator \
                --shell pwsh
    )
    cmd_output=$(
        printf '%s' ver |
            PYTHONPATH="$temporary" \
            VM_WINRM_PASSWORD_FILE="$temporary/administrator_password" \
            python3 "$repo_root/runtime/libexec/winrm-run.py" \
                --endpoint http://127.0.0.1:15985/wsman \
                --user Administrator \
                --shell cmd
    )
    rm -rf "$temporary"
    assert_equal "winrm output" "$output" \
        "WinRM runner should authenticate from the embedded password file"
    assert_equal "winrm output" "$cmd_output" \
        "WinRM runner should dispatch cmd.exe scripts"
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
    assert_contains "$joined" \
        '-cpu host,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_time,hv_vpindex,hv_synic,hv_stimer' \
        "SynIC should include its VP_INDEX dependency"
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
run_test "vm resolves source-tree support files" test_vm_resolves_source_tree_layout
run_test "startup failure preserves diagnostics" test_start_failure_preserves_diagnostics
run_test "run dispatches commands to SSH" test_run_dispatches_to_ssh
run_test "run dispatches commands to WinRM" test_run_dispatches_to_winrm
run_test "run honors VM_TRANSPORT" test_run_uses_transport_environment_default
run_test "WinRM runner uses password file" test_winrm_runner_uses_password_file
run_test "state dir preserves explicit override" test_state_dir_preserves_explicit_value
run_test "cache dir derives from WARP_BUILD_CACHE_ROOT" test_cache_dir_uses_warp_root
run_test "cache dir rejects missing configuration" test_cache_dir_requires_configuration
run_test "image path includes image version" test_image_path_uses_version
run_test "forward parser accepts valid ports" test_forward_spec_accepts_valid_ports
run_test "forward parser rejects invalid ports" test_forward_spec_rejects_invalid_ports
run_test "QEMU args include identity, devices, and forwards" test_qemu_args_construct_expected_devices
run_test "QEMU args select VNC" test_qemu_args_enable_vnc

printf '1..%s\n' "$tests_run"
