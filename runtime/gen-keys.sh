#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
key_dir=$script_dir/keys
private_key=$key_dir/id_ed25519
password_file=$key_dir/administrator_password

if [[ -f $private_key && -f $private_key.pub ]]; then
    printf 'Keypair already exists in %s\n' "$key_dir"
elif [[ -e $private_key || -e $private_key.pub ]]; then
    printf 'error: incomplete keypair in %s; remove it and retry\n' "$key_dir" >&2
    exit 1
else
    mkdir -p "$key_dir"
    ssh-keygen -q -t ed25519 -N '' -C windows-vm -f "$private_key"
    chmod 0600 "$private_key"
    chmod 0644 "$private_key.pub"
    printf 'Generated Windows VM keypair in %s\n' "$key_dir"
fi

if [[ -s $password_file ]]; then
    printf 'Administrator password already exists in %s\n' "$password_file"
elif [[ -e $password_file ]]; then
    printf 'error: Administrator password file is empty: %s\n' "$password_file" >&2
    exit 1
else
    command -v od >/dev/null 2>&1 || {
        printf 'error: required command not found: od\n' >&2
        exit 1
    }
    random_hex=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
    umask 077
    printf 'Aa1!%s\n' "$random_hex" >"$password_file"
    printf 'Generated Windows Administrator password in %s\n' "$password_file"
fi
chmod 0600 "$password_file"

printf 'Use %s when baking the Windows image.\n' "$private_key.pub"
