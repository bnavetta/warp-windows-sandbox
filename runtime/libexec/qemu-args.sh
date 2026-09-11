#!/usr/bin/env bash

find_ovmf_code() {
    if [[ -n ${VM_OVMF_CODE:-} ]]; then
        printf '%s\n' "$VM_OVMF_CODE"
    elif [[ -f /usr/share/OVMF/OVMF_CODE_4M.fd ]]; then
        printf '%s\n' /usr/share/OVMF/OVMF_CODE_4M.fd
    else
        printf '%s\n' /usr/share/OVMF/OVMF_CODE.fd
    fi
}

find_ovmf_vars() {
    if [[ -n ${VM_OVMF_VARS:-} ]]; then
        printf '%s\n' "$VM_OVMF_VARS"
    elif [[ -f /usr/share/OVMF/OVMF_VARS_4M.fd ]]; then
        printf '%s\n' /usr/share/OVMF/OVMF_VARS_4M.fd
    else
        printf '%s\n' /usr/share/OVMF/OVMF_VARS.fd
    fi
}

build_qemu_args() {
    local cpus=$1
    local memory=$2
    local display_mode=$3
    shift 3
    local netdev="user,id=n0,hostfwd=tcp:127.0.0.1:${VM_SSH_PORT}-:22"
    local spec
    local host_port
    local guest_port

    for spec in "$@"; do
        host_port=$(forward_host_port "$spec") ||
            die "invalid port forward '$spec'; expected HOST_PORT:GUEST_PORT"
        guest_port=$(forward_guest_port "$spec")
        netdev+=",hostfwd=tcp:127.0.0.1:${host_port}-:${guest_port}"
    done

    QEMU_ARGS=(
        -name windows-sandbox
        -enable-kvm
        -machine "q35,accel=kvm"
        -cpu "host,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_time,hv_synic,hv_stimer"
        -smp "$cpus"
        -m "$memory"
        -uuid "$VM_UUID"
        -smbios "type=1,serial=$VM_SMBIOS_SERIAL"
        -drive "if=pflash,format=raw,readonly=on,file=$VM_OVMF_CODE_RESOLVED"
        -drive "if=pflash,format=raw,file=$VM_OVMF_VARS_RUNTIME"
        -drive "if=none,id=osdisk,format=qcow2,file=$VM_OVERLAY"
        -device "virtio-blk-pci,drive=osdisk"
        -netdev "$netdev"
        -device "virtio-net-pci,netdev=n0,mac=$VM_MAC"
        -qmp "unix:$VM_QMP_SOCKET,server,nowait"
        -serial "file:$VM_SERIAL_LOG"
        -pidfile "$VM_PID_FILE"
        -daemonize
    )

    if [[ $display_mode == vnc ]]; then
        QEMU_ARGS+=(-vnc 127.0.0.1:0)
    else
        QEMU_ARGS+=(-display none)
    fi
}
