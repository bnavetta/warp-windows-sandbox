# windows-sandbox

A Docker base image for Oz cloud agent environments that lets the agent run a
KVM-accelerated Windows Server 2025 VM inside the sandbox.

The agent harness is the container entrypoint. This image adds a `vm` CLI:

```
vm start                      # boot the VM (downloads the base image on first use)
vm run -- Get-ComputerInfo    # run PowerShell in the guest
vm run --shell cmd -- ver     # or cmd.exe
vm cp ./artifact.zip vm:C:\Users\vmuser\artifact.zip
vm forward add 8080:8080      # reach a guest service from the container
vm stop                       # graceful shutdown + cleanup
```

## How it works

- **Virtualization:** plain QEMU/KVM. No libvirt, no Vagrant. OVMF (UEFI), no TPM,
  virtio disk and NIC, Hyper-V enlightenments enabled.
- **Image caching:** a pristine `win-base-<version>.qcow2` is downloaded once from
  `$VM_IMAGE_URL` into the persistent cache dir (`$VM_CACHE_DIR`, or
  `$WARP_BUILD_CACHE_ROOT/windows` in Oz). Every `vm start` boots a throwaway
  qcow2 overlay in `$VM_STATE_DIR`, so the cached image is never modified.
- **Networking:** QEMU user-mode (slirp) networking. The guest gets the
  container's outbound access with no extra capabilities. The container reaches
  the guest through `hostfwd` rules on `127.0.0.1` (SSH always; others via
  `vm forward add`). The guest reaches the container at `10.0.2.2`.
- **Fixed hardware identity:** UUID, SMBIOS serial and MAC are constants shared by
  the image bake and the runtime so that licensing state baked into the image
  survives across runs. Do not randomize them.
- **Licensing:** Phase 1 uses the 180-day evaluation edition; the image is
  rebuilt on a schedule (`scripts/rebuild-check.sh` reports remaining days).
  Phase 2 switches to Windows Server 2025 pay-as-you-go via Azure Arc; the
  runtime hooks (`ARC_*` env vars) are already present and are no-ops until set.

## Layout

- `runtime/` - the Docker image: `Dockerfile`, `bin/vm`, `libexec/`, and the
  `windows-vm` agent skill.
- `image/` - one-time Packer bake of the Windows base image. See `image/README.md`.
- `scripts/` - `rebuild-check.sh` (eval clock) and `arc-sweep.sh` (Phase 2 cleanup).
- `tests/` - bash tests for the pure-shell parts of `vm` (run on any OS).
- `docker-compose.yml` - local Linux harness for driving `vm` by hand.

## Prerequisites

- The sandbox must have `/dev/kvm` (and nested virtualization if the host is
  itself a VM).
- A published base image URL (`VM_IMAGE_URL`), its version (`VM_IMAGE_VERSION`)
  and sha256 (`VM_IMAGE_SHA256`). Produce these with `image/build.sh` and
  `image/publish.sh` on a Linux host with KVM.

## Quickstart

```
# one-time: generate the guest SSH keypair used by both the bake and the runtime
runtime/gen-keys.sh

# build the runtime image (build context is the repo root)
docker build -f runtime/Dockerfile -t windows-sandbox-runtime .

# local test on a Linux host with /dev/kvm
export VM_IMAGE_URL=https://.../win-base-20260911.qcow2
export VM_IMAGE_VERSION=20260911
docker compose up -d
docker compose exec windows-sandbox vm start
docker compose exec windows-sandbox vm run -- systeminfo
docker compose exec windows-sandbox vm stop
```

In an Oz environment, use this image as the base, set the `VM_IMAGE_*`
variables, and optionally run `vm prefetch` in the init script so the download
happens before the agent starts.

## Testing

```
shellcheck runtime/bin/vm runtime/libexec/*.sh scripts/*.sh image/*.sh
bash tests/run.sh
```
