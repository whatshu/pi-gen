ARG BASE_IMAGE=debian:bullseye
FROM ${BASE_IMAGE}

ARG http_proxy
ARG https_proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG no_proxy
ARG NO_PROXY

ENV DEBIAN_FRONTEND=noninteractive

RUN if [ -n "${http_proxy:-${HTTP_PROXY:-}}" ]; then \
        printf 'Acquire::http::Proxy "%s";\n' "${http_proxy:-${HTTP_PROXY}}" > /etc/apt/apt.conf.d/99proxy; \
    fi && \
    if [ -n "${https_proxy:-${HTTPS_PROXY:-}}" ]; then \
        printf 'Acquire::https::Proxy "%s";\n' "${https_proxy:-${HTTPS_PROXY}}" >> /etc/apt/apt.conf.d/99proxy; \
    fi && \
    apt-get -y update && \
    apt-get -y install --no-install-recommends \
        git vim parted \
        quilt coreutils qemu-user-static debootstrap zerofree zip dosfstools e2fsprogs\
        libarchive-tools libcap2-bin rsync grep udev xz-utils curl xxd file kmod bc \
        binfmt-support ca-certificates fdisk gpg pigz arch-test \
        # Kernel build dependencies
        make gcc bison flex libssl-dev libelf-dev \
        crossbuild-essential-arm64 crossbuild-essential-armhf \
        dpkg-dev debhelper-compat dwarves \
        # LLVM/Rust toolchain for modern Raspberry Pi kernels
        clang llvm lld libclang-dev \
        rustc rust-src bindgen rustfmt rust-clippy \
    && rm -f /etc/apt/apt.conf.d/99proxy \
    && rm -rf /var/lib/apt/lists/*

COPY . /pi-gen/

VOLUME [ "/pi-gen/work", "/pi-gen/deploy"]
