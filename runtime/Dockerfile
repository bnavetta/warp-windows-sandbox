FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        coreutils \
        curl \
        jq \
        openssh-client \
        ovmf \
        python3 \
        python3-winrm \
        qemu-system-x86 \
        qemu-utils \
        socat \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

# Run runtime/gen-keys.sh before docker build. image/build.sh consumes the same
# public key and Administrator password while baking the Windows image.
COPY runtime/keys/ /tmp/windows-vm-keys/
RUN test -f /tmp/windows-vm-keys/id_ed25519 \
    && test -f /tmp/windows-vm-keys/id_ed25519.pub \
    && test -s /tmp/windows-vm-keys/administrator_password \
    && install -d -m 0755 /opt/windows-vm/keys \
    && install -m 0644 /tmp/windows-vm-keys/id_ed25519 /opt/windows-vm/keys/id_ed25519 \
    && install -m 0644 /tmp/windows-vm-keys/id_ed25519.pub /opt/windows-vm/keys/id_ed25519.pub \
    && install -m 0600 /tmp/windows-vm-keys/administrator_password /opt/windows-vm/keys/administrator_password \
    && rm -rf /tmp/windows-vm-keys

# The credentials are intentionally baked into the sandbox image. Guest SSH and
# WinRM ports bind only to loopback inside the sandbox. vm copies the SSH key
# into its per-run state directory with mode 0600 before invoking OpenSSH.
COPY runtime/bin/ /opt/windows-vm/bin/
COPY runtime/libexec/ /opt/windows-vm/libexec/
COPY runtime/skills/windows-vm/SKILL.md /usr/local/share/windows-vm/skills/windows-vm/SKILL.md
COPY runtime/skills/windows-vm/SKILL.md /root/.agents/skills/windows-vm/SKILL.md
RUN chmod 0755 /opt/windows-vm/bin/vm \
    && chmod 0644 /opt/windows-vm/libexec/*.sh \
    && chmod 0644 /opt/windows-vm/libexec/*.py \
    && ln -s /opt/windows-vm/bin/vm /usr/local/bin/vm \
    && chmod 0644 /usr/local/share/windows-vm/skills/windows-vm/SKILL.md \
    && chmod 0644 /root/.agents/skills/windows-vm/SKILL.md

ENV VM_STATE_DIR=/run/windows-vm
