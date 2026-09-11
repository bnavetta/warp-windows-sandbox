#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'usage: %s <qcow2-path> [destination-prefix]\n' "${0##*/}" >&2
    printf '       destination-prefix may also be set with IMAGE_BUCKET_URL\n' >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 2
fi

image_path=$1
destination=${2:-${IMAGE_BUCKET_URL:-}}
if [[ ! -f $image_path ]]; then
    printf 'error: image does not exist: %s\n' "$image_path" >&2
    exit 1
fi
checksum_path="${image_path}.sha256"
if [[ ! -f $checksum_path ]]; then
    printf 'error: checksum does not exist: %s\n' "$checksum_path" >&2
    exit 1
fi
if [[ -z $destination ]]; then
    printf 'error: provide a destination prefix or set IMAGE_BUCKET_URL\n' >&2
    exit 1
fi

destination=${destination%/}
image_name=$(basename -- "$image_path")
checksum_name=$(basename -- "$checksum_path")

case "$destination" in
    gs://*)
        if command -v gcloud >/dev/null 2>&1; then
            gcloud storage cp "$image_path" "$checksum_path" "$destination/"
        elif command -v gsutil >/dev/null 2>&1; then
            gsutil cp "$image_path" "$checksum_path" "$destination/"
        else
            printf 'error: publishing to gs:// requires gcloud or gsutil\n' >&2
            exit 1
        fi
        google_path=${destination#gs://}
        public_prefix="https://storage.googleapis.com/$google_path"
        ;;
    s3://*)
        if ! command -v aws >/dev/null 2>&1; then
            printf 'error: publishing to s3:// requires the AWS CLI\n' >&2
            exit 1
        fi
        aws s3 cp "$image_path" "$destination/$image_name"
        aws s3 cp "$checksum_path" "$destination/$checksum_name"
        s3_path=${destination#s3://}
        bucket=${s3_path%%/*}
        if [[ $s3_path == */* ]]; then
            key_prefix=${s3_path#*/}
            public_prefix="https://$bucket.s3.amazonaws.com/$key_prefix"
        else
            public_prefix="https://$bucket.s3.amazonaws.com"
        fi
        ;;
    *)
        printf 'error: unsupported destination %s; expected gs:// or s3://\n' "$destination" >&2
        exit 1
        ;;
esac

printf 'Upload complete. Public URL guesses (bucket permissions must allow access):\n'
printf '  %s/%s\n' "$public_prefix" "$image_name"
printf '  %s/%s\n' "$public_prefix" "$checksum_name"
