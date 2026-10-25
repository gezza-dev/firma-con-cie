# SPDX-License-Identifier: BSD-3-Clause
# Ubuntu 22.04 x86_64 OCI manifest verified during the local test build.
FROM --platform=linux/amd64 ubuntu:22.04@sha256:98510ac07bb4545e389be502a8918b385c018bfe4ceeb5ac7e0375c782268b04
ENV DEBIAN_FRONTEND=noninteractive CMAKE_BUILD_PARALLEL_LEVEL=2
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
    libpcsclite-dev libnss3-tools python3 python3-pip python3-venv git curl \
    ca-certificates autoconf automake libtool gettext patchelf squashfs-tools \
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
