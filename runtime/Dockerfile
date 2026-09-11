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
        qemu-system-x86 \
        qemu-utils \
        socat \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

# Run runtime/gen-keys.sh before docker build. image/build.sh consumes the same
# runtime/keys/id_ed25519.pub while baking vmuser's authorized_keys.
COPY runtime/keys/ /tmp/windows-vm-keys/
RUN test -f /tmp/windows-vm-keys/id_ed25519 \
    && test -f /tmp/windows-vm-keys/id_ed25519.pub \
    && install -d -m 0755 /usr/local/lib/windows-vm \
    && install -m 0644 /tmp/windows-vm-keys/id_ed25519 /usr/local/lib/windows-vm/id_ed25519 \
    && install -m 0644 /tmp/windows-vm-keys/id_ed25519.pub /usr/local/lib/windows-vm/id_ed25519.pub \
    && rm -rf /tmp/windows-vm-keys

# The private key is intentionally baked into the sandbox image. The guest SSH
# port binds only to loopback inside the sandbox. vm copies this key into its
# per-run state directory with mode 0600 before invoking OpenSSH.
COPY runtime/bin/vm /usr/local/bin/vm
COPY runtime/libexec/ /usr/local/lib/windows-vm/
COPY runtime/skills/windows-vm/SKILL.md /usr/local/share/windows-vm/skills/windows-vm/SKILL.md
COPY runtime/skills/windows-vm/SKILL.md /root/.agents/skills/windows-vm/SKILL.md

RUN chmod 0755 /usr/local/bin/vm \
    && chmod 0644 /usr/local/lib/windows-vm/*.sh \
    && chmod 0644 /usr/local/share/windows-vm/skills/windows-vm/SKILL.md \
    && chmod 0644 /root/.agents/skills/windows-vm/SKILL.md

ENV VM_STATE_DIR=/run/windows-vm
