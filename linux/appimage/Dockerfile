# SPDX-License-Identifier: BSD-3-Clause
# Ubuntu 22.04 OCI index: build with --platform=linux/amd64 or linux/arm64.
FROM ubuntu:22.04@sha256:0a9887931b0e38af2e3487ed39e29436b0535c4f3f52e57745baaf79d1898956
ENV DEBIAN_FRONTEND=noninteractive CMAKE_BUILD_PARALLEL_LEVEL=2
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
    libpcsclite-dev libnss3-tools python3 python3-pip python3-venv git curl \
    ca-certificates autoconf automake libtool gettext gperf patchelf squashfs-tools \
    desktop-file-utils binutils xvfb xauth dbus-x11 libgl1-mesa-dri libegl1 \
    libgl1 libgles2 fonts-dejavu-core libsecret-1-0 libasound2 libssl-dev \
    libayatana-appindicator3-dev librsvg2-common tzdata glib-networking \
    dconf-gsettings-backend gsettings-desktop-schemas && \
    python3 -m pip install cmake==3.31.6 meson==1.11.0 && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /work/project
# Supply the pinned Linux Flutter SDK and source tree as build inputs.
# No pcscd service, reader device, user HOME or browser profile is exposed.
CMD ["bash"]
