# syntax=docker/dockerfile:1.6
###########################################################################################
## PDC node Dockerfile - builds the source tree it is run from (no `git clone` inside)
###########################################################################################
#
# Build from the repository root, with submodules checked out (git clone --recursive):
#
#   docker build -f utils/docker/Dockerfile -t pdc-node .                  # runtime image (pdcd + simplewallet)
#   docker build -f utils/docker/Dockerfile --target tests -t pdc-tests .  # build + run the unit tests
#   docker build -f utils/docker/Dockerfile --target artifacts -o out .    # export binaries to ./out
#
# Multi-platform (amd64 + arm64), see utils/docker/README.md for the native-runner caveat:
#
#   docker buildx build --platform linux/amd64,linux/arm64 -f utils/docker/Dockerfile -t pdc-node .
#
# Run a node. Publish RPC on loopback only: the daemon RPC has no authentication or TLS.
# Put utils/docker/compose.yml's gateway in front of it to serve wallets from a remote host.
#
#   docker run -d --name pdcd --restart unless-stopped \
#     -v pdc-data:/home/pdc/.PDC -p 19121:19121 -p 127.0.0.1:19211:19211 pdc-node
#
# Build args (all downloads are verified against the sha256 below):
#   UBUNTU_VERSION, BOOST_VERSION_DOT, BOOST_HASH, OPENSSL_VERSION_DOT, OPENSSL_HASH, JOBS

ARG UBUNTU_VERSION=22.04

###########################################################################################
# Toolchain
###########################################################################################
FROM ubuntu:${UBUNTU_VERSION} AS toolchain

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      ccache \
      cmake \
      curl \
      git \
      libicu-dev \
      pkg-config \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

###########################################################################################
# Boost (own stage so BuildKit builds it in parallel with OpenSSL and caches it)
###########################################################################################
FROM toolchain AS boost

ARG BOOST_VERSION_DOT=1.84.0
ARG BOOST_HASH=cc4b893acf645c9d4b698e9a0f08ca8846aa5d6c68275c14c3e7949c24109454
ARG JOBS=0

RUN set -eux; \
    BOOST_VERSION="$(echo "${BOOST_VERSION_DOT}" | tr . _)"; \
    curl -fL -o boost.tar.bz2 "https://archives.boost.io/release/${BOOST_VERSION_DOT}/source/boost_${BOOST_VERSION}.tar.bz2"; \
    echo "${BOOST_HASH}  boost.tar.bz2" | sha256sum -c -; \
    mkdir /opt/boost && tar -xjf boost.tar.bz2 -C /opt/boost --strip-components=1; \
    rm boost.tar.bz2; \
    cd /opt/boost; \
    ./bootstrap.sh --with-libraries=system,filesystem,thread,date_time,chrono,regex,serialization,atomic,program_options,locale,timer,log; \
    ./b2 -j"$([ "${JOBS}" -gt 0 ] && echo "${JOBS}" || nproc)"; \
    rm -rf /opt/boost/bin.v2

###########################################################################################
# OpenSSL 1.1.1 (Boost.Asio 1.84 / the daemon are built against it, same as the release CI)
###########################################################################################
FROM toolchain AS openssl

ARG OPENSSL_VERSION_DOT=1.1.1w
ARG OPENSSL_HASH=cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
ARG JOBS=0

RUN set -eux; \
    curl -fL -o openssl.tar.gz "https://github.com/openssl/openssl/releases/download/OpenSSL_$(echo "${OPENSSL_VERSION_DOT}" | tr . _)/openssl-${OPENSSL_VERSION_DOT}.tar.gz"; \
    echo "${OPENSSL_HASH}  openssl.tar.gz" | sha256sum -c -; \
    tar xzf openssl.tar.gz; \
    cd "openssl-${OPENSSL_VERSION_DOT}"; \
    ./config --prefix=/opt/openssl --openssldir=/opt/openssl shared zlib; \
    make -j"$([ "${JOBS}" -gt 0 ] && echo "${JOBS}" || nproc)"; \
    make install_sw

###########################################################################################
# Sources + dependencies
###########################################################################################
FROM toolchain AS source

