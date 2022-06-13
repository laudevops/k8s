FROM centos:7
MAINTAINER zhangjt <zhangjt@xxx.com>

ENV TZ Asia/Shanghai
## pkgconfig dir env
ENV PKG_CONFIG_PATH $PKG_CONFIG_PATH:/usr/lib64/pkgconfig:/usr/local/lib/pkgconfig
ENV export PKG_CONFIG_PATH
## dynamic load path
ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:/usr/lib:/usr/lib64:/usr/local/lib:/usr/local/lib64
ENV export LD_LIBRARY_PATH
ENV PATH /usr/local/node-v14.16.0-linux-x64/bin:/usr/local/yarn-v1.22.5/bin:$PATH

RUN yum install -y epel-release \
    && mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup \
    && curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo \
    && sed -i -e '/mirrors.cloud.aliyuncs.com/d' -e '/mirrors.aliyuncs.com/d' /etc/yum.repos.d/CentOS-Base.repo \
    && yum clean all \
    && yum makecache \
    && yum install -y fftw fftw-devel fftw-devel bzip2 bzip2-devel freetype-devel libjpeg-devel libpng-devel libtiff-devel giflib-devel \
    zlib-devel ghostscript-devel djvulibre-devel libwmf-devel jasper-devel  libX11-devel libXext-devel libXt-devel lcms-devel libxml2-devel \
    librsvg2-devel OpenEXR-devel openjpeg openjpeg-devel  openjpeg2 openjpeg2-devel openjpeg2-libs  gcc gcc-c++  make cmake automake  libtool \
    libtool-ltdl-devel lcms2  lcms2-devel LibRaw LibRaw-devel net-tools wget ghostscript \
    && mkdir -pv  /opt/make \ 
    && cd /opt/make \
    # 下载ImageMagick和node二进制文件
    && echo $'https://nih.at/libzip/libzip-1.2.0.tar.gz\n\
    https://github.com/facebook/zstd/releases/download/v1.5.0/zstd-1.5.0.tar.gz\n\
    https://github.com/webmproject/libwebp/archive/refs/tags/v1.2.1.tar.gz\n\
    https://download.imagemagick.org/ImageMagick/download/delegates/liblqr-1-0.4.2.tar.bz2\n\
    https://www.nasm.us/pub/nasm/releasebuilds/2.13.03/nasm-2.13.03.tar.gz\n\
    https://bitbucket.org/multicoreware/x265_git/downloads/x265_3.3.tar.gz\n\
    https://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/l/libaom-3.1.1-1.el7.x86_64.rpm\n\
    https://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/l/libaom-devel-3.1.1-1.el7.x86_64.rpm\n\
    https://github.com/strukturag/libde265/releases/download/v1.0.8/libde265-1.0.8.tar.gz\n\
    https://github.com/strukturag/libheif/releases/download/v1.12.0/libheif-1.12.0.tar.gz\n\
    https://download.imagemagick.org/ImageMagick/download/ImageMagick-7.1.0-29.tar.gz\n\
    https://nodejs.org/dist/v14.16.0/node-v14.16.0-linux-x64.tar.gz\n\
    https://yarnpkg.com/downloads/1.22.5/yarn-v1.22.5.tar.gz\n' > wget.txt \
    && wget -e "https_proxy=http://192.168.0.159:7890" -i wget.txt --no-check-certificate \
    # install libzip
    && cd /opt/make && tar -zxvf libzip-1.2.0.tar.gz && cd libzip-1.2.0 && ./configure && make -j 4 && make install \
    # install zstd
    && cd /opt/make && tar -zxvf zstd-1.5.0.tar.gz && cd zstd-1.5.0 && make -j 4 && make install \
    # install liblqr
    && cd /opt/make  && tar -xjf liblqr-1-0.4.2.tar.bz2 && cd liblqr-1-0.4.2  && ./configure && make -j 4 && make install  \
    # install libwep
    && cd /opt/make  && tar -zxvf v1.2.1.tar.gz && cd libwebp-1.2.1 && ./autogen.sh  && ./configure && make -j 4 && make install  \
    # install nasm
    && cd /opt/make  && tar -zxvf nasm-2.13.03.tar.gz && cd nasm-2.13.03 &&  ./autogen.sh && ./configure && make -j 4  && make install \ 
    # install x265
    && cd /opt/make && tar -zxvf x265_3.3.tar.gz && cd x265_3.3/build/linux &&  cmake -j 4  -G "Unix Makefiles" ../../source  && make -j 4 && make install \
    # install aom
    && cd /opt/make && rpm -ivh libaom-3.1.1-1.el7.x86_64.rpm  && rpm -ivh libaom-devel-3.1.1-1.el7.x86_64.rpm \
    # install libde265
    && cd /opt/make && tar -zxvf libde265-1.0.8.tar.gz && cd libde265-1.0.8 && ./autogen.sh && ./configure && make -j 4 && make install \
    && cd /opt/make && tar -zxvf libheif-1.12.0.tar.gz && cd libheif-1.12.0 && ./autogen.sh && ./configure && make -j 4 && make install \ 
    # install magick
    && cd /opt/make && tar -zxvf ImageMagick-7.1.0-29.tar.gz && cd ImageMagick-7.1.0-29  && ./configure && make -j 4  && make install \
    # 安装node 环境
    && cd /opt/make && tar fx node-v14.16.0-linux-x64.tar.gz -C /usr/local \
    && tar fx yarn-v1.22.5.tar.gz -C /usr/local \
    && ldconfig /usr/local/lib \
    && rm -rf /opt/make \
    && yum clean all \
    && rm -rf /var/cache/yum/*
