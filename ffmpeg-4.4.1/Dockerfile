FROM centos:7
RUN yum install -y wget autoconf automake bzip2 bzip2-devel \
    cmake freetype-devel gcc gcc-c++ git libtool make pkgconfig zlib-devel gcc gcc-c++ \
    && mkdir -pv /tmp/make && cd /tmp/make \
    # 下载源码文件
    && echo $'https://www.nasm.us/pub/nasm/releasebuilds/2.15.05/nasm-2.15.05.tar.bz2\n\
    https://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz\n\
    https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz\n\
    https://ffmpeg.org/releases/ffmpeg-4.4.1.tar.gz\n\
    https://archive.mozilla.org/pub/opus/opus-1.3.1.tar.gz\n' > wget.txt \
    && wget -e "https_proxy=http://192.168.0.159:7890" -i wget.txt --no-check-certificate \
    && git config --global http.proxy http://192.168.0.159:7890 \
    && git clone --branch stable --depth 1 https://code.videolan.org/videolan/x264.git \
    && git clone --branch stable --depth 2 https://bitbucket.org/multicoreware/x265_git \
    && git clone --depth 1 https://github.com/mstorsjo/fdk-aac \
    && git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git \
    # 编译
    && cd /tmp/make && tar xjvf nasm-2.15.05.tar.bz2 && cd nasm-2.15.05 && ./autogen.sh && ./configure && make -j 4 && make install \
    && cd /tmp/make && tar xzvf yasm-1.3.0.tar.gz && cd yasm-1.3.0 && ./configure && make -j 4 && make install \
    && cd /tmp/make && cd x264 && ./configure --enable-static --enable-shared  && make -j 4 && make install \
    && cd /tmp/make && cd x265_git/build/linux && cmake -G "Unix Makefiles" -DENABLE_SHARED:bool=off ../../source && make -j 4 && make install  \
    && cd /tmp/make && cd fdk-aac && autoreconf -fiv && ./configure --disable-shared &&  make -j 4 && make install \
    && cd /tmp/make && tar xzvf lame-3.100.tar.gz && cd lame-3.100 && ./configure --disable-shared --enable-nasm && make -j 4 && make install \
    && cd /tmp/make && tar xzvf opus-1.3.1.tar.gz && cd opus-1.3.1 && ./configure --disable-shared && make -j 4 && make install \
    && cd /tmp/make && cd libvpx && ./configure --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm && make -j 4 && make install \ 
    && cd /tmp/make && tar fx ffmpeg-4.4.1.tar.gz \
    && cd ffmpeg-4.4.1  \
    && PKG_CONFIG_PATH="/usr/local/lib/pkgconfig" ./configure \
    --pkg-config-flags="--static" \
    --extra-libs=-lpthread \
    --extra-libs=-lm \
    --enable-gpl \
    --enable-libfdk_aac \
    --enable-libfreetype \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libvpx \
    --enable-libx264 \
    --enable-libx265 \
    --enable-nonfree \
    --enable-parser=h264 \
    && make -j 4 && make install \
    && ldconfig /usr/local/lib && rm -rf /tmp/make && yum clean all && rm -rf /var/cache/yum/*
