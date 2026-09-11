---
name: windows-vm
description: Start and use the sandboxed Windows VM whenever work needs to run, build, test, inspect, or reproduce anything on Windows.
---

# Windows VM

Use the `vm` CLI to work inside Windows Server 2025. Start one VM, run as many
commands as needed, and stop it when the task is complete.

## Lifecycle

```bash
vm start
vm run -- Get-ComputerInfo
vm run -- Get-ChildItem C:\
vm stop
```

The first start may download a large base image. Later starts reuse the pristine
cached image and normally take only the guest boot time. Every start creates a
throwaway disk overlay, so guest changes disappear after `vm stop`.

Always stop the VM at the end of the task. `vm start` cleans state left by an
unclean container exit, but explicit shutdown is faster and gives Azure Arc a
chance to disconnect when Arc is enabled.

## Running commands

The guest's default OpenSSH shell is PowerShell:

```bash
vm run -- '$PSVersionTable'
vm run -- Get-Service sshd
vm run --shell cmd -- ver
vm run --transport winrm -- Get-ComputerInfo
```

Quote PowerShell expressions with single quotes in Bash so Bash does not expand
`$variables`, globs, or command substitutions. For multiline scripts, send
PowerShell on stdin:

```bash
vm run - <<'POWERSHELL'
$ErrorActionPreference = 'Stop'
Get-ChildItem Env:
POWERSHELL
```

Use `--timeout SECONDS` for commands that might hang. The guest exit code is the
exit code of `vm run`.

SSH is the default command transport. WinRM uses pywinrm and the Administrator
credential embedded in both images. Select it per command with
`--transport winrm`, or set `VM_TRANSPORT=winrm`. `VM_WINRM_USER` defaults to
`Administrator`; `--user` overrides the selected transport's user for one
command. `VM_WINRM_PASSWORD` and `VM_WINRM_PASSWORD_FILE` override the embedded
credential.

Copy files in either direction by prefixing the guest path with `vm:`:

```bash
vm cp ./input.zip 'vm:C:\Temp\input.zip'
vm cp 'vm:C:\Temp\result.json' ./result.json
```

## Networking

SSH is always exposed on container loopback. RDP and WinRM are forwarded by
default. Expose another guest service at startup or while the VM is running:

```bash
vm start --forward 18080:8080
vm forward add 18443:443
vm forward ls
vm forward rm 18443:443
```

Host ports bind to `127.0.0.1` inside the container. From the Windows guest,
reach a service running in the container at `10.0.2.2`. The guest has outbound
network access through QEMU user-mode networking.

## Diagnostics

Runtime state and logs are under `$VM_STATE_DIR`, normally `/run/windows-vm`
and `/tmp/windows-vm` when `/run` is not writable:

- `qemu.log`: QEMU startup and device errors
- `serial.log`: Windows serial console output
- `qmp.sock`: QEMU control socket
- `forwards`: active port-forward registry

Use `vm status` to inspect state. Use `vm console` to follow the serial log. If
boot debugging needs a graphical display, start with `vm start --vnc` and
connect to `127.0.0.1:5900`.

When startup fails, `vm` preserves the entire state directory instead of
deleting it. `vm status` prints the recorded failure and paths to any QEMU or
serial logs. Inspect those files before retrying; the next `vm start` removes
the stale state automatically. `vm stop` also explicitly clears preserved
failure state.

The guest is a fresh copy of the base image on every start; nothing persists in
the VM between `vm stop` and the next `vm start`. Copy results out with `vm cp`
before stopping.
