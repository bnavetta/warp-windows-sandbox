#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TEMPLATE="$SCRIPT_DIR/windows-server-2025.pkr.hcl"

for command_name in packer qemu-img curl sha256sum 7z; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'error: required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

if [[ ! -c /dev/kvm || ! -r /dev/kvm || ! -w /dev/kvm ]]; then
    printf 'error: /dev/kvm must exist and be readable and writable\n' >&2
    exit 1
fi

IMAGE_VERSION=${IMAGE_VERSION:-$(date +%Y%m%d)}
if [[ ! $IMAGE_VERSION =~ ^[0-9]{8}$ ]]; then
    printf 'error: IMAGE_VERSION must use YYYYMMDD format\n' >&2
    exit 1
fi


RUNTIME_KEY_DIR=${RUNTIME_KEY_DIR:-"$SCRIPT_DIR/../runtime/keys"}
SSH_PUBLIC_KEY_FILE=${SSH_PUBLIC_KEY_FILE:-"$RUNTIME_KEY_DIR/id_ed25519.pub"}
if [[ ! -s $SSH_PUBLIC_KEY_FILE ]]; then
    printf 'error: SSH public key not found at %s\n' "$SSH_PUBLIC_KEY_FILE" >&2
    printf 'hint: run runtime/gen-keys.sh before building the image\n' >&2
    exit 1
fi
SSH_PUBLIC_KEY=$(cat "$SSH_PUBLIC_KEY_FILE")

if [[ -z ${ADMIN_PASSWORD:-} ]]; then
    ADMIN_PASSWORD_FILE=${ADMIN_PASSWORD_FILE:-"$RUNTIME_KEY_DIR/administrator_password"}
    if [[ ! -s $ADMIN_PASSWORD_FILE ]]; then
        printf 'error: Administrator password not found at %s\n' "$ADMIN_PASSWORD_FILE" >&2
        printf 'hint: run runtime/gen-keys.sh before building the image\n' >&2
        exit 1
    fi
    IFS= read -r ADMIN_PASSWORD <"$ADMIN_PASSWORD_FILE"
fi

# Both ISOs are downloaded once into a local cache directory and handed to
# Packer as file paths, so repeated build never re-download and the Windows ISO
# can also be supplied out-of-band (for example, copied from a bucket) via
# ISO_PATH without any URL.
ISO_CACHE_DIR=${ISO_CACHE_DIR:-${VIRTIO_CACHE_DIR:-"$SCRIPT_DIR/.packer-cache"}}
mkdir -p "$ISO_CACHE_DIR"

absolute_path() {
    printf '%s/%s\n' "$(CDPATH='' cd -- "$(dirname -- "$1")" && pwd)" "$(basename -- "$1")"
}

# download_if_missing <url> <destination>
download_if_missing() {
    local url=$1
    local destination=$2
    local temporary="${destination}.tmp.$$"

    if [[ -s $destination ]]; then
        printf 'Using cached %s\n' "$destination"
        return
    fi
    if [[ -z $url ]]; then
        printf 'error: %s does not exist and no download URL was provided\n' "$destination" >&2
        return 1
    fi
    printf 'Downloading %s\n  -> %s\n' "$url" "$destination"
    trap 'rm -f "$temporary"' EXIT
    curl --fail --location --retry 3 --output "$temporary" "$url"
    mv "$temporary" "$destination"
    trap - EXIT
}

# Windows Server 2025 installation ISO. Either point ISO_PATH at an existing
# file, or set ISO_URL and it is downloaded into the cache once.
ISO_PATH=${ISO_PATH:-"$ISO_CACHE_DIR/windows-server-2025.iso"}
if ! download_if_missing "${ISO_URL:-}" "$ISO_PATH"; then
    printf 'hint: set ISO_URL to the Windows Server 2025 evaluation ISO URL, or ISO_PATH to a local copy\n' >&2
    exit 1
fi
ISO_PATH=$(absolute_path "$ISO_PATH")