COPY --from=boost /opt/boost /opt/boost
COPY --from=openssl /opt/openssl /opt/openssl
ENV BOOST_ROOT=/opt/boost \
    OPENSSL_ROOT_DIR=/opt/openssl \
    LD_LIBRARY_PATH=/opt/openssl/lib

COPY . /src
WORKDIR /src
RUN test -f contrib/randomx/CMakeLists.txt || \
    { echo "Submodules are missing: run 'git submodule update --init --recursive' before docker build"; exit 1; }

###########################################################################################
# Release build (static, same flags as .github/workflows/main-cli.yml)
###########################################################################################
FROM source AS build

ARG JOBS=0
# --build-arg TESTNET=TRUE builds the testnet daemon (other ports, network id and hard-fork schedule)
ARG TESTNET=FALSE
RUN --mount=type=cache,target=/root/.ccache \
    set -eux; \
    mkdir -p /build/release && cd /build/release; \
    cmake -D BOOST_ROOT=/opt/boost -D OPENSSL_ROOT_DIR=/opt/openssl \
          -D BUILD_GUI=OFF -D STATIC=true -D CMAKE_BUILD_TYPE=Release -D BUILD_TESTS=OFF -D TESTNET=${TESTNET} \
          -D CMAKE_C_COMPILER_LAUNCHER=ccache -D CMAKE_CXX_COMPILER_LAUNCHER=ccache \
          /src; \
    make -j"$([ "${JOBS}" -gt 0 ] && echo "${JOBS}" || nproc)" daemon simplewallet connectivity_tool; \
    strip src/pdcd src/simplewallet src/connectivity_tool

###########################################################################################
# Remote-only wallet library for the Flutter wallet (docker build --target walletlib-artifacts -o out .)
# Same remote-only configuration as the mobile wallets, as a shared library with a C ABI; the build then runs
# src/wallet_core_lib/smoke_test.c against the real engine (creates a wallet offline, asks for its address).
###########################################################################################
FROM source AS walletlib

