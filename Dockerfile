FROM debian:bullseye-slim AS stage1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential cmake git curl wget vim ca-certificates tzdata libssl-dev \
    libavcodec-dev libavutil-dev libswscale-dev libresample-dev ffmpeg \
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


RUN git clone --depth=1 https://github.com/ZLMediaKit/ZLMediaKit.git && \
    cd ZLMediaKit && git submodule update --init --recursive && \
    mkdir -p build release/linux/Release/

WORKDIR /opt/media/ZLMediaKit/build
RUN cmake -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_WEBRTC=true \
    -DENABLE_FFMPEG=true .. && \
    make -j $(nproc)

FROM scratch AS export-stage
COPY --from=stage1 /opt/media/ZLMediaKit/release/linux/Release/libmk_api.so bin/libmk_api.so
COPY --from=stage1 /opt/media/ZLMediaKit/api/include/** include/
COPY --from=stage1 /opt/media/ZLMediaKit/release/linux/Release/** lib/
