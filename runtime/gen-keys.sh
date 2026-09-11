#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
key_dir=$script_dir/keys
private_key=$key_dir/id_ed25519

if [[ -f $private_key && -f $private_key.pub ]]; then
    printf 'Keypair already exists in %s\n' "$key_dir"
    exit 0
fi
if [[ -e $private_key || -e $private_key.pub ]]; then
    printf 'error: incomplete keypair in %s; remove it and retry\n' "$key_dir" >&2
    exit 1
fi

mkdir -p "$key_dir"
ssh-keygen -q -t ed25519 -N '' -C windows-vm -f "$private_key"
chmod 0600 "$private_key"
chmod 0644 "$private_key.pub"
printf 'Generated Windows VM keypair in %s\n' "$key_dir"
printf 'Use %s when baking the Windows image.\n' "$private_key.pub"