ARG JOBS=0
ARG TESTNET=FALSE
RUN apt-get update && apt-get install -y --no-install-recommends patchelf && rm -rf /var/lib/apt/lists/*
RUN --mount=type=cache,target=/root/.ccache \
    set -eux; \
    mkdir -p /build/walletlib && cd /build/walletlib; \
    cmake -D BOOST_ROOT=/opt/boost -D OPENSSL_ROOT_DIR=/opt/openssl \
          -D BUILD_WALLET_CORE_LIB=ON -D BUILD_GUI=OFF -D CMAKE_BUILD_TYPE=Release -D BUILD_TESTS=OFF -D TESTNET=${TESTNET} \
          -D CMAKE_C_COMPILER_LAUNCHER=ccache -D CMAKE_CXX_COMPILER_LAUNCHER=ccache \
          /src; \
    make -j"$([ "${JOBS}" -gt 0 ] && echo "${JOBS}" || nproc)" pdc_wallet_core; \
    LIB="$(find /build/walletlib -name 'libpdc_wallet_core.so' | head -n1)"; \
    test -n "$LIB"; \
    mkdir -p /build/dist; \
    cp "$LIB" /build/dist/libpdc_wallet_core.so; \
    for dep in $(ldd "$LIB" | awk '/=> \/opt\//{print $3}'); do cp -L "$dep" /build/dist/; done; \
    cd /build/dist; \
    for f in *.so*; do strip --strip-unneeded "$f" || true; patchelf --set-rpath '$ORIGIN' "$f"; done; \
    ls -l /build/dist; \
    gcc -O1 -Wall -o /build/smoke_test /src/src/wallet_core_lib/smoke_test.c -ldl; \
    mkdir -p /tmp/pdcw; \
    env -u LD_LIBRARY_PATH /build/smoke_test /build/dist/libpdc_wallet_core.so /tmp/pdcw

FROM scratch AS walletlib-artifacts
COPY --from=walletlib /build/dist/ /

###########################################################################################
# The Flutter wallet's Dart code against the real library, offline (docker build --target walletlib-dart-check .)
# Create, reopen, wrong password, restore from the phrase (same address), and how spending without funds fails.
###########################################################################################
FROM dart:stable AS walletlib-dart-check

COPY --from=walletlib /build/dist/ /opt/pdc/
COPY wallet-flutter/lib /w/lib
COPY wallet-flutter/tool/real_engine_check /w/tool/real_engine_check
WORKDIR /w/tool/real_engine_check
RUN dart pub get
RUN PDC_WALLET_CORE_LIB=/opt/pdc/libpdc_wallet_core.so dart run bin/check.dart

###########################################################################################
# Unit tests (docker build --target tests): fails the build if a test fails
###########################################################################################
FROM source AS tests

ARG JOBS=0
# narrow the run while triaging, e.g. --build-arg GTEST_FILTER='pow_epoch_cache*:seed_nodes_file*'
ARG GTEST_FILTER=*
RUN --mount=type=cache,target=/root/.ccache \
    set -eux; \
    mkdir -p /build/tests && cd /build/tests; \
    cmake -D BOOST_ROOT=/opt/boost -D OPENSSL_ROOT_DIR=/opt/openssl \
          -D BUILD_GUI=OFF -D CMAKE_BUILD_TYPE=Release -D BUILD_TESTS=ON \
          -D CMAKE_C_COMPILER_LAUNCHER=ccache -D CMAKE_CXX_COMPILER_LAUNCHER=ccache \
          /src; \
    make -j"$([ "${JOBS}" -gt 0 ] && echo "${JOBS}" || nproc)" unit_tests; \
    cd tests && ./unit_tests --gtest_color=no --gtest_filter="${GTEST_FILTER}"

###########################################################################################
# Export only the binaries: docker build --target artifacts -o out .
###########################################################################################
FROM scratch AS artifacts
COPY --from=build /build/release/src/pdcd /build/release/src/simplewallet /build/release/src/connectivity_tool /

###########################################################################################
# Runtime
###########################################################################################
FROM ubuntu:${UBUNTU_VERSION} AS runtime

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -ms /bin/bash pdc \
    && mkdir -p /home/pdc/.PDC \
    && chown -R pdc:pdc /home/pdc/.PDC

USER pdc:pdc
WORKDIR /home/pdc
COPY --chown=pdc:pdc --from=build /build/release/src/pdcd /build/release/src/simplewallet ./

# blockchain data lives here; an optional seed_nodes.txt goes next to it
VOLUME /home/pdc/.PDC

# 19121 p2p, 19211 daemon RPC (unauthenticated: never expose directly to the internet)
EXPOSE 19121 19211

HEALTHCHECK --interval=60s --timeout=10s --start-period=120s --retries=3 \
  CMD curl -fsS http://127.0.0.1:19211/getinfo > /dev/null || exit 1

ENTRYPOINT ["./pdcd"]
# RPC binds 0.0.0.0 inside the container so a published port reaches it; publish it on 127.0.0.1 only
CMD ["--data-dir=/home/pdc/.PDC", "--disable-upnp", "--rpc-bind-ip=0.0.0.0", "--log-level=0"]

###########################################################################################
# End-to-end test pieces (utils/docker/e2e/run.sh): a testnet node on accelerated time, and the runner that drives
# the real wallet engine against it through the gateway. Build both with --build-arg TESTNET=TRUE.
###########################################################################################
FROM runtime AS node-e2e
USER root
# libfaketime lets the test node run its clock 60x faster, so the 120 s block target is ~2 s and a few hundred
# blocks take minutes. Test builds only: nothing else uses this stage.
RUN apt-get update && apt-get install -y --no-install-recommends faketime && rm -rf /var/lib/apt/lists/*
USER pdc:pdc
ENTRYPOINT ["faketime", "-f", "+0 x60", "./pdcd"]

FROM dart:stable AS e2e-runner
COPY --from=walletlib /build/dist/ /opt/pdc/
COPY wallet-flutter/lib /w/lib
COPY wallet-flutter/tool/real_engine_check /w/tool/real_engine_check
WORKDIR /w/tool/real_engine_check
RUN dart pub get
ENV PDC_WALLET_CORE_LIB=/opt/pdc/libpdc_wallet_core.so
CMD ["dart", "run", "bin/e2e.dart"]

# The last stage is what a plain `docker build` produces: keep that the runtime image.
FROM runtime AS final
