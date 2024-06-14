# Use an official Ubuntu as a parent image
FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV DEVICE=r4s
ENV BRANCH=master

# Install dependencies
RUN apt-get update && apt-get install -qq -y --no-install-recommends \
    pv jq ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
    bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar flex gawk gettext gcc-multilib \
    g++-multilib git gnutls-dev gperf haveged help2man intltool lib32gcc-s1 libc6-dev-i386 libelf-dev \
    libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5 \
    libncursesw5-dev libpython3-dev libreadline-dev libssl-dev libtool lld llvm lrzsz mkisofs \
    nano ninja-build p7zip p7zip-full patch pkgconf python2.7 python3 python3-pip python3-ply \
    python3-docutils python3-pyelftools qemu-utils re2c rsync scons squashfs-tools subversion swig \
    texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev

# Clean up APT when done
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Set up workspace
WORKDIR /workspace

# Add the script to merge packages and patches
COPY scripts/merge_packages.sh /workspace/scripts/
COPY scripts/patches.sh /workspace/scripts/

# Clone repositories and prepare the build environment
RUN git clone -b r4s --single-branch https://github.com/coolsnowwolf/lede lede \
    && cd lede \
    && ./scripts/feeds update -a \
    && ./scripts/feeds install -a \
    && . /workspace/scripts/merge_packages.sh \
    && . /workspace/scripts/patches.sh

# Custom configure file
COPY *.config.seed /workspace/
RUN cd /workspace/lede \
    && cat /workspace/r4s.config.seed /workspace/common.seed | sed 's/\(CONFIG_PACKAGE_luci-app-[^A-Z]*=\)y/\1m/' > .config \
    && find package/ -type d -name luci-app-* | rev | cut -d'/' -f1 | rev | xargs -ri echo CONFIG_PACKAGE_{}=m >> .config \
    && cat /workspace/extra_packages.seed >> .config \
    && make defconfig && sed -i -E 's/# (CONFIG_.*_COMPRESS_UPX) is not set/\1=y/' .config && make defconfig

# Build and deploy packages
RUN cd /workspace/lede \
    && ulimit -SHn 65000 \
    && rm -rf dl \
    && while true; do make download -j && break || true; done \
    && [ `nproc` -gt 8 ] && con=$[`nproc`/2+3] || con=`nproc` \
    && if [ -d build_dir ]; then \
        make -j$con IGNORE_ERRORS=1 tools/compile toolchain/compile buildinfo target/compile package/compile package/install target/install \
        && if [ ! -e /workspace/lede/bin/targets/*/*/*imagebuilder*xz ]; then \
            make V=sc \
        fi \
    else \
        make -j$con IGNORE_ERRORS=1 tools/compile toolchain/compile \
    fi

# Prepare artifact
RUN mkdir -p /workspace/artifact/buildinfo \
    && cd /workspace/lede \
    && cp -rf .config $(find ./bin/targets/ -type f -name "*.buildinfo" -o -name "*.manifest") /workspace/artifact/buildinfo/

# Final cleanup
RUN cd /workspace/lede \
    && make clean \
    && rm -rf bin tmp

# Entry point for running the container
CMD ["bash"]
