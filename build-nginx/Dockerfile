FROM  centos:7
MAINTAINER Zhangjt<Zhangjt@shinemo.com>

ADD nginx_build.tar.gz openssl-1.1.1e.tar.gz tengine-2.3.3.tar.gz /tmp/

ADD CentOS-Base.repo epel.repo /etc/yum.repos.d/

RUN groupadd -g 2049 admin && useradd -g 2049 -u 2049 admin

RUN yum install -y gcc gcc-c++ make openssl-devel pcre-devel  flex bison yajl yajl-devel curl-devel curl GeoIP-devel doxygen zlib-devel lmdb-devel libxml2-devel ssdeep-devel libtool autoconf automake unzip && yum makecache fast && \ 
    cd /tmp/tengine-2.3.3 && \
    ./configure --prefix=/home/admin/nginx --user=admin --group=admin --with-pcre=../pcre-8.43 --with-pcre-jit --with-file-aio --with-threads --with-http_realip_module --with-http_addition_module --with-http_mp4_module --with-http_secure_link_module --with-http_gunzip_module --with-http_auth_request_module --with-http_degradation_module --with-http_slice_module --with-stream --with-stream_ssl_module --with-stream_realip_module --with-stream_sni --with-stream_ssl_preread_module --with-http_v2_module --with-http_gzip_static_module --with-http_realip_module --with-http_stub_status_module --with-ipv6 --add-module=../ngx_devel_kit  --add-module=../echo-nginx-module --add-module=../redis2-nginx-module --add-module=../set-misc-nginx-module --add-module=./modules/ngx_http_concat_module --add-module=./modules/ngx_http_reqstat_module  --add-module=./modules/ngx_http_upstream_check_module --add-module=./modules/ngx_http_upstream_consistent_hash_module --add-module=./modules/ngx_http_upstream_dynamic_module --add-module=./modules/ngx_http_upstream_dyups_module --add-module=./modules/ngx_http_upstream_session_sticky_module --with-zlib=../zlib-1.2.8 --with-openssl=../openssl-1.1.1e --with-http_sub_module && \
    make -j 4 && \
    make install && \
    rm -rf /tmp/nginx_build* /tmp/openssl-1.1.1e* /tmp/tengine-2.3.2*  && \
    rm -rf /var/cache/yum/* && yum clean all && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo 'Asia/Shanghai' >/etc/timezone

FROM centos:7
RUN groupadd -g 2049 admin && useradd -g 2049 -u 2049 admin && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo 'Asia/Shanghai' >/etc/timezone
WORKDIR /home/admin
COPY --from=0 /home/admin/nginx/ ./nginx
COPY nginx.conf /home/admin/nginx/conf/nginx.conf
RUN mkdir /home/admin/nginx/conf/vhost && chown admin.admin /home/admin/ -R 
COPY  default.conf /home/admin/nginx/conf/vhost/default.conf
EXPOSE 8080
CMD ["./nginx/sbin/nginx", "-g", "daemon off;"]
