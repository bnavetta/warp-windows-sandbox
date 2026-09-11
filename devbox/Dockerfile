# Namespace Devbox base image for developing windows-sandbox.
#
# Build and register with:
#   devbox image build . --name=warp/windows-sandbox-dev -f devbox/Dockerfile
#
# Devboxes expose /dev/kvm with nested virtualization automatically, so this
# image can run image/build.sh (Packer + QEMU/KVM) and the docker-compose
# runtime harness directly.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Base tooling plus everything image/build.sh, runtime/, and the test suite need.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https \
        bash-completion \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        less \
        libxml2-utils \
        lsb-release \
        openssh-client \
        ovmf \
        p7zip-full \
        qemu-system-x86 \
        qemu-utils \
        shellcheck \
        socat \
        sudo \
        unzip \
        util-linux \
        vim \
        xorriso \
    && rm -rf /var/lib/apt/lists/*

# HashiCorp apt repo for Packer.
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends packer \
    && rm -rf /var/lib/apt/lists/*

# Docker engine + compose plugin for the local runtime harness (docker-compose.yml).
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Non-root user with passwordless sudo, per Namespace devbox conventions.
# Ubuntu 24.04 ships a default "ubuntu" user at uid 1000; devbox uses 1001.
# /dev/kvm is made usable by non-root users by the devbox runtime, so no kvm
# group membership is needed.
RUN adduser --disabled-password --gecos "" --uid 1001 devbox \
    && echo "devbox ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/devbox \
    && chmod 0440 /etc/sudoers.d/devbox \
    && usermod -aG docker devbox

# Pre-install the Packer QEMU plugin so packer init is a no-op offline.
USER devbox
WORKDIR /home/devbox
RUN packer plugins install github.com/hashicorp/qemu

# Default env for the repo's tooling.
ENV ISO_CACHE_DIR=/home/devbox/.cache/windows-sandbox
