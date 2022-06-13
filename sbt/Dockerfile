FROM centos:7

ENV SBT_VERSION 1.5.2
ENV JAVA_HOME /usr/java/latest
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/java/latest/bin
ENV TZ Asia/Shanghai
RUN  yum -y install wget unzip telnet vim net-tools && wget http://edas-hz.oss-cn-hangzhou.aliyuncs.com/agent/prod/files/jdk-8u191-linux-x64.rpm -O /tmp/jdk-8u191-linux-x64.rpm && yum -y install  /tmp/jdk-8u191-linux-x64.rpm  && rm -rf /tmp/jdk-8u191-linux-x64.rpm &&  rm -rf /var/cache/yum/* && yum clean all

RUN curl -L https://www.scala-sbt.org/sbt-rpm.repo > /etc/yum.repos.d/sbt-rpm.repo && yum install sbt-1.5.8-0 -y 
