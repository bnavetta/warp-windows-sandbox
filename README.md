# windows-sandbox

A Docker base image for Warp cloud agent environments that lets the agent run a
KVM-accelerated Windows Server 2025 VM inside the sandbox.

This image adds a `vm` CLI:

```
vm start                      # boot the VM (downloads the base image on first use)
vm run -- Get-ComputerInfo    # run PowerShell in the guest
vm run --transport winrm -- Get-ComputerInfo
vm run --shell cmd -- ver     # or cmd.exe
vm cp ./artifact.zip vm:C:\Users\vmuser\artifact.zip
vm forward add 8080:8080      # reach a guest service from the container
vm stop                       # graceful shutdown + cleanup
```

## How it works

- **Virtualization:** plain QEMU/KVM, using QEMU's support for UEFI via OVMF, virtio disks
  and NICs, and Hyper-V enlightenments.
- **Image caching:** the Windows server image is cached and used to create a per-VM overlay.
- **Networking:** QEMU user-mode (slirp) networking. The guest gets the
  container's outbound access with no extra capabilities. The container reaches
  the guest through `hostfwd` rules on `127.0.0.1` (SSH, RDP, and WinRM by
  default; others via `vm forward add`). The guest reaches the container at
  `10.0.2.2`.
- **Fixed hardware identity:** UUID, SMBIOS serial and MAC are constants shared by
  the image bake and the runtime so that licensing state baked into the image
  survives across runs. Do not randomize them.

## Layout

- `runtime/` - the Docker image: `Dockerfile`, `bin/vm`, `libexec/`, and the
  `windows-vm` agent skill.
- `image/` - Packer definition the Windows base image. See `image/README.md`.
- `tests/` - bash tests for the pure-shell parts of `vm` (run on any OS).
- `docker-compose.yml` - local Linux harness for driving `vm` by hand.
- `devbox/` - Namespace Devbox base image with Packer, QEMU/KVM, Docker and
  lint tools for doing the build and runtime testing remotely (see below).

## Prerequisites

- The sandbox must have `/dev/kvm` (and nested virtualization if the host is
  itself a VM).
- A published base image URL (`VM_IMAGE_URL`), its version (`VM_IMAGE_VERSION`)
  and sha256 (`VM_IMAGE_SHA256`). Produce these with `image/build.sh` and
  `image/publish.sh` on a Linux host with KVM.

## Quickstart

```
# one-time: generate the guest SSH keypair and Administrator password
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

`vm run` uses SSH by default. Pass `--transport winrm` to use pywinrm, or set
`VM_TRANSPORT=winrm` to make it the default. The generated Administrator
password is built into both the Windows image and runtime image; override it
with `VM_WINRM_PASSWORD` or `VM_WINRM_PASSWORD_FILE` when needed.
Build both images from the same `runtime/keys/` directory. Rotating those
credentials requires rebuilding both images.

In a Warp agentenvironment, use this image as the base, set the `VM_IMAGE_*`
variables, and optionally run `vm prefetch` in the init script so the download
happens before the agent starts.

## Testing

```
shellcheck runtime/bin/vm runtime/libexec/*.sh scripts/*.sh image/*.sh
bash tests/run.sh
```
