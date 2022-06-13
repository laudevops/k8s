FROM registry.suse.com/suse/sles12sp3:latest
ENV JAVA_HOME /usr/local/java
ENV PATH $PATH:/usr/local/java/bin
ENV TZ Asia/Shanghai
ENV LANG en_US.UTF-8
COPY tar wget /usr/bin/
RUN cd /tmp && wget http://192.168.0.159:21000/download/jre-8u191-linux-x64.tar.gz \
     && tar fx jre-8u191-linux-x64.tar.gz \
     && mv jre1.8.0_191/ /usr/local/java \
     && rm -rf /tmp/jre*
