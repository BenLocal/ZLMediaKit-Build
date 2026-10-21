# Debian 11 (bullseye) went EOL on 2026-08-31, and its security pool has since been pulled
# from deb.debian.org: the bullseye-security *index* is still served, so apt-get update
# succeeds and then every .deb under /debian-security/pool/ 404s (libssl-dev, libav*-dev,
# git-man, perl-modules...). Bookworm is the current supported base.
FROM debian:bookworm-slim AS stage1

# ZLMediaKit only defines ENABLE_FFMPEG when pkg-config finds ALL of avutil/avcodec/swscale/
# swresample/avfilter (CMakeLists.txt). libswresample-dev (NOT libresample-dev) and
# libavfilter-dev are required, else -DENABLE_FFMPEG=true silently flips OFF and WebRTC
# can't transcode AAC->Opus (no audio). pkg-config is listed explicitly because nothing else
# here depends on it: without it ZLMediaKit falls back to its bundled FindAV*.cmake modules,
# and we'd rather stay on the primary pkg_check_modules path that carries real link flags.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential cmake git curl wget vim ca-certificates tzdata pkg-config libssl-dev \
    libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libswresample-dev libavfilter-dev ffmpeg \
    && apt-get clean

RUN mkdir -p /opt/media

WORKDIR /opt/media

# libsrtp
# https://github.com/cisco/libsrtp/archive/refs/tags/v2.5.0.tar.gz
RUN wget -O libsrtp-2.5.0.tar.gz https://github.com/cisco/libsrtp/archive/refs/tags/v2.5.0.tar.gz  && \
    tar -zxvf libsrtp-2.5.0.tar.gz && \
    cd libsrtp-2.5.0 && \
    ./configure --enable-openssl && \
    make -j $(nproc) && make install

ARG ARG_BRANCH=master
ENV ARG_BRANCH=${ARG_BRANCH}
# Local fixes on top of upstream, applied in name order; see each patch's header.
COPY patches /opt/media/patches
# ZLMediaKit's default .gitmodules points submodules at gitee.com, which rate-limits /
# blocks GitHub Actions runner IPs (401 -> git prompts for a username -> non-interactive
# clone failure). The repo ships .gitmodules_github with the same submodules on GitHub;
# swap to it before fetching submodules.
RUN git clone --depth=1 -b ${ARG_BRANCH} https://github.com/ZLMediaKit/ZLMediaKit.git && \
    cd ZLMediaKit && \
    cp .gitmodules_github .gitmodules && git submodule sync && \
    git submodule update --init --recursive && \
    git apply --verbose /opt/media/patches/*.patch && \
    mkdir -p build release/linux/Release/

WORKDIR /opt/media/ZLMediaKit/build
RUN cmake -DCMAKE_BUILD_TYPE=Release \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DENABLE_OBJCOPY=OFF \
    -DENABLE_WEBRTC=true \
    -DENABLE_FFMPEG=true .. && \
    make -j $(nproc)

FROM scratch AS export-stage
COPY --from=stage1 /opt/media/ZLMediaKit/release/linux/Release/MediaServer bin/MediaServer
COPY --from=stage1 /opt/media/ZLMediaKit/api/include/** include/
COPY --from=stage1 /opt/media/ZLMediaKit/release/linux/Release/*.so lib/
COPY --from=stage1 /opt/media/ZLMediaKit/release/linux/Release/*.a lib/
