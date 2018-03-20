#!/bin/bash

set -ex

# Use AWS mirror if running in EC2
if [ -n "${EC2:-}" ]; then
  A="archive.ubuntu.com"
  B="us-east-1.ec2.archive.ubuntu.com"
  perl -pi -e "s/${A}/${B}/g" /etc/apt/sources.list
fi

# Install common dependencies
apt-get update
# TODO: Some of these may not be necessary
apt-get install -y --no-install-recommends \
  apt-transport-https \
  asciidoc \
  autoconf \
  automake \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  docbook-xml \
  docbook-xsl \
  git \
  libatlas-base-dev \
  libiomp-dev \
  libyaml-dev \
  libz-dev \
  python \
  python-dev \
  python-setuptools \
  python-wheel \
  software-properties-common \
  sudo \
  wget \
  valgrind \
  xsltproc

# TODO: THIS IS A HACK!!!
# distributed nccl(2) tests are a bit busted, see https://github.com/pytorch/pytorch/issues/5877
if dpkg -s libnccl-dev; then
  apt-get remove -y libnccl-dev libnccl2
fi

# Setup compiler cache
if [ -n "$CUDA_VERSION" ]; then
  # If CUDA is installed, we must use ccache, as sccache doesn't support
  # caching nvcc yet

  # Install ccache from source.
  # Needs 3.4 or later for ccbin support
  pushd /tmp
  git clone https://github.com/ccache/ccache -b v3.4.1
  pushd ccache
  # Disable developer mode, so we squelch -Werror
  ./autogen.sh
  ./configure --prefix=/usr/local
  make "-j$(nproc)" install
  popd
  popd

  # Install ccache symlink wrappers
  pushd /usr/local/bin
  ln -sf "$(which ccache)" cc
  ln -sf "$(which ccache)" c++
  ln -sf "$(which ccache)" gcc
  ln -sf "$(which ccache)" g++
  ln -sf "$(which ccache)" clang
  ln -sf "$(which ccache)" clang++
  ln -sf "$(which ccache)" nvcc
  popd

else
  # We prefer sccache because we don't have to have a warm local ccache
  # to use it

  pushd /tmp
  SCCACHE_BASE_URL="https://github.com/mozilla/sccache/releases/download/"
  SCCACHE_VERSION="0.2.5"
  SCCACHE_BASE="sccache-${SCCACHE_VERSION}-x86_64-unknown-linux-musl"
  SCCACHE_FILE="$SCCACHE_BASE.tar.gz"
  wget -q "$SCCACHE_BASE_URL/$SCCACHE_VERSION/$SCCACHE_FILE"
  tar xzf $SCCACHE_FILE
  mv "$SCCACHE_BASE/sccache" /usr/local/bin
  popd

  function write_sccache_stub() {
    printf "#!/bin/sh\nexec sccache $1 \$*" > "/usr/local/bin/$1"
    chmod a+x "/usr/local/bin/$1"
  }

  write_sccache_stub cc
  write_sccache_stub c++
  write_sccache_stub gcc
  write_sccache_stub g++
  write_sccache_stub clang
  write_sccache_stub clang++
  write_sccache_stub nvcc

fi

# Cleanup package manager
apt-get autoclean && apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
