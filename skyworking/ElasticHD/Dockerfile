FROM alpine:latest

ADD ElasticHD.tar.gz /usr/sbin
    # https://github.com/farmerx/ElasticHD/releases/download/1.4/elasticHD_linux_amd64.zip && unzip elasticHD_linux_amd64.zip && tar -zcvf ElasticHD.tar.gz

RUN adduser -D elastic

USER elastic

EXPOSE 9800

ENTRYPOINT ["ElasticHD"]
