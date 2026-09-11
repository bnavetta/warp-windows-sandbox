#!/usr/bin/env bash

arc_is_configured() {
    local name

    for name in \
        ARC_TENANT_ID \
        ARC_SP_ID \
        ARC_SP_SECRET \
        ARC_SUBSCRIPTION \
        ARC_RESOURCE_GROUP; do
        [[ -n ${!name:-} ]] || return 1
    done
}

arc_resource_name() {
    # Must be unique per sandbox (the VM UUID is deliberately fixed), so default
    # to the container hostname.
    if [[ -n ${ARC_RESOURCE_NAME:-} ]]; then
        printf '%s\n' "$ARC_RESOURCE_NAME"
    else
        printf 'windows-sandbox-%s\n' "$(hostname)"
    fi
}

arc_connect_hook() {
    local command
    local resource_name

    arc_is_configured || return 0
    resource_name=$(arc_resource_name)
    log "connecting guest to Azure Arc as $resource_name"
    command="azcmagent connect"
    command+=" --tenant-id $(powershell_quote "$ARC_TENANT_ID")"
    command+=" --service-principal-id $(powershell_quote "$ARC_SP_ID")"
    command+=" --service-principal-secret $(powershell_quote "$ARC_SP_SECRET")"
    command+=" --subscription-id $(powershell_quote "$ARC_SUBSCRIPTION")"
    command+=" --resource-group $(powershell_quote "$ARC_RESOURCE_GROUP")"
    command+=" --location $(powershell_quote "${ARC_LOCATION:-eastus}")"
    command+=" --resource-name $(powershell_quote "$resource_name")"
    command+=" --tags $(powershell_quote "windows-sandbox=true,sandbox-id=$resource_name")"
    vm_ssh "$VM_SSH_USER" 120 "$command"
}

arc_disconnect_hook() {
    local command

    arc_is_configured || return 0
    log "disconnecting guest from Azure Arc"
    # Disconnect with credentials so the Azure resource is deleted rather than
    # orphaned. scripts/arc-sweep.sh cleans up anything left by unclean exits.
    command="azcmagent disconnect"
    command+=" --service-principal-id $(powershell_quote "$ARC_SP_ID")"
    command+=" --service-principal-secret $(powershell_quote "$ARC_SP_SECRET")"
    vm_ssh "$VM_SSH_USER" 120 "$command"
}