# Verify against ISO_CHECKSUM when provided; otherwise trust the local file and
# compute its checksum so Packer's own verification still passes.
if [[ -n ${ISO_CHECKSUM:-} ]]; then
    expected=${ISO_CHECKSUM#sha256:}
    actual=$(sha256sum "$ISO_PATH" | awk '{print $1}')
    if [[ ${actual,,} != "${expected,,}" ]]; then
        printf 'error: Windows ISO checksum mismatch\n  expected %s\n  actual   %s\n' "$expected" "$actual" >&2
        exit 1
    fi
    printf 'Verified Windows ISO sha256\n'
else
    printf 'ISO_CHECKSUM not set; computing sha256 of the local ISO (not verified against a published value)\n'
    actual=$(sha256sum "$ISO_PATH" | awk '{print $1}')
fi

ISO_CHECKSUM="sha256:$actual"

# virtio-win drivers ISO.
VIRTIO_WIN_ISO_URL=${VIRTIO_WIN_ISO_URL:-"https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"}
VIRTIO_WIN_ISO_PATH=${VIRTIO_WIN_ISO_PATH:-"$ISO_CACHE_DIR/virtio-win.iso"}
download_if_missing "$VIRTIO_WIN_ISO_URL" "$VIRTIO_WIN_ISO_PATH"
VIRTIO_WIN_ISO_PATH=$(absolute_path "$VIRTIO_WIN_ISO_PATH")

# Packer has no built-in Windows driver injection. Extract only the signed
# Server 2025 storage/network packages and the guest-tools installer into a
# stable tree. Passing the `$WinPEDriver$` directory itself to cd_files puts it
# at the PROVISION CD root, where Windows Setup automatically scans it
# recursively before disk configuration.
VIRTIO_STAGE_DIR=${VIRTIO_STAGE_DIR:-"$ISO_CACHE_DIR/virtio-win-2k25"}
VIRTIO_STAGE_STAMP="$VIRTIO_STAGE_DIR/.source-sha256"
virtio_sha256=$(sha256sum "$VIRTIO_WIN_ISO_PATH" | awk '{print $1}')
stage_signature="winpedriver-v1:$virtio_sha256"
if [[ ! -f $VIRTIO_STAGE_STAMP ]] ||
    [[ $(cat "$VIRTIO_STAGE_STAMP") != "$stage_signature" ]]; then
    rm -rf "$VIRTIO_STAGE_DIR"
    WINPE_DRIVER_DIR="$VIRTIO_STAGE_DIR/\$WinPEDriver\$"
    mkdir -p "$WINPE_DRIVER_DIR"
    printf 'Extracting Windows Server 2025 virtio drivers\n'
    7z x -y "-o$WINPE_DRIVER_DIR" "$VIRTIO_WIN_ISO_PATH" \
        'vioscsi/2k25/amd64/*' \
        'viostor/2k25/amd64/*' \
        'NetKVM/2k25/amd64/*' >/dev/null
    7z e -y "-o$VIRTIO_STAGE_DIR" "$VIRTIO_WIN_ISO_PATH" \
        'virtio-win-guest-tools.exe' >/dev/null
    for required_file in \
        "$WINPE_DRIVER_DIR/vioscsi/2k25/amd64/vioscsi.inf" \
        "$WINPE_DRIVER_DIR/viostor/2k25/amd64/viostor.inf" \
        "$WINPE_DRIVER_DIR/NetKVM/2k25/amd64/netkvm.inf" \
        "$VIRTIO_STAGE_DIR/virtio-win-guest-tools.exe"; do
        [[ -s $required_file ]] ||
            { printf 'error: expected virtio file was not extracted: %s\n' "$required_file" >&2; exit 1; }
    done
    printf '%s\n' "$stage_signature" >"$VIRTIO_STAGE_STAMP"
else
    printf 'Using staged Server 2025 virtio drivers at %s\n' "$VIRTIO_STAGE_DIR"
fi
VIRTIO_STAGE_DIR=$(absolute_path "$VIRTIO_STAGE_DIR")

PACKER_OUTPUT_DIR=${PACKER_OUTPUT_DIR:-"$SCRIPT_DIR/output-$IMAGE_VERSION"}
ARTIFACT_DIR=${ARTIFACT_DIR:-"$SCRIPT_DIR/dist"}
if [[ -e $PACKER_OUTPUT_DIR ]]; then
    printf 'error: Packer output directory already exists: %s\n' "$PACKER_OUTPUT_DIR" >&2
    printf 'remove it or set PACKER_OUTPUT_DIR to a new path before retrying\n' >&2
    exit 1
fi
mkdir -p "$ARTIFACT_DIR"

if command -v boxctl >/dev/null; then
    touch /.namespace/tasks/packer-build
    trap 'rm -f /.namespace/tasks/packer-build' EXIT
fi

export PKR_VAR_iso_url=$ISO_PATH
export PKR_VAR_iso_checksum=$ISO_CHECKSUM
export PKR_VAR_virtio_stage_dir=$VIRTIO_STAGE_DIR
export PKR_VAR_output_dir=$PACKER_OUTPUT_DIR
export PKR_VAR_image_version=$IMAGE_VERSION
export PKR_VAR_admin_password=$ADMIN_PASSWORD
export PKR_VAR_ssh_public_key=$SSH_PUBLIC_KEY

export PACKER_LOG=1
export PACKER_LOG_PATH="packer-$IMAGE_VERSION.log"
echo "Logging Packer output to $PACKER_LOG_PATH"

packer init "$TEMPLATE"
packer build "$@" "$TEMPLATE"

echo "Packer build complete"

packer_images=("$PACKER_OUTPUT_DIR"/*.qcow2)
if [[ ! -f ${packer_images[0]} || ${#packer_images[@]} -ne 1 ]]; then
    printf 'error: expected exactly one qcow2 image in %s\n' "$PACKER_OUTPUT_DIR" >&2
    exit 1
fi

final_image="$ARTIFACT_DIR/win-base-$IMAGE_VERSION.qcow2"
if [[ -e $final_image || -e $final_image.sha256 ]]; then
    printf 'error: output artifact already exists: %s\n' "$final_image" >&2
    exit 1
fi

# disk_compression=true and skip_compaction=false make Packer perform the
# qemu-img convert -c pass. Rename that compressed result without recompressing.
mv "${packer_images[0]}" "$final_image"
(
    cd "$ARTIFACT_DIR"
    sha256sum "$(basename -- "$final_image")" >"$(basename -- "$final_image").sha256"
)

image_sha256=$(awk '{print $1}' "$final_image.sha256")
printf '\nImage build complete:\n'
printf '  %s\n' "$final_image"
printf '  %s.sha256\n\n' "$final_image"
printf 'Export these values for the runtime image:\n'
printf '  export VM_IMAGE_VERSION=%q\n' "$IMAGE_VERSION"
printf '  export VM_IMAGE_SHA256=%q\n' "$image_sha256"
