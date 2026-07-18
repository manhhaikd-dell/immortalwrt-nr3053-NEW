#!/bin/bash
# Install build dependencies for ImmortalWrt on Ubuntu/Debian.

set -euo pipefail

APT_GET=(apt-get)
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    APT_GET=(sudo apt-get)
fi

export DEBIAN_FRONTEND=noninteractive

"${APT_GET[@]}" update
"${APT_GET[@]}" install -y --no-install-recommends \
    autoconf \
    automake \
    bash \
    binutils \
    bison \
    build-essential \
    bzip2 \
    ca-certificates \
    clang \
    curl \
    diffutils \
    file \
    flex \
    g++ \
    gawk \
    gcc \
    gettext \
    git \
    grep \
    gzip \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    libtool \
    make \
    patch \
    perl \
    pkg-config \
    python3 \
    python3-dev \
    python3-pyelftools \
    python3-setuptools \
    rsync \
    subversion \
    swig \
    tar \
    time \
    unzip \
    wget \
    which \
    xz-utils \
    zlib1g-dev \
    zstd
