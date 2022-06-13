####### 节点清单
```
IP        HOSTNAME        ROLE
192.168.0.13        k8s-01        master&node
192.168.0.14        k8s-02        master&node
192.168.0.15        k8s-03        master&node
192.168.0.16        k8s-04        node
192.168.0.18        k8s-05        node
192.168.0.19        vip
注：提前配置静态IP
```
####### 服务版本
```
SERVER        VERSION
Kubernetes    1.19.7
Etcd          3.4.12
Docker        19.03.9
Flannel       0.12.0
```
####### 操作系统
```
# cat /etc/os-release
NAME="SLES"
VERSION="12-SP3"
VERSION_ID="12.3"
PRETTY_NAME="SUSE Linux Enterprise Server 12 SP3"
ID="sles"
ANSI_COLOR="0;32"
CPE_NAME="cpe:/o:suse:sles:12:sp3"

# uname -r
4.4.73-5-default

注：suse 12 sp3默认的内核是4.4.73的，如内核版本小于4.x，则需要升级内核，因为Docker overlay2需要使用kernel 4.x版本
官方文档：对于运行 Linux 内核版本 4.0 或更高版本，或使用 3.10.0-51 及更高版本的 RHEL 或 CentOS 的系统，overlay2是首选的存储驱动程序。
k8s-master 的配置不能小于2c2g，k8s-node 可以给1c1g，集群为奇数，所以不能少于3个master，master和node节点可以复用，8G内存玩起来会很憋屈，玩过的都知道（哭唧唧~~~）
/etc/sysconfig/network/dhcp文件中，将DHCLIENT_SET_HOSTNAME="yes"改为no。
```

# 一、环境准备
###### 没有特别说明的话默认在k8s-01操作
0.1、添加hosts解析
```
# cat >> /etc/hosts <<EOF
192.168.0.13 k8s-01
192.168.0.14 k8s-02
192.168.0.15 k8s-03
192.168.0.16 k8s-04
192.168.0.18 k8s-05
EOF
```
0.2、配置ssh免密
```
# rpm -qa | grep expect
expect-5.45-18.56.x86_64

"如果没有expect，则执行如下操作（注：需要网络或者本地源）"
# zypper in expect

#!/usr/bin/env bash
ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa -q
for host in k8s-01 k8s-02 k8s-03 k8s-04 k8s-05
do
    expect -c "
    spawn ssh-copy-id -i /root/.ssh/id_rsa.pub root@${host}
        expect {
                \"*yes/no*\" {send \"yes\r\"; exp_continue}
                \"*Password*\" {send \"123456\r\"; exp_continue}
                \"*Password*\" {send \"123456\r\";}
               }"
done

注：我本机的密码是 1233456 ，注意修改成自己本机的密码
```
0.3环境初始化脚本脚本.切记，需要先完成免密和hosts文件创建脚本
```
# cat k8s-init.sh
#!/usr/bin/env bash

cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF

cat >> /etc/rc.d/rc.local <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
modprobe -- br_netfilter
EOF

for host in k8s-01 k8s-02 k8s-03 k8s-04 k8s-05
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /etc/hosts ${host}:/etc/hosts
    scp /etc/sysctl.d/kubernetes.conf ${host}:/etc/sysctl.d/kubernetes.conf
    scp /etc/rc.d/rc.local ${host}:/etc/rc.d/rc.local
    ssh root@${host} "hostnamectl set-hostname --static ${host}"
    ssh root@${host} "zypper addrepo http://download.opensuse.org/repositories/devel:/tools:/scm/SLE_12_SP5/devel:tools:scm.repo"
    ssh root@${host} "zypper in -y ntp ipset iptables curl sysstat wget openssl-devel gcc lrzsz git-core"
    ssh root@${host} "swapoff -a"
    ssh root@${host} "sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab"
    ssh root@${host} "modprobe -- ip_vs && \
                      modprobe -- ip_vs_rr && \
                      modprobe -- ip_vs_wrr && \
                      modprobe -- ip_vs_sh && \
                      modprobe -- nf_conntrack_ipv4 && \
                      modprobe -- br_netfilter"
    ssh root@${host} "chmod +x /etc/rc.d/rc.local"
    ssh root@${host} "sysctl -p /etc/sysctl.d/kubernetes.conf"
    ssh root@${host} "systemctl disable SuSEfirewall2.service --now"
    ssh root@${host} "iptables -F && iptables -X && \
                      iptables -F -t nat && iptables -X -t nat && \
                      iptables -P FORWARD ACCEPT"
    ssh root@${host} "echo 'PATH=$PATH:/opt/k8s/bin' >> /etc/profile"
    ssh root@${host} "source /etc/profile"
    ssh root@${host} "mkdir -p /opt/k8s/{bin,packages,ssl,conf,server} /etc/{kubernetes,etcd}/cert"
done

# sh  k8s-init.sh
```

0.4、配置脚本参数文件
后续的部署，将直接使用变量进行代替，以减少出错的概率，相关的信息，请修改成自己的环境信息，并分发到所有节点的 /opt/k8s/bin 目录下，文件名称为 k8s-env.sh
```
echo '#!/usr/bin/env bash
# 集群各机器 IP 数组
export NODE_IPS=( 192.168.0.13 192.168.0.14 192.168.0.15 192.168.0.16 192.168.0.18 )

# 集群各 IP 对应的主机名数组
export NODE_NAMES=( k8s-01 k8s-02 k8s-03 k8s-04 k8s-05 )

# 集群MASTER机器 IP 数组
export MASTER_IPS=( 192.168.0.13 192.168.0.14 192.168.0.15 )

# 集群所有的master Ip对应的主机
export MASTER_NAMES=( k8s-01 k8s-02 k8s-03 )

# etcd 集群服务地址列表
export ETCD_ENDPOINTS="https://192.168.0.13:2379,https://192.168.0.14:2379,https://192.168.0.15:2379"

# etcd 集群间通信的 IP 和端口
export ETCD_NODES="k8s-01=https://192.168.0.13:2380,k8s-02=https://192.168.0.14:2380,k8s-03=https://192.168.0.15:2380"

# etcd 集群所有node ip
export ETCD_IPS=( 192.168.0.13 192.168.0.14 192.168.0.15 )

# etcd 数据目录
export ETCD_DATA_DIR="/opt/k8s/server/etcd/data"

# etcd WAL 目录，建议是 SSD 磁盘分区，或者和 ETCD_DATA_DIR 不同的磁盘分区
export ETCD_WAL_DIR="/opt/k8s/server/etcd/wal"

# kube-apiserver 的反向代理(kube-nginx)地址端口，如果有配置keepalived，可以写VIP
export KUBE_APISERVER="https://192.168.0.19:8443"

# k8s 各组件数据目录
export K8S_DIR="/opt/k8s/server/k8s"

# 最好使用 当前未用的网段 来定义服务网段和 Pod 网段
# 服务网段，部署前路由不可达，部署后集群内路由可达(kube-proxy 保证)
SERVICE_CIDR="10.254.0.0/16"

# Pod 网段，建议 /16 段地址，部署前路由不可达，部署后集群内路由可达(flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort Range)
export NODE_PORT_RANGE="30000-32767"

# flanneld 网络配置前缀
export FLANNEL_ETCD_PREFIX="/kubernetes/network"

# kubernetes 服务 IP (一般是 SERVICE_CIDR 中第一个IP)
export CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名（末尾不带点号）
export CLUSTER_DNS_DOMAIN="cluster.local"

# 将二进制目录 /opt/k8s/bin 加到 PATH 中
export PATH=$PATH:/opt/k8s/bin
' > /opt/k8s/bin/k8s-env.sh
```

# 二、kubernetes集群部署
1、kubernetes集群部署
```
注：若没有特别指明操作的节点，默认所有操作均在k8s-01节点中执行
kubernetes master 节点运行组件：etcd、kube-apiserver、kube-controller-manager、kube-scheduler
kubernetes node 节点运行组件：docker、calico、kubelet、kube-proxy、coredns
```

1.0、创建CA证书和秘钥
```
为确保安全，kubernetes各个组件需要使用x509证书对通信进行加密和认证
CA(Certificate Authority)是自签名的根证书，用来签名后续创建的其他证书
使用CloudFlare的PKI工具cfssl创建所有证书
```
1.0.0、安装cfssl工具
```
# cd /opt/k8s/packages/
# wget https://github.com/cloudflare/cfssl/releases/download/v1.6.1/cfssl_1.6.1_linux_amd64
# wget https://github.com/cloudflare/cfssl/releases/download/v1.6.1/cfssljson_1.6.1_linux_amd64
# wget https://github.com/cloudflare/cfssl/releases/download/v1.6.1/cfssl-certinfo_1.6.1_linux_amd64

# mv cfssl_1.6.1_linux_amd64 /opt/k8s/bin/cfssl
# mv cfssljson_1.6.1_linux_amd64 /opt/k8s/bin/cfssljson
# mv cfssl-certinfo_1.6.1_linux_amd64 /opt/k8s/bin/cfssl-certinfo
# chmod +x /opt/k8s/bin/*
```

1.0.1、创建根证书
```
# cd /opt/k8s/ssl/
# cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "876000h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "876000h"
      }
    }
  }
}
EOF

signing 表示该证书可用于签名其它证书，生成的ca.pem证书找中CA=TRUE
server auth 表示client可以用该证书对server提供的证书进行验证
client auth 表示server可以用该证书对client提供的证书进行验证
```

1.0.2、创建证书签名请求文件
```
# cat > ca-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "bandian"
    }
  ],
  "ca": {
    "expiry": "876000h"
}
}
EOF

CN:CommonName kube-apiserver从证书中提取该字段作为请求的用户名(User Name)，浏览器使用该字段验证网站是否合法
O :Organization kube-apiserver从证书中提取该字段作为请求的用户和所属组(Group)
kube-apiserver将提取的User、Group作为RBAC授权的用户和标识
```

1.0.3、生成CA证书和秘钥
```
# source /opt/k8s/bin/k8s-env.sh
# cfssl gencert -initca ca-csr.json | cfssljson -bare ca
```

1.0.4、分发CA证书到所有节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /opt/k8s/ssl/ca* ${host}:/opt/k8s/ssl/
done
```

1.1、安装二进制文件
```
kubernetes二进制包的github网址
https://github.com/kubernetes/kubernetes/tree/master/CHANGELOG
```
```
# cd /opt/k8s/packages/
# wget https://dl.k8s.io/v1.19.7/kubernetes-server-linux-amd64.tar.gz
# wget http://ftp.pbone.net/mirror/ftp.opensuse.org/distribution/leap/15.3/repo/oss/x86_64/ipvsadm-1.29-4.3.1.x86_64.rpm
# tar xf kubernetes-server-linux-amd64.tar.gz
```

1.1.0、分发二进制文件到所有节点（node节点只需要kubelet和kube-proxy）
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /opt/k8s/packages/kubernetes/server/bin/* ${host}:/opt/k8s/bin
    ssh root@${host} "kubectl completion bash > /etc/bash_completion.d/kubectl"
done

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /opt/k8s/packages/kubernetes/server/bin/kubelet ${host}:/opt/k8s/bin
    scp /opt/k8s/packages/kubernetes/server/bin/kube-proxy ${host}:/opt/k8s/bin
    scp /opt/k8s/packages/ipvsadm-1.29-4.3.1.x86_64.rpm ${host}:/tmp/ipvsadm-1.29-4.3.1.x86_64.rpm
    ssh root@${host} "rpm -ivh /tmp/ipvsadm-1.29-4.3.1.x86_64.rpm"
done


kubectl completion bash > /etc/bash_completion.d/kubectl 配置kubectl命令自动补全，依赖bash-completion，如果没有，需要先安装bash-completion（suse一般都自带，centos发行版需要执行yum -y install bash-completion）
```

1.1.1、创建admin证书和秘钥
kubectl作为集群的管理工具，需要被授予最高权限，这里创建具有最高权限的admin证书
kubectl与apiserver进行https通信，apiserver对提供的证书进行认证和授权
```
# cd /opt/k8s/ssl/
# cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "system:masters",
      "OU": "bandian"
    }
  ]
}
EOF


O 为system:masters，kube-apiserver收到该证书后将请求的Group设置为system:masters
预定的ClusterRoleBinding cluster-admin将Group system:masters与Role cluster-admin绑定，该Role授予API的权限
该证书只有被kubectl当做client证书使用，所以hosts字段为空
```

1.1.2、生成admin证书和秘钥
```
# cfssl gencert -ca=/opt/k8s/ssl/ca.pem \
-ca-key=/opt/k8s/ssl/ca-key.pem \
-config=/opt/k8s/ssl/ca-config.json \
-profile=kubernetes admin-csr.json | cfssljson -bare admin
```

1.1.3、创建kubeconfig文件
```
# source /opt/k8s/bin/k8s-env.sh

# "设置集群参数"
# kubectl config set-cluster kubernetes \
--certificate-authority=/opt/k8s/ssl/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=kubectl.kubeconfig

# "设置客户端认证参数"
# kubectl config set-credentials admin \
--client-certificate=/opt/k8s/ssl/admin.pem \
--client-key=/opt/k8s/ssl/admin-key.pem \
--embed-certs=true \
--kubeconfig=kubectl.kubeconfig

# "设置上下文参数"
# kubectl config set-context kubernetes \
--cluster=kubernetes \
--user=admin \
--kubeconfig=kubectl.kubeconfig

# "设置默认上下文"
# kubectl config use-context kubernetes --kubeconfig=kubectl.kubeconfig

--certificate-authority 验证kube-apiserver证书的根证书
--client-certificate、--client-key 刚生成的admin证书和私钥，连接kube-apiserver时使用
--embed-certs=true 将ca.pem和admin.pem证书嵌入到生成的kubectl.kubeconfig文件中 (如果不加入，写入的是证书文件路径，后续拷贝kubeconfig到其它机器时，还需要单独拷贝证书)
```

1.1.4、分发kubeconfig文件
分发到使用kubectl命令的节点（一般在master上管理）
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir ~/.kube"
    scp /opt/k8s/ssl/kubectl.kubeconfig ${host}:~/.kube/config
done
```

1.2、部署etcd集群
```
所有master节点需要etcd（复用master节点，也可以独立三节点部署etcd，只要kubernetes集群可以访问即可）
```

1.2.0、下载etcd二进制文件
```
# cd /opt/k8s/packages/
# wget https://github.com/etcd-io/etcd/releases/download/v3.4.12/etcd-v3.4.12-linux-amd64.tar.gz
# tar xf etcd-v3.4.12-linux-amd64.tar.gz
```

1.2.1、创建etcd证书和私钥
```
# cd /opt/k8s/ssl
# cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "192.168.0.13",
    "192.168.0.14",
    "192.168.0.15"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "bandian"
    }
  ]
}
EOF

host字段指定授权使用该证书的etcd节点IP或域名列表，需要将etcd集群的3个节点都添加其中
```

1.2.2、生成etcd证书和私钥
```
# cfssl gencert -ca=/opt/k8s/ssl/ca.pem \
-ca-key=/opt/k8s/ssl/ca-key.pem \
-config=/opt/k8s/ssl/ca-config.json \
-profile=kubernetes etcd-csr.json | cfssljson -bare etcd
```

1.2.3、配置etcd为systemctl管理
```
# cd /opt/k8s/conf/
# source /opt/k8s/bin/k8s-env.sh
# cat > etcd.service.template <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos
[Service]
Type=notify
WorkingDirectory=${ETCD_DATA_DIR}
ExecStart=/opt/k8s/bin/etcd \\
  --data-dir=${ETCD_DATA_DIR} \\
  --wal-dir=${ETCD_WAL_DIR} \\
  --name=##NODE_NAME## \\
  --cert-file=/opt/k8s/ssl/etcd.pem \\
  --key-file=/opt/k8s/ssl/etcd-key.pem \\
  --trusted-ca-file=/opt/k8s/ssl/ca.pem \\
  --peer-cert-file=/opt/k8s/ssl/etcd.pem \\
  --peer-key-file=/opt/k8s/ssl/etcd-key.pem \\
  --peer-trusted-ca-file=/opt/k8s/ssl/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --listen-peer-urls=https://##NODE_IP##:2380 \\
  --initial-advertise-peer-urls=https://##NODE_IP##:2380 \\
  --listen-client-urls=https://##NODE_IP##:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://##NODE_IP##:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --auto-compaction-mode=periodic \\
  --auto-compaction-retention=1 \\
  --max-request-bytes=33554432 \\
  --quota-backend-bytes=6442450944 \\
  --heartbeat-interval=250 \\
  --election-timeout=2000 \\
  --enable-v2=true
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

WorkDirectory、--data-dir 指定etcd工作目录和数据存储为${ETCD_DATA_DIR},需要在启动前创建这个目录 (后面会有创建步骤)
--wal-dir 指定wal目录，为了提高性能，一般使用SSD和–data-dir不同的盘
--name 指定节点名称，当–initial-cluster-state值为new时，–name的参数值必须位于–initial-cluster列表中
--cert-file、--key-file etcd server与client通信时使用的证书和私钥
--trusted-ca-file 签名client证书的CA证书，用于验证client证书
--peer-cert-file、--peer-key-file etcd与peer通信使用的证书和私钥
--peer-trusted-ca-file 签名peer证书的CA证书，用于验证peer证书
```

1.2.4、分发etcd证书和启动文件到其他etcd节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for (( i=0; i < 3; i++ ))
do
    sed -e "s/##NODE_NAME##/${MASTER_NAMES[i]}/" \
        -e "s/##NODE_IP##/${ETCD_IPS[i]}/" \
        /opt/k8s/conf/etcd.service.template > /opt/k8s/conf/etcd-${ETCD_IPS[i]}.service
done

# for host in ${ETCD_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /opt/k8s/packages/etcd-v3.4.12-linux-amd64/etcd* ${host}:/opt/k8s/bin/
    scp /opt/k8s/conf/etcd-${host}.service ${host}:/etc/systemd/system/etcd.service
    scp /opt/k8s/ssl/etcd*.pem ${host}:/opt/k8s/ssl/
done
```

1.2.5、配置并启动etcd服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${ETCD_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p ${ETCD_DATA_DIR} ${ETCD_WAL_DIR}"
    ssh root@${host} "chmod 700 ${ETCD_DATA_DIR}"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable etcd && \
                      systemctl restart etcd && \
                      systemctl status etcd | grep Active"
done

如果第一个回显是failed，先别着急取消，若后面两个节点的回显是running就没有问题了，这是集群的机制，如下显示是正常的
192.168.0.13
Created symlink from /etc/systemd/system/multi-user.target.wants/etcd.service to /etc/systemd/system/etcd.service.
   Active: active (running) since Wed 2022-04-27 16:53:57 CST; 3ms ago
192.168.0.14
Created symlink from /etc/systemd/system/multi-user.target.wants/etcd.service to /etc/systemd/system/etcd.service.
Job for etcd.service failed because a timeout was exceeded. See "systemctl status etcd.service" and "journalctl -xe" for details.
192.168.0.15
Created symlink from /etc/systemd/system/multi-user.target.wants/etcd.service to /etc/systemd/system/etcd.service.
   Active: active (running) since Wed 2022-04-27 16:55:37 CST; 3ms ago

```

1.2.6、验证etcd集群状态
在k8s-01机器执行就可以了，既然是集群，在哪执行，都是可以获取到信息的
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${ETCD_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ETCDCTL_API=3 /opt/k8s/bin/etcdctl \
    --endpoints=https://${host}:2379 \
    --cacert=/opt/k8s/ssl/ca.pem \
    --cert=/opt/k8s/ssl/etcd.pem \
    --key=/opt/k8s/ssl/etcd-key.pem endpoint health
done

如下显示successfully committed proposal则表示集群正常
192.168.0.13
https://192.168.0.13:2379 is healthy: successfully committed proposal: took = 8.032286ms
192.168.0.14
https://192.168.0.14:2379 is healthy: successfully committed proposal: took = 13.806446ms
192.168.0.15
https://192.168.0.15:2379 is healthy: successfully committed proposal: took = 8.747518ms

```

1.3、部署flannel网络
```
所有节点都需要flannel
```
1.3.0、下载flannel二进制文件
```
# cd /opt/k8s/packages/
# mkdir flannel
# wget https://github.com/coreos/flannel/releases/download/v0.12.0/flannel-v0.12.0-linux-amd64.tar.gz
# tar xf flannel-v0.12.0-linux-amd64.tar.gz -C /opt/k8s/packages/flannel/
```

1.3.1、创建flannel证书和私钥
```
# cd /opt/k8s/ssl/
# cat > flanneld-csr.json <<EOF
{
  "CN": "flanneld",
  "hosts": [
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "bandian"
    }
  ]
}
EOF
```

1.3.2、生成flannel证书和私钥
```
# cfssl gencert -ca=/opt/k8s/ssl/ca.pem \
-ca-key=/opt/k8s/ssl/ca-key.pem \
-config=/opt/k8s/ssl/ca-config.json \
-profile=kubernetes flanneld-csr.json | cfssljson -bare flanneld
```

1.3.3、将pod网段写入etcd
```
# cd /opt/k8s/ssl/
# source /opt/k8s/bin/k8s-env.sh
# ETCDCTL_API=2 etcdctl \
--endpoints=${ETCD_ENDPOINTS} \
--ca-file=/opt/k8s/ssl/ca.pem \
--cert-file=/opt/k8s/ssl/flanneld.pem \
--key-file=/opt/k8s/ssl/flanneld-key.pem \
mk ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 21, "Backend": {"Type": "vxlan"}}'

因为flannel当前版本0.12.0不支持etcd v3，因此需要使用etcd v2 API写入配置，否则后面启动flanneld会找不到写入的key
```

1.3.4、配置flannel为systemctl管理
```
# cd /opt/k8s/conf/
# source /opt/k8s/bin/k8s-env.sh
# cat > flanneld.service << EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service
[Service]
Type=notify
ExecStart=/opt/k8s/bin/flanneld \\
  -etcd-cafile=/opt/k8s/ssl/ca.pem \\
  -etcd-certfile=/opt/k8s/ssl/flanneld.pem \\
  -etcd-keyfile=/opt/k8s/ssl/flanneld-key.pem \\
  -etcd-endpoints=${ETCD_ENDPOINTS} \\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX}
ExecStartPost=/opt/k8s/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=always
RestartSec=5
StartLimitInterval=0
[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF

mk-docker-opts.sh 脚本将分配给 flanneld 的 Pod 子网段信息写入 /run/flannel/docker 文件，后续 docker 启动时使用这个文件中的环境变量配置 docker0 网桥
flanneld 使用系统缺省路由所在的接口与其它节点通信，对于有多个网络接口（如内网和公网）的节点，可以用 -iface 参数指定通信接口
-ip-masq flanneld 为访问 Pod 网络外的流量设置 SNAT 规则，同时将传递给 Docker 的变量 -ip-masq（/run/flannel/docker 文件中）设置为 false，这样 Docker 将不再创建 SNAT 规则；
Docker 的 -ip-masq 为 true 时，创建的 SNAT 规则比较“暴力”：将所有本节点 Pod 发起的、访问非 docker0 接口的请求做 SNAT，这样访问其他节点 Pod 的请求来源 IP 会被设置为 flannel.1 接口的 IP，导致目的 Pod 看不到真实的来源 Pod IP。
flanneld 创建的 SNAT 规则比较温和，只对访问非 Pod 网段的请求做 SNAT。
```

1.3.5、分发flannel证书和启动文件到所有节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p /opt/k8s/ssl"
    scp /opt/k8s/ssl/flanneld*.pem ${host}:/opt/k8s/ssl/
    scp /opt/k8s/packages/flannel/{flanneld,mk-docker-opts.sh} ${host}:/opt/k8s/bin/
    scp /opt/k8s/conf/flanneld.service ${host}:/etc/systemd/system/
done
```

1.3.6、配置并启动flannel服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable flanneld && \
                      systemctl restart flanneld && \
                      systemctl status flanneld | grep Active"
done
```

1.3.7、查看已分配的pod网段列表
```
# ETCDCTL_API=2 etcdctl \
--endpoints=${ETCD_ENDPOINTS} \
--ca-file=/opt/k8s/ssl/ca.pem \
--cert-file=/opt/k8s/ssl/flanneld.pem \
--key-file=/opt/k8s/ssl/flanneld-key.pem \
ls ${FLANNEL_ETCD_PREFIX}/subnets
```

1.3.8、查看各节点是否都存在flannel网卡
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "ip a | grep flannel | grep -w inet"
done
```

1.4、部署docker
```
所有节点都需要docker（复用master节点为node节点运行pod）
```
1.4.0、下载docker二进制文件
```
# cd /opt/k8s/packages/
# wget https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/static/stable/x86_64/docker-19.03.9.tgz --no-check-certificate
# tar xf docker-19.03.9.tgz
```

1.4.1、配置docker镜像加速
```
# cd /opt/k8s/conf/
# cat > daemon.json <<-EOF
{
  "registry-mirrors": ["https://bk6kzfqm.mirror.aliyuncs.com"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
```

1.4.2、配置docker为systemctl管理
```
# cat > docker.service <<-EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd  \$DOCKER_NETWORK_OPTIONS
EnvironmentFile=-/run/flannel/docker
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutSec=0
RestartSec=2
Restart=always

# Note that StartLimit* options were moved from "Service" to "Unit" in systemd 229.
# Both the old, and new location are accepted by systemd 229 and up, so using the old location
# to make them work for either version of systemd.
StartLimitBurst=3

# Note that StartLimitInterval was renamed to StartLimitIntervalSec in systemd 230.
# Both the old, and new name are accepted by systemd 230 and up, so using the old name to make
# this option work for either version of systemd.
StartLimitInterval=60s

# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity

# Comment TasksMax if your systemd version does not support it.
# Only systemd 226 and above support this option.
TasksMax=infinity

# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes

# kill only the docker process, not all processes in the cgroup
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
```

1.4.3、启动docker服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir /etc/docker"
    scp /opt/k8s/packages/docker/* ${host}:/usr/bin/
    scp /opt/k8s/conf/daemon.json ${host}:/etc/docker/
    scp /opt/k8s/conf/docker.service ${host}:/etc/systemd/system/
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable docker --now && \
                      systemctl status docker | grep Active"
done
```

1.4.4、查看所有节点docker和flannel的网卡是否为同一网段
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} 'ifconfig | egrep "docker*|flannel*" -A 1'
done
```

1.5、部署kube-nginx
```
master节点需要kube-nginx
使用Nginx 4层透明代理功能实现k8s节点(master节点和nginx节点)高可用访问kube-apiserver
控制节点的kube-controller-manager、kube-scheduler是多实例部署，所以只要一个实例正常，就可以保证集群高可用
集群内的Pod使用k8s服务域名kubernetes访问kube-apiserver，kube-dns会自动解析多个kube-apiserver节点的IP，所以也是高可用的
在每个Nginx进程，后端对接多个apiserver实例，Nginx对他们做健康检查和负载均衡
```

1.5.0、下载nginx二进制文件
```
# cd /opt/k8s/packages/
# wget http://nginx.org/download/nginx-1.16.1.tar.gz
tar xf nginx-1.16.1.tar.gz
```

1.5.1、编译部署nginx
```
# cd /opt/k8s/packages/nginx-1.16.1/ && mkdir -pv /opt/k8s/nginx
# ./configure --prefix=/opt/k8s/nginx \
--with-stream \
--without-http \
--without-http_uwsgi_module && \
make -j 4 && \
make install

--with-stream 开启 4 层透明转发(TCP Proxy)功能
--without-xxx 关闭功能，这样生成的动态链接二进制程序依赖最小
```

1.5.2、配置nginx.conf
```
# cd /opt/k8s/nginx/conf/
# cat > nginx.conf <<EOF
worker_processes 1;
events {
    worker_connections  1024;
}
stream {
    upstream backend {
        hash \$remote_addr consistent;
        server 192.168.0.13:6443        max_fails=3 fail_timeout=30s;
        server 192.168.0.14:6443        max_fails=3 fail_timeout=30s;
        server 192.168.0.15:6443        max_fails=3 fail_timeout=30s;
    }
    server {
        listen *:8443;
        proxy_connect_timeout 1s;
        proxy_pass backend;
    }
}
EOF
```

1.5.3、配置nginx为systemctl管理
```
# cd /opt/k8s/conf/
# cat > kube-nginx.service <<EOF
[Unit]
Description=kube-apiserver nginx proxy
After=network.target
After=network-online.target
Wants=network-online.target
[Service]
Type=forking
ExecStartPre=/opt/k8s/nginx/sbin/nginx \
          -c /opt/k8s/nginx/conf/nginx.conf \
          -p /opt/k8s/nginx -t
ExecStart=/opt/k8s/nginx/sbin/nginx \
       -c /opt/k8s/nginx/conf/nginx.conf \
       -p /opt/k8s/nginx
ExecReload=/opt/k8s/nginx/sbin/nginx \
        -c /opt/k8s/nginx/conf/nginx.conf \
        -p /opt/k8s/nginx -s reload
PrivateTmp=true
Restart=always
RestartSec=5
StartLimitInterval=0
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
```

1.5.4、分发nginx二进制文件和配置文件
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp  -r /opt/k8s/nginx ${host}:/opt/k8s/
    scp /opt/k8s/conf/kube-nginx.service ${host}:/etc/systemd/system/
done
```

1.5.5、启动kube-nginx服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable kube-nginx --now && \
                      systemctl status kube-nginx | grep Active"
done
```
1.5.6、编译部署keepalived
```
# cd /opt/k8s/packages/
# wget https://www.keepalived.org/software/keepalived-2.2.0.tar.gz --no-check-certificate
# tar xf keepalived-2.2.0.tar.gz &&  cd keepalived-2.2.0

# 编译keepalived
# ./configure --prefix=$(pwd)/keepalived-prefix && \
make -j 4 && \
make install

# 配置keepalived.conf
# cd /opt/k8s/conf/
# cat > keepalived.conf.template <<EOF
! Configuration File for keepalived
global_defs {
}
vrrp_script chk_nginx {
    script "/etc/keepalived/check_port.sh"
    interval 3
    fall 2

}
vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 251
    priority 100
    advert_int 1
    mcast_src_ip ##NODE_IP##
    nopreempt
    authentication {
        auth_type PASS
        auth_pass 11111111
    }
    track_script {
         chk_nginx
    }
    virtual_ipaddress {
        192.168.0.19
    }
}
EOF

为了避免keepalived服务出现问题，修复后重启keepalived，出现IP漂移回来的情况，这里选择了3个都是BACKUP的模式，减少数据的丢失
```

1.5.7、 创建健康检测脚本
```
# cd /opt/k8s/conf/
# cat > check_port.sh <<"EOF"
#!/bin/bash
CHK_PORT='8443'
if [ -n "$CHK_PORT" ];then
        PORT_PROCESS=$(netstat -ntlp | grep $CHK_PORT | wc -l)
        if [ $PORT_PROCESS -eq 0 ];then
          systemctl restart kube-nginx
          sleep 3
          PORT_PROCESS=$(netstat -ntlp | grep $CHK_PORT | wc -l)
             if [ "${PORT_PROCESS}" = "0" ]; then
               systemctl stop keepalived
             fi  
        fi
else
        echo "Check Port Cant Be Empty!"
fi
EOF

# chmod 755 check_port.sh
```

1.5.8、配置keepalived为systemctl管理
```
# cat > keepalived.service <<EOF
[Unit]
Description=LVS and VRRP High Availability Monitor
After=syslog.target network-online.target

[Service]
Type=forking
PIDFile=/var/run/keepalived.pid
KillMode=process
EnvironmentFile=-/etc/sysconfig/keepalived
ExecStart=/usr/sbin/keepalived \$KEEPALIVED_OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
```
1.5.9、 分发keepalived二进制文件和配置文件
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for (( i=0; i < 3; i++ ))
do
    sed -e "s/##NODE_IP##/${MASTER_IPS[i]}/" /opt/k8s/conf/keepalived.conf.template > \
           /opt/k8s/conf/keepalived.conf-${MASTER_IPS[i]}.template
done

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p /etc/keepalived"
    scp /opt/k8s/packages/keepalived-2.2.0/keepalived-prefix/sbin/keepalived ${host}:/usr/sbin/
    scp /opt/k8s/packages/keepalived-2.2.0/keepalived-prefix/etc/sysconfig/keepalived ${host}:/etc/sysconfig/
    scp /opt/k8s/conf/keepalived.conf-${host}.template ${host}:/etc/keepalived/keepalived.conf
    scp /opt/k8s/conf/check_port.sh ${host}:/etc/keepalived/
    scp /opt/k8s/conf/keepalived.service ${host}:/etc/systemd/system/
done

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable keepalived --now && \
                      systemctl restart keepalived  && \
                      systemctl status keepalived | grep Active"
done
```
1.5.9.0、 查看VIP所在的机器以及是否ping通
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "ip a | grep 192.168.0.19"
done

# ping 192.168.0.19 -c 1
```

1.6、部署kube-apiserver
```
所有master节点需要kube-apiserver
kube-apiserver是无状态服务，需要通过kube-nginx进行代理访问，从而保证服务可用性
部署kubectl的时候已经下载了完整的kubernetes二进制文件，因此kube-apiserver就无须下载了，等下脚本分发即可
```
1.6.0、创建kubernetes证书和私钥
```
# cd /opt/k8s/ssl/
# source /opt/k8s/bin/k8s-env.sh
# cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "192.168.0.13",
    "192.168.0.14",
    "192.168.0.15",
    "192.168.0.19",
    "${CLUSTER_KUBERNETES_SVC_IP}",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "bandian"
    }
  ]
}
EOF

需要将集群的所有IP添加到证书内
```
1.6.1、生成kubernetes证书和私钥
```
# cfssl gencert -ca=/opt/k8s/ssl/ca.pem \
-ca-key=/opt/k8s/ssl/ca-key.pem \
-config=/opt/k8s/ssl/ca-config.json \
-profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes
```

1.6.2、创建metrics-server证书和私钥
```
# cat > metrics-server-csr.json <<EOF
{
  "CN": "aggregator",
  "hosts": [
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "bandian"
    }
  ]
}
EOF
```

1.6.3、生成metrics-server证书和私钥
```
# cfssl gencert -ca=/opt/k8s/ssl/ca.pem \
-ca-key=/opt/k8s/ssl/ca-key.pem \
-config=/opt/k8s/ssl/ca-config.json \
-profile=kubernetes metrics-server-csr.json | cfssljson -bare metrics-server
```

1.6.4、配置kube-apiserver为systemctl管理
```
# cd /opt/k8s/conf/
# source /opt/k8s/bin/k8s-env.sh
# cat > kube-apiserver.service.template <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=${K8S_DIR}/kube-apiserver
ExecStart=/opt/k8s/bin/kube-apiserver \\
  --v=2 \\
  --advertise-address=##NODE_IP## \\
  --secure-port=6443 \\
  --bind-address=##NODE_IP## \\
  --etcd-servers=${ETCD_ENDPOINTS} \\
  --allow-privileged=true \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction \\
  --authorization-mode=RBAC,Node \\
  --enable-bootstrap-token-auth=true \\
  --token-auth-file=/opt/k8s/ssl/token.csv \\
  --service-node-port-range=${NODE_PORT_RANGE} \\
  --kubelet-client-certificate=/opt/k8s/ssl/kubernetes.pem \\
  --kubelet-client-key=/opt/k8s/ssl/kubernetes-key.pem \\
  --tls-cert-file=/opt/k8s/ssl/kubernetes.pem \\
  --tls-private-key-file=/opt/k8s/ssl/kubernetes-key.pem \\
  --client-ca-file=/opt/k8s/ssl/ca.pem \\
  --service-account-key-file=/opt/k8s/ssl/ca.pem \\
  --etcd-cafile=/opt/k8s/ssl/ca.pem \\
  --etcd-certfile=/opt/k8s/ssl/kubernetes.pem \\
  --etcd-keyfile=/opt/k8s/ssl/kubernetes-key.pem \\
  --audit-log-maxage=15 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-truncate-enabled \\
  --audit-log-path=${K8S_DIR}/kube-apiserver/audit.log \\
  --proxy-client-cert-file=/opt/k8s/ssl/metrics-server.pem \\
  --proxy-client-key-file=/opt/k8s/ssl/metrics-server-key.pem \\
  --requestheader-client-ca-file=/opt/k8s/ssl/ca.pem \\
  --requestheader-allowed-names=aggregator \\
  --requestheader-extra-headers-prefix="X-Remote-Extra-" \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User

Restart=on-failure
RestartSec=10
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

--v 日志等级
--etcd-servers etcd集群地址
--bind-address 监听地址
--secure-port https安全端口
--advertise-address 集群通告地址
--allow-privileged 启用授权
--service-cluster-ip-range Service虚拟IP地址段
--enable-admission-plugins 准入控制模块
--authorization-mode 认证授权，启用RBAC授权和节点自管理
--enable-bootstrap-token-auth 启用TLS bootstrap机制
--token-auth-file bootstrap token文件
--service-node-port-range Service nodeport类型默认分配端口范围
--kubelet-client-xxx apiserver访问kubelet客户端证书
--tls-xxx-file apiserver https证书
--etcd-xxxfile 连接Etcd集群证书 --audit-log-xxx:审计日志
--requestheader-xxx-xxx 开启kube-apiserver的aggregation（hpa和metrics依赖aggregation）
--proxy-client-xxx 同上
```
1.6.5、配置bootstrap token文件
```
# cd /opt/k8s/ssl/
# cat > token.csv <<EOF
404a083c42f5d39979fd731a24774b83,kubelet-bootstrap,10001,"system:node-bootstrapper"
EOF

bootstrap token文件格式
token，用户名，UID，用户组
token生成方式
#  head -c 16 /dev/urandom | od -An -t x | tr -d ' '
```

1.6.6、分发kube-apiserver命令和秘钥等文件到其他节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# 替换模板文件
# for (( i=0; i < 3; i++ ))
do
    sed -e "s/##NODE_IP##/${MASTER_IPS[i]}/" /opt/k8s/conf/kube-apiserver.service.template > \
           /opt/k8s/conf/kube-apiserver-${MASTER_IPS[i]}.service
done

# 分发到master节点
# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
        scp /opt/k8s/packages/kubernetes/server/bin/{apiextensions-apiserver,kube-apiserver,kube-controller-manager,kube-proxy,kube-scheduler,kubeadm,kubelet,mounter} ${host}:/opt/k8s/bin/
        scp /opt/k8s/ssl/{kubernetes*.pem,token.csv} ${host}:/opt/k8s/ssl/
        scp /opt/k8s/ssl/metrics-server*.pem ${host}:/opt/k8s/ssl/
        scp /opt/k8s/conf/kube-apiserver-${host}.service ${host}:/etc/systemd/system/kube-apiserver.service
done

# 分发到所有节点
# for host_node in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host_node}\e[0m\n"
        scp /opt/k8s/packages/kubernetes/server/bin/{kubelet,kube-proxy} ${host_node}:/opt/k8s/bin/
done
```

1.6.7、启动kube-apiserver服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p ${K8S_DIR}/kube-apiserver/"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable kube-apiserver --now && \
                      systemctl status kube-apiserver | grep Active"
done

注：返回的如果是Active: activating (auto-restart)，可以稍等一下，然后再次执行systemctl status kube-apiserver | grep Active，出现running就可以了，否则的话，需要查看日志journalctl -xeu kube-apiserver
```
1.6.8、查看kube-apiserver写入etcd的数据
```
# source /opt/k8s/bin/k8s-env.sh
# etcdctl \
--endpoints=${ETCD_ENDPOINTS} \
--cacert=/opt/k8s/ssl/ca.pem \
--cert=/opt/k8s/ssl/etcd.pem \
--key=/opt/k8s/ssl/etcd-key.pem \
get /registry/ --prefix --keys-only
```
1.6.9、检查kubernetes集群信息
```
# kubectl cluster-info
Kubernetes master is running at https://192.168.0.19:8443

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

# kubectl get all --all-namespaces
NAMESPACE   NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
default     service/kubernetes   ClusterIP   10.254.0.1   <none>        443/TCP   38s

# kubectl get cs
Warning: v1 ComponentStatus is deprecated in v1.19+
NAME                 STATUS      MESSAGE                                                                                       ERROR
scheduler            Unhealthy   Get "http://127.0.0.1:10251/healthz": dial tcp 127.0.0.1:10251: connect: connection refused
controller-manager   Unhealthy   Get "http://127.0.0.1:10252/healthz": dial tcp 127.0.0.1:10252: connect: connection refused
etcd-1               Healthy     {"health":"true"}                                                                       
etcd-2               Healthy     {"health":"true"}                                                                       
etcd-0               Healthy     {"health":"true"}

注：如果有报错，检查一下~/.kube/config 的配置，以及证书是否正确
```

1.6.10、授权kubelet-bootstrap用户允许请求证书
```
# kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes
```

1.7、部署kube-controller-manager
```
所有master节点需要kube-controller-manager
```
1.7.0、创建kube-controller-manager请求证书
```
# cd /opt/k8s/ssl/
# cat > kube-controller-manager-csr.json <<EOF
{
    "CN": "system:kube-controller-manager",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "hosts": [
    "127.0.0.1",
    "192.168.0.13",
    "192.168.0.14",
    "192.168.0.15",
    "192.168.0.19"
    ],
    "names": [
      {
        "C": "CN",
        "ST": "ShangHai",
        "L": "ShangHai",
        "O": "system:kube-controller-manager",
        "OU": "bandian"
      }
    ]
}
EOF
```

1.7.1、生成kube-controller-manager证书和私钥
```
# cfssl gencert -ca=/opt/k8s/ssl/ca.pem \
-ca-key=/opt/k8s/ssl/ca-key.pem \
-config=/opt/k8s/ssl/ca-config.json \
-profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
```

1.7.2、创建kube-controller-manager的kubeconfig文件
```
# cd /opt/k8s/ssl/
# source /opt/k8s/bin/k8s-env.sh

# "设置集群参数"
kubectl config set-cluster kubernetes \
--certificate-authority=/opt/k8s/ssl/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=kube-controller-manager.kubeconfig

# "设置客户端认证参数"
kubectl config set-credentials system:kube-controller-manager \
--client-certificate=kube-controller-manager.pem \
--client-key=kube-controller-manager-key.pem \
--embed-certs=true \
--kubeconfig=kube-controller-manager.kubeconfig

# "设置上下文参数"
kubectl config set-context system:kube-controller-manager \
--cluster=kubernetes \
--user=system:kube-controller-manager \
--kubeconfig=kube-controller-manager.kubeconfig

# "设置默认上下文"
kubectl config use-context system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig
```

1.7.3、配置kube-controller-manager为systemctl启动
```
# cd /opt/k8s/conf/
# source /opt/k8s/bin/k8s-env.sh
# cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=${K8S_DIR}/kube-controller-manager
ExecStart=/opt/k8s/bin/kube-controller-manager \\
  --v=2 \\
  --cluster-name=kubernetes \\
  --profiling \\
  --logtostderr=true \\
  --leader-elect=true \\
  --bind-address=0.0.0.0 \\
  --allocate-node-cidrs=true \\
  --cluster-cidr=${CLUSTER_CIDR} \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --cluster-signing-cert-file=/opt/k8s/ssl/ca.pem \\
  --cluster-signing-key-file=/opt/k8s/ssl/ca-key.pem \\
  --root-ca-file=/opt/k8s/ssl/ca.pem \\
  --service-account-private-key-file=/opt/k8s/ssl/ca-key.pem \\
  --experimental-cluster-signing-duration=87600h0m0s \\
  --kubeconfig=/opt/k8s/ssl/kube-controller-manager.kubeconfig \\
  --requestheader-allowed-names \\
  --requestheader-client-ca-file=/opt/k8s/ssl/ca.pem \\
  --requestheader-extra-headers-prefix="X-Remote-Extra-" \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --authorization-kubeconfig=/opt/k8s/ssl/kube-controller-manager.kubeconfig \\
  --controllers=*,bootstrapsigner,tokencleaner \\
  --use-service-account-credentials=true
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

--controllers=*,bootstrapsigner,tokencleaner 启用的控制器列表，tokencleaner 用于自动清理过期的 Bootstrap token
--profiling 开启profilling，通过web接口host:port/debug/pprof/分析性能
--experimental-cluster-signing-duration 指定 TLS Bootstrap 证书的有效期
--root-ca-file 放置到容器 ServiceAccount 中的 CA 证书，用来对 kube-apiserver 的证书进行校验
--service-cluster-ip-range 指定 Service Cluster IP 网段，必须和 kube-apiserver 中的同名参数一致
--leader-elect=true 集群运行模式，启用选举功能被选为 leader 的节点负责处理工作，其它节点为阻塞状态
```

1.7.4、分发kube-controller-manager证书和文件到其他节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /opt/k8s/conf/kube-controller-manager.service \
        ${host}:/etc/systemd/system/kube-controller-manager.service
    scp /opt/k8s/ssl/{kube-controller-manager*.pem,kube-controller-manager.kubeconfig} \
        ${host}:/opt/k8s/ssl/
done
```

1.7.5、启动kube-controller-manager服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p ${K8S_DIR}/kube-controller-manager"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable kube-controller-manager --now && \
                      systemctl status kube-controller-manager | grep Active"
done
```
1.7.6、查看kube-controller-manager端口
```
# ss -nltp | grep kube-contro
LISTEN     0      128         :::10252                   :::*                   users:(("kube-controller",pid=65221,fd=7))
LISTEN     0      128         :::10257                   :::*                   users:(("kube-controller",pid=65221,fd=8))
```
1.7.7、查看当前的leader

```
# kubectl get endpoints kube-controller-manager --namespace=kube-system -o yaml
apiVersion: v1
kind: Endpoints
metadata:
  annotations:
    control-plane.alpha.kubernetes.io/leader: '{"holderIdentity":"k8s-01_d04c6ed1-5048-4fe2-aaee-ed3043b24e6b","leaseDurationSeconds":15,"acquireTime":"2021-02-12T16:52:57Z","renewTime":"2021-02-12T16:53:07Z","leaderTransitions":0}'
  creationTimestamp: "2021-02-12T16:52:57Z"
  managedFields:
  - apiVersion: v1
    fieldsType: FieldsV1
    fieldsV1:
      f:metadata:
        f:annotations:
          .: {}
          f:control-plane.alpha.kubernetes.io/leader: {}
    manager: kube-controller-manager
    operation: Update
    time: "2021-02-12T16:52:57Z"
  name: kube-controller-manager
  namespace: kube-system
  resourceVersion: "355"
  selfLink: /api/v1/namespaces/kube-system/endpoints/kube-controller-manager
  uid: fc7f643d-a71f-4a58-b66c-2edcacbda693
```

1.8、部署kube-scheduler
1.8.0、创建kube-scheduler请求证书
```
# cd /opt/k8s/ssl/
# cat > kube-scheduler-csr.json <<EOF
{
    "CN": "system:kube-scheduler",
    "hosts": [
    "127.0.0.1",
    "192.168.0.13",
    "192.168.0.14",
    "192.168.0.15",
    "192.168.0.19"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
      {
        "C": "CN",
        "ST": "ShangHai",
        "L": "ShangHai",
        "O": "system:kube-scheduler",
        "OU": "bandian"
      }
    ]
}
EOF
```

1.8.1、生成kube-scheduler证书和私钥
```
# cfssl gencert -ca=/opt/k8s/ssl/ca.pem \
-ca-key=/opt/k8s/ssl/ca-key.pem \
-config=/opt/k8s/ssl/ca-config.json \
-profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler
```

1.8.2、创建kube-scheduler的kubeconfig文件
```
# source /opt/k8s/bin/k8s-env.sh

# "设置集群参数"
kubectl config set-cluster kubernetes \
--certificate-authority=/opt/k8s/ssl/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=kube-scheduler.kubeconfig

# "设置客户端认证参数"
kubectl config set-credentials system:kube-scheduler \
--client-certificate=kube-scheduler.pem \
--client-key=kube-scheduler-key.pem \
--embed-certs=true \
--kubeconfig=kube-scheduler.kubeconfig

# "设置上下文参数"
kubectl config set-context system:kube-scheduler \
--cluster=kubernetes \
--user=system:kube-scheduler \
--kubeconfig=kube-scheduler.kubeconfig

# "设置默认上下文"
kubectl config use-context system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig
```

1.8.3、配置kube-scheduler为systemctl启动
```
# cd /opt/k8s/conf/
# source /opt/k8s/bin/k8s-env.sh
# cat > kube-scheduler.service.template <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
WorkingDirectory=${K8S_DIR}/kube-scheduler
ExecStart=/opt/k8s/bin/kube-scheduler \\
  --bind-address=0.0.0.0 \\
  --leader-elect=true \\
  --kubeconfig=/opt/k8s/ssl/kube-scheduler.kubeconfig \\
  --tls-cert-file=/opt/k8s/ssl/kube-scheduler.pem \\
  --tls-private-key-file=/opt/k8s/ssl/kube-scheduler-key.pem \\
  --authentication-kubeconfig=/opt/k8s/ssl/kube-scheduler.kubeconfig \\
  --client-ca-file=/opt/k8s/ssl/ca.pem \\
  --requestheader-allowed-names \\
  --requestheader-client-ca-file=/opt/k8s/ssl/ca.pem \\
  --requestheader-extra-headers-prefix="X-Remote-Extra-" \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --logtostderr=true \\
  --v=2
Restart=always
RestartSec=5
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOF
```

1.8.4、分发kube-scheduler证书和文件到其他节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /opt/k8s/conf/kube-scheduler.service.template ${host}:/etc/systemd/system/kube-scheduler.service
    scp /opt/k8s/ssl/{kube-scheduler*.pem,kube-scheduler.kubeconfig} ${host}:/opt/k8s/ssl
done
```

1.8.5、启动kube-scheduler服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${MASTER_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p ${K8S_DIR}/kube-scheduler"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable kube-scheduler --now && \
                      systemctl status kube-scheduler | grep Active"
done
```

1.8.6、查看kube-scheduler端口
```
# ss -nltp | grep kube-scheduler
LISTEN     0      128         :::10251                   :::*                   users:(("kube-scheduler",pid=67502,fd=8))
LISTEN     0      128         :::10259                   :::*                   users:(("kube-scheduler",pid=67502,fd=9))
```

1.8.7、查看当前leader
```
# kubectl get endpoints kube-scheduler --namespace=kube-system  -o yaml
apiVersion: v1
kind: Endpoints
metadata:
  annotations:
    control-plane.alpha.kubernetes.io/leader: '{"holderIdentity":"k8s-01_556718e1-338e-4e87-b2c8-c1ea2ccfa1c1","leaseDurationSeconds":15,"acquireTime":"2021-02-12T16:54:38Z","renewTime":"2021-02-12T16:54:49Z","leaderTransitions":0}'
  creationTimestamp: "2021-02-12T16:54:39Z"
  managedFields:
  - apiVersion: v1
    fieldsType: FieldsV1
    fieldsV1:
      f:metadata:
        f:annotations:
          .: {}
          f:control-plane.alpha.kubernetes.io/leader: {}
    manager: kube-scheduler
    operation: Update
    time: "2021-02-12T16:54:39Z"
  name: kube-scheduler
  namespace: kube-system
  resourceVersion: "557"
  selfLink: /api/v1/namespaces/kube-system/endpoints/kube-scheduler
  uid: 1e33fe40-0d13-4407-a7bb-f7a37f4a72a8

到此，kubernetes master节点已经部署完成，后面开始kubernetes node节点的部署
docker和flannel之前已经全节点部署了，因此，node节点只需要部署kubelet、kube-proxy、coredns以及dashboard
```

1.9、部署kubelet
```
kubelet运行在每个node节点上，接收kube-apiserver发送的请求，管理Pod容器，执行交互命令

kubelet启动时自动向kube-apiserver注册节点信息，内置的cAdivsor统计和监控节点的资源使用资源情况

为确保安全，部署时关闭了kubelet的非安全http端口，对请求进行认证和授权，拒绝未授权的访问
```

1.9.0、创建kubelet bootstrap kubeconfig文件
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for node_name in ${NODE_NAMES[@]}
do
    printf "\e[1;34m${node_name}\e[0m\n"
    # 创建 token
    export BOOTSTRAP_TOKEN=$(kubeadm token create \
    --description kubelet-bootstrap-token \
    --groups system:bootstrappers:${node_name} \
    --kubeconfig ~/.kube/config)

    # 设置集群参数
    kubectl config set-cluster kubernetes \
    --certificate-authority=/opt/k8s/ssl/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=/opt/k8s/ssl/kubelet-bootstrap-${node_name}.kubeconfig

    # 设置客户端认证参数
    kubectl config set-credentials kubelet-bootstrap \
    --token=${BOOTSTRAP_TOKEN} \
    --kubeconfig=/opt/k8s/ssl/kubelet-bootstrap-${node_name}.kubeconfig

    # 设置上下文参数
    kubectl config set-context default \
    --cluster=kubernetes \
    --user=kubelet-bootstrap \
    --kubeconfig=/opt/k8s/ssl/kubelet-bootstrap-${node_name}.kubeconfig

    # 设置默认上下文
    kubectl config use-context default --kubeconfig=/opt/k8s/ssl/kubelet-bootstrap-${node_name}.kubeconfig
done

向kubeconfig写入的是token，bootstrap结束后kube-controller-manager为kubelet创建client和server证书

"查看kubeadm为各个节点创建的token"
# kubeadm token list --kubeconfig ~/.kube/config
TOKEN                     TTL         EXPIRES                     USAGES                   DESCRIPTION                                                EXTRA GROUPS
5750z9.ycsk3jxiahgz1gkn   23h         2021-02-14T00:55:41+08:00   authentication,signing   kubelet-bootstrap-token                                    system:bootstrappers:k8s-05
f4scbn.lev5uqmokwai5k0e   23h         2021-02-14T00:55:40+08:00   authentication,signing   kubelet-bootstrap-token                                    system:bootstrappers:k8s-02
kjfsng.qmjesofryg97c80q   23h         2021-02-14T00:55:41+08:00   authentication,signing   kubelet-bootstrap-token                                    system:bootstrappers:k8s-04
nseipt.09jaep1j8qnoqn1a   23h         2021-02-14T00:55:40+08:00   authentication,signing   kubelet-bootstrap-token                                    system:bootstrappers:k8s-01
zlal1h.856gawjgom560fys   23h         2021-02-14T00:55:40+08:00   authentication,signing   kubelet-bootstrap-token                                    system:bootstrappers:k8s-03

token有效期为1天，超期后将不能被用来bootstrap kubelet，且会被kube-controller-manager的token cleaner清理
kube-apiserver接收kubelet的bootstrap token后，将请求的user设置为system:bootstrap; group设置为system:bootstrappers，后续将为这个group设置ClusterRoleBinding
```

1.9.1、创建kubelet配置文件
```
# cd /opt/k8s/conf/
# source /opt/k8s/bin/k8s-env.sh
# cat > kubelet-config.yaml.template <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: "##NODE_IP##"
staticPodPath: ""
syncFrequency: 1m
fileCheckFrequency: 20s
httpCheckFrequency: 20s
staticPodURL: ""
port: 10250
readOnlyPort: 0
rotateCertificates: true
serverTLSBootstrap: true
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/opt/k8s/ssl/ca.pem"
authorization:
  mode: Webhook
registryPullQPS: 0
registryBurst: 20
eventRecordQPS: 0
eventBurst: 20
enableDebuggingHandlers: true
enableContentionProfiling: true
healthzPort: 10248
healthzBindAddress: "##NODE_IP##"
clusterDomain: "${CLUSTER_DNS_DOMAIN}"
clusterDNS:
  - "${CLUSTER_DNS_SVC_IP}"
nodeStatusUpdateFrequency: 10s
nodeStatusReportFrequency: 1m
imageMinimumGCAge: 2m
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80
volumeStatsAggPeriod: 1m
kubeletCgroups: ""
systemCgroups: ""
cgroupRoot: ""
cgroupsPerQOS: true
cgroupDriver: systemd
runtimeRequestTimeout: 10m
hairpinMode: promiscuous-bridge
maxPods: 220
podCIDR: "${CLUSTER_CIDR}"
podPidsLimit: -1
resolvConf: /etc/resolv.conf
maxOpenFiles: 1000000
kubeAPIQPS: 1000
kubeAPIBurst: 2000
serializeImagePulls: false
evictionHard:
  memory.available:  "100Mi"
nodefs.available:  "10%"
nodefs.inodesFree: "5%"
imagefs.available: "15%"
evictionSoft: {}
enableControllerAttachDetach: true
failSwapOn: true
containerLogMaxSize: 20Mi
containerLogMaxFiles: 10
systemReserved: {}
kubeReserved: {}
systemReservedCgroup: ""
kubeReservedCgroup: ""
enforceNodeAllocatable: ["pods"]
EOF
```

1.9.2、配置kubelet为systemctl启动
```
# cd /opt/k8s/conf/
# source /opt/k8s/bin/k8s-env.sh
# cat > kubelet.service.template <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=${K8S_DIR}/kubelet
ExecStart=/opt/k8s/bin/kubelet \\
  --v=2 \\
  --hostname-override=##NODE_IP## \\
  --bootstrap-kubeconfig=/opt/k8s/ssl/kubelet-bootstrap.kubeconfig \\
  --cert-dir=/opt/k8s/ssl \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --config=/etc/kubernetes/kubelet-config.yaml \\
  --logtostderr=true \\
  --pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.2 \\
  --image-pull-progress-deadline=15m \\
  --cni-conf-dir=/etc/cni/net.d \\
  --root-dir=${K8S_DIR}/kubelet

Restart=always
RestartSec=5
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOF

–bootstrap-kubeconfig：指向 bootstrap kubeconfig 文件，kubelet 使用该文件中的用户名和 token 向 kube-apiserver 发送 TLS Bootstrapping 请求
K8S approve kubelet 的 csr 请求后，在 --cert-dir 目录创建证书和私钥文件，然后写入 --kubeconfig 文件
kubelet设置了 --hostname-override 选项，kube-proxy 也需要设置该选项，否则会出现 找不到 Node 的情况；
```
1.9.3、拉取kubelet依赖的pause镜像
```
# docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.2
# cd /opt/k8s/packages/
# docker save $(docker images | grep -v REPOSITORY | awk 'BEGIN{OFS=":";ORS=" "}{print $1,$2}') -o pause.tar
"将镜像保存到本地，分发到其他节点"
```

1.9.4、分发kubelet证书和文件到其他节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for (( i=0; i < 5; i++ ))
do
    sed -e "s/##NODE_IP##/${NODE_IPS[i]}/" /opt/k8s/conf/kubelet.service.template > \
           /opt/k8s/conf/kubelet-${NODE_IPS[i]}.service
    sed -e "s/##NODE_IP##/${NODE_IPS[i]}/" /opt/k8s/conf/kubelet-config.yaml.template > \
           /opt/k8s/conf/kubelet-config-${NODE_IPS[i]}.yaml.template
done

# for node_name in ${NODE_NAMES[@]}
do
    printf "\e[1;34m${node_name}\e[0m\n"
    scp /opt/k8s/ssl/kubelet-bootstrap-${node_name}.kubeconfig \
        ${node_name}:/opt/k8s/ssl/kubelet-bootstrap.kubeconfig
done

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /opt/k8s/conf/kubelet-${host}.service ${host}:/etc/systemd/system/kubelet.service
    scp /opt/k8s/conf/kubelet-config-${host}.yaml.template ${host}:/etc/kubernetes/kubelet-config.yaml
    scp /opt/k8s/packages/pause.tar ${host}:/opt/k8s/
    ssh root@${host} "docker load -i /opt/k8s/pause.tar"
done
```

1.9.5、授权kubelet-bootstrap用户组允许请求证书
```
# kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --group=system:bootstrappers
1
不创建的话，kubelet会启动失败
```
1.9.6、启动kubelet服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p ${K8S_DIR}/kubelet/kubelet-plugins/volume/exec/"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable kubelet --now && \
                      systemctl status kubelet | grep Active"
done

kubelet 启动后使用 --bootstrap-kubeconfig 向 kube-apiserver 发送 CSR 请求，当这个CSR 被 approve 后，kube-controller-manager 为 kubelet 创建 TLS 客户端证书、私钥和 --kubeletconfig 文件
注意：kube-controller-manager 需要配置 --cluster-signing-cert-file 和 --cluster-signing-key-file 参数，才会为TLS Bootstrap 创建证书和私钥
```

1.9.7、自动approve CSR请求
创建三个ClusterRoleBinding，分别用于自动approve client、renew client、renew server证书
```
# cd /opt/k8s/conf/
# cat > csr-crb.yaml <<EOF
# Approve all CSRs for the group "system:bootstrappers"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
   name: auto-approve-csrs-for-group
subjects:
- kind: Group
   name: system:bootstrappers
   apiGroup: rbac.authorization.k8s.io
roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
   apiGroup: rbac.authorization.k8s.io
---
# To let a node of the group "system:nodes" renew its own credentials
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
   name: node-client-cert-renewal
subjects:
- kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
roleRef:
   kind: ClusterRole
   name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
   apiGroup: rbac.authorization.k8s.io
---
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-server-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
---
# To let a node of the group "system:nodes" renew its own server credentials
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
   name: node-server-cert-renewal
subjects:
- kind: Group
   name: system:nodes
   apiGroup: rbac.authorization.k8s.io
roleRef:
   kind: ClusterRole
   name: approve-node-server-renewal-csr
   apiGroup: rbac.authorization.k8s.io
EOF

# kubectl apply -f csr-crb.yaml

auto-approve-csrs-for-group 自动approve node的第一次CSR，注意第一次CSR时，请求的Group为system:bootstrappers
node-client-cert-renewal 自动approve node后续过期的client证书，自动生成的证书Group为system:nodes
node-server-cert-renewal 自动approve node后续过期的server证书，自动生成的证书Group
```
1.9.8、查看节点是否都为ready(两分钟)
```
# kubectl get node
NAME            STATUS   ROLES    AGE   VERSION
192.168.0.13   Ready    <none>   29m   v1.19.7
192.168.0.14   Ready    <none>   29m   v1.19.7
192.168.0.15   Ready    <none>   29m   v1.19.7
192.168.0.16   Ready    <none>   26m   v1.19.7
192.168.0.18   Ready    <none>   29m   v1.19.7

```
1.9.9、手动approve server cert csr
基于安全考虑，CSR approving controllers不会自动approve kubelet server证书签名请求，需要手动approve
```
# kubectl get csr | grep Pending | awk '{print $1}' | xargs kubectl certificate approve
```

1.9.10、bear token认证和授权
创建一个ServiceAccount，将它和ClusterRole system:kubelet-api-admin绑定，从而具有调用kubelet API的权限
```
# kubectl create sa kubelet-api-test
# kubectl create clusterrolebinding kubelet-api-test --clusterrole=system:kubelet-api-admin --serviceaccount=default:kubelet-api-test
```

1.10、部署kube-proxy
```
kube-proxy运行在所有node节点上，它监听apiserver中service和endpoint的变化情况，创建路由规则提供服务IP和负载均衡功能

这里使用ipvs模式的kube-proxy进行部署，在各个节点需要安装ipset命令，加载ip_vs内核模块

# zypper in ipset
# modprobe ip_vs_rr
```

1.10.0、创建kube-proxy证书
```
# cd /opt/k8s/ssl/
# cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShangHai",
      "L": "ShangHai",
      "O": "k8s",
      "OU": "bandian"
    }
  ]
}
EOF
```

1.10.1、生成kube-proxy证书和秘钥
```
# cfssl gencert -ca=/opt/k8s/ssl/ca.pem \
-ca-key=/opt/k8s/ssl/ca-key.pem \
-config=/opt/k8s/ssl/ca-config.json \
-profile=kubernetes  kube-proxy-csr.json | cfssljson -bare kube-proxy
```

1.10.2、创建kube-proxy的kubeconfig文件
```
# source /opt/k8s/bin/k8s-env.sh

# "设置集群参数"
kubectl config set-cluster kubernetes \
--certificate-authority=/opt/k8s/ssl/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=kube-proxy.kubeconfig

# "设置客户端认证参数"
kubectl config set-credentials kube-proxy \
--client-certificate=kube-proxy.pem \
--client-key=kube-proxy-key.pem \
--embed-certs=true \
--kubeconfig=kube-proxy.kubeconfig

# "设置上下文参数"
kubectl config set-context default \
--cluster=kubernetes \
--user=kube-proxy \
--kubeconfig=kube-proxy.kubeconfig

# "设置默认上下文"
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
```

1.10.3、创建kube-proxy配置文件
```
# cd /opt/k8s/conf/
# source /opt/k8s/bin/k8s-env.sh
# cat > kube-proxy-config.yaml.template <<EOF
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
clientConnection:
  burst: 200
  kubeconfig: "/opt/k8s/ssl/kube-proxy.kubeconfig"
  qps: 100
bindAddress: ##NODE_IP##
healthzBindAddress: ##NODE_IP##:10256
metricsBindAddress: ##NODE_IP##:10249
enableProfiling: true
clusterCIDR: ${CLUSTER_CIDR}
mode: "ipvs"
portRange: ""
EOF

clientConnection.kubeconfig 连接 apiserver 的 kubeconfig 文件
clusterCIDR kube-proxy 根据 --cluster-cidr判断集群内部和外部流量，指定 --cluster-cidr 或 --masquerade-all 选项后 kube-proxy 才会对访问 Service IP 的请求做 SNAT
```

1.10.4、配置kube-proxy为systemctl启动
```
# cd /opt/k8s/conf/
# source /opt/k8s/bin/k8s-env.sh
# cat > kube-proxy.service.template <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
[Service]
WorkingDirectory=${K8S_DIR}/kube-proxy
ExecStart=/opt/k8s/bin/kube-proxy \\
  --hostname-override=##NODE_IP## \\
  --config=/etc/kubernetes/kube-proxy-config.yaml \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
```

1.10.5、分发kube-proxy证书和文件到其他节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for (( i=0; i < 5; i++ ))
do
    sed -e "s/##NODE_IP##/${NODE_IPS[i]}/" /opt/k8s/conf/kube-proxy.service.template > \
           /opt/k8s/conf/kube-proxy-${NODE_IPS[i]}.service
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" \
    /opt/k8s/conf/kube-proxy-config.yaml.template > /opt/k8s/conf/kube-proxy-config-${NODE_IPS[i]}.yaml.template
done

#  for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /opt/k8s/ssl/kube-proxy.kubeconfig ${host}:/opt/k8s/ssl
    scp /opt/k8s/conf/kube-proxy-${host}.service ${host}:/etc/systemd/system/kube-proxy.service
    scp /opt/k8s/conf/kube-proxy-config-${host}.yaml.template \
        ${host}:/etc/kubernetes/kube-proxy-config.yaml
    scp /opt/k8s/packages/conntrack ${host}:/opt/k8s/bin/
    ssh root@${host} "chmod +x /opt/k8s/bin/*"
done

kube-proxy 需要 conntrack
suse 编译比较麻烦
可以找一个 centos 执行 yum -y install conntrack
从 /usr/sbin 目录下获取 conntrack 二进制文件，复制到 suse 内使用
也可以百度网盘链接：https://pan.baidu.com/s/1x3fgMQeT6c8oSzRA6R8R6Q
提取码：abcd
```

1.10.6、启动kube-proxy服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p ${K8S_DIR}/kube-proxy"
        ssh root@${host} "modprobe ip_vs_rr"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable kube-proxy --now && \
                      systemctl status kube-proxy | grep Active"
done
```

1.10.7、查看kube-proxy端口
```
# ss -nltp | grep kube-proxy
LISTEN     0      128    192.168.72.25:10249                    *:*                   users:(("kube-proxy",pid=103283,fd=12))
LISTEN     0      128    192.168.72.25:10256                    *:*                   users:(("kube-proxy",pid=103283,fd=13))
```

1.11.0、部署coredns
```
# source /opt/k8s/bin/k8s-env.sh
# cat > /etc/kubernetes/coredns.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
  labels:
      kubernetes.io/cluster-service: "true"
      addonmanager.kubernetes.io/mode: Reconcile
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
    addonmanager.kubernetes.io/mode: Reconcile
  name: system:coredns
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  - pods
  - namespaces
  verbs:
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
    addonmanager.kubernetes.io/mode: EnsureExists
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
  labels:
      addonmanager.kubernetes.io/mode: EnsureExists
data:
  Corefile: |
    .:53 {
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/name: "CoreDNS"
spec:
  replicas: 2
  # replicas: not specified here:
  # 1. In order to make Addon Manager do not reconcile this replicas parameter.
  # 2. Default is 1.
  # 3. Will be tuned in real time if DNS horizontal auto-scaling is turned on.
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
      annotations:
        seccomp.security.alpha.kubernetes.io/pod: 'docker/default'
    spec:
      priorityClassName: system-cluster-critical
      serviceAccountName: coredns
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      nodeSelector:
        beta.kubernetes.io/os: linux
      containers:
      - name: coredns
        image: coredns/coredns:1.7.0
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: host-time
          mountPath: /etc/localtime
          readOnly: true
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
      dnsPolicy: Default
      volumes:
        - name: host-time
          hostPath:
            path: /etc/localtime
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
---
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  annotations:
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/name: "CoreDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.254.0.2
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
  - name: metrics
    port: 9153
    protocol: TCP
EOF


# kubectl apply -f /etc/kubernetes/coredns.yaml
```

1.11.1、测试coredns功能
```
# cat<<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: busybox
  namespace: default
spec:
  containers:
  - name: busybox
    image: busybox:1.28.3
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
EOF

注：busybox高版本有nslookup Bug，不建议使用高版本，请按照我的版本进行操作即可！

# kubectl exec busybox -- nslookup kubernetes
Server:    10.254.0.2
Address 1: 10.254.0.2 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes
Address 1: 10.254.0.1 kubernetes.default.svc.cluster.local

```
1.12.0、部署metrics-server(HPA需要)
```
# git clone https://github.com/kodekloudhub/kubernetes-metrics-server.git
# vim kubernetes-metrics-server/metrics-server-deployment.yaml
      - name: metrics-server      
         image: registry.cn-hangzhou.aliyuncs.com/google_containers/metrics-server-amd64:v0.3.1
默认文件中是空目录
# kubectl create -f kubernetes-metrics-server/
# kubectl  top node
NAME           CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%  
192.168.0.13   84m          1%     4714Mi          30%      
192.168.0.14   62m          0%     2546Mi          16%      
192.168.0.15   64m          0%     2544Mi          16%    
```

# (篇外)增加node节点(全量替换文件，慎重操作)
1、准备node节点环境
1.0、修改配置脚本参数
```
后面的操作，只需要在k8s-01节点上操作即可
# cd /opt/k8s/bin/
# vim k8s-env.sh        
# 修改NODE_IPS为需要增加的node节点ip
export NODE_IPS=( 192.168.0.21 )

# 修改NODE_NAMES为需要增加的node节点主机名
export NODE_NAMES=( k8s-06 )
```
1.1、配置免密
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    expect -c "
    spawn ssh-copy-id -i /root/.ssh/id_rsa.pub root@${host}
        expect {
                \"*yes/no*\" {send \"yes\r\"; exp_continue}
                \"*Password*\" {send \"123456\r\"; exp_continue}
                \"*Password*\" {send \"123456\r\";}
               }"
done
```

1.2、添加hosts解析
```
# cat >> /etc/hosts <<EOF
192.168.0.21 k8s-06
EOF

分发到其他节点
#!/usr/bin/env bash

# for host in k8s-02 k8s-03 k8s-04 k8s-05 k8s-06
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /etc/hosts ${host}:/etc/hosts
done
```
1.3、修改主机名
```
#!/usr/bin/env bash

# for host in 6
do
    printf "\e[1;34mk8s-0${host}\e[0m\n"
    ssh root@k8s-0${host} "hostnamectl set-hostname --static k8s-0${host}"
done
```
1.4、更新PATH变量
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in 6
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@k8s-0${host} "echo 'PATH=$PATH:/opt/k8s/bin' >> /etc/profile"
done
```
1.5、安装依赖包
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "zypper in -y ntp ipset iptables curl sysstat wget lrzsz"
done
```
1.6、关闭防火墙以及swap分区
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "systemctl disable SuSEfirewall2.service --now"
    ssh root@${host} "iptables -F && iptables -X && iptables -F -t nat && iptables -X -t nat"
    ssh root@${host} "iptables -P FORWARD ACCEPT"
    ssh root@${host} "swapoff -a"
    ssh root@${host} "sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab"
done
```
1.7、开启内核模块
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "modprobe ip_vs_rr"
    ssh root@${host} "modprobe br_netfilter"
    ssh root@${host} "echo 'modprobe ip_vs_rr' >> /etc/rc.local"
    ssh root@${host} "echo 'modprobe br_netfilter' >> /etc/rc.local"
    ssh root@${host} "chmod +x /etc/rc.local"
done
```
1.8、内核优化
```
k8s-01节点上已经独立配置过k8s的内核优化文件，因此，直接scp过去，使配置生效即可
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /etc/sysctl.d/kubernetes.conf ${host}:/etc/sysctl.d/kubernetes.conf
    ssh root@${host} "sysctl -p /etc/sysctl.d/kubernetes.conf"
done
```
1.9、创建部署所需目录
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p /opt/k8s/bin /etc/kubernetes/cert"
done
```

2、部署flannel网络
flannel需要配置的， 在一开始都已经就绪了，只需要分发文件，启动新节点的flannel服务即可
2.0、分发证书文件到新的节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p /etc/flanneld/cert"
    scp /opt/k8s/ssl/ca.pem ${host}:/etc/kubernetes/cert/
    scp /opt/k8s/ssl/flanneld*.pem ${host}:/etc/flanneld/cert/
    scp /opt/k8s/packages/flannel/{flanneld,mk-docker-opts.sh} ${host}:/opt/k8s/bin/
    scp /opt/k8s/conf/flanneld.service ${host}:/etc/systemd/system/
done
```
2.1、启动flanneld服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable flanneld --now && \
                      systemctl status flanneld | grep Active"
done
```

2.2、查看新增node节点是否存在flannel网卡
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "ip a | grep flannel | grep -w inet"
done
```
3、部署docker
```
同上，只需要分发文件，启动docker即可
3.0、分发文件到新的节点
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir /etc/docker"
    scp /opt/k8s/packages/docker/* ${host}:/usr/bin/
    scp /opt/k8s/conf/daemon.json ${host}:/etc/docker/
    scp /opt/k8s/conf/docker.service ${host}:/etc/systemd/system/
done
```
3.1、启动docker服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable docker --now && \
                      systemctl status docker | grep Active"
done
```
3.2、查看新节点的docker和flannel网卡是否为同一网段
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} 'ifconfig | egrep "docker*|flannel*" -A 1'
done
```
4、部署kubelet组件
4.0、创建kubelet bootstrap kubeconfig文件
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for node_name in ${NODE_NAMES[@]}
do
    printf "\e[1;34m${node_name}\e[0m\n"
    # 创建 token
    export BOOTSTRAP_TOKEN=$(kubeadm token create \
    --description kubelet-bootstrap-token \
    --groups system:bootstrappers:${node_name} \
    --kubeconfig ~/.kube/config)

    # 设置集群参数
    kubectl config set-cluster kubernetes \
    --certificate-authority=/opt/k8s/ssl/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=/opt/k8s/ssl/kubelet-bootstrap-${node_name}.kubeconfig

    # 设置客户端认证参数
    kubectl config set-credentials kubelet-bootstrap \
    --token=${BOOTSTRAP_TOKEN} \
    --kubeconfig=/opt/k8s/ssl/kubelet-bootstrap-${node_name}.kubeconfig

    # 设置上下文参数
    kubectl config set-context default \
    --cluster=kubernetes \
    --user=kubelet-bootstrap \
    --kubeconfig=/opt/k8s/ssl/kubelet-bootstrap-${node_name}.kubeconfig

    # 设置默认上下文
    kubectl config use-context default --kubeconfig=/opt/k8s/ssl/kubelet-bootstrap-${node_name}.kubeconfig
done

"查看kubeadm为新节点创建的token"
# kubeadm token list --kubeconfig ~/.kube/config
TOKEN                     TTL         EXPIRES                     USAGES                   DESCRIPTION                                                EXTRA GROUPS
6sp12t.btr31aj1hc403tar   23h         2021-02-16T01:34:59+08:00   authentication,signing   kubelet-bootstrap-token                                    system:bootstrappers:k8s-06
bajiy9.b4fhfy8serfmyve0   23h         2021-02-16T01:35:00+08:00   authentication,signing   kubelet-bootstrap-token                                    system:bootstrappers:k8s-07
```
4.1、分发文件到新的节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for (( i=0; i < 6; i++ ))
do
    sed -e "s/##NODE_IP##/${NODE_IPS[i]}/" /opt/k8s/conf/kubelet.service.template > \
           /opt/k8s/conf/kubelet-${NODE_IPS[i]}.service
    sed -e "s/##NODE_IP##/${NODE_IPS[i]}/" /opt/k8s/conf/kubelet-config.yaml.template > \
           /opt/k8s/conf/kubelet-config-${NODE_IPS[i]}.yaml.template
done

# for node_name in ${NODE_NAMES[@]}
do
    printf "\e[1;34m${node_name}\e[0m\n"
    scp /opt/k8s/ssl/kubelet-bootstrap-${node_name}.kubeconfig \
        ${node_name}:/opt/k8s/ssl/kubelet-bootstrap.kubeconfig
done

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /opt/k8s/bin/kubelet ${host}:/opt/k8s/bin/kubelet
    scp /opt/k8s/conf/kubelet-${host}.service ${host}:/etc/systemd/system/kubelet.service
    scp /opt/k8s/conf/kubelet-config-${host}.yaml.template ${host}:/etc/kubernetes/kubelet-config.yaml
    scp /opt/k8s/packages/pause.tar ${host}:/opt/k8s/
    ssh root@${host} "docker load -i /opt/k8s/pause.tar"
done
```
4.2、启动kubelet服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p ${K8S_DIR}/kubelet/kubelet-plugins/volume/exec/"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable kubelet --now && \
                      systemctl status kubelet | grep Active"
done
```
4.3、查看新增节点是否ready了
```
# kubectl get node
NAME           STATUS   ROLES    AGE     VERSION
192.168.0.13   Ready    <none>   98m     v1.19.7
192.168.0.14   Ready    <none>   98m     v1.19.7
192.168.0.15   Ready    <none>   98m     v1.19.7
192.168.0.16   Ready    <none>   98m     v1.19.7
192.168.0.18   Ready    <none>   98m     v1.19.7
192.168.0.21   Ready    <none>   2m26s   v1.19.7
```

4.4、手动approve server cert csr
```
# kubectl get csr | grep Pending | awk '{print $1}' | xargs kubectl certificate approve
```
5、部署kube-proxy
同样，只需要分发文件后，启动kube-proxy即可
5.0、分发文件到新的节点
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for (( i=0; i < 6; i++ ))
do
    sed -e "s/##NODE_IP##/${NODE_IPS[i]}/" /opt/k8s/conf/kube-proxy.service.template > \
           /opt/k8s/conf/kube-proxy-${NODE_IPS[i]}.service
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" \
    /opt/k8s/conf/kube-proxy-config.yaml.template > /opt/k8s/conf/kube-proxy-config-${NODE_IPS[i]}.yaml.template
done

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    scp /opt/k8s/ssl/kube-proxy.kubeconfig ${host}:/opt/k8s/ssl
    scp /opt/k8s/conf/kube-proxy-${host}.service ${host}:/etc/systemd/system/kube-proxy.service
    scp /opt/k8s/conf/kube-proxy-config-${host}.yaml.template \
        ${host}:/etc/kubernetes/kube-proxy-config.yaml
    scp /opt/k8s/packages/conntrack ${host}:/opt/k8s/bin/
    scp /opt/k8s/packages/kubernetes/server/bin/kube-proxy ${host}:/opt/k8s/bin/
    ssh root@${host} "chmod +x /opt/k8s/bin/*"
done
```
5.1、启动kube-proxy服务
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "mkdir -p ${K8S_DIR}/kube-proxy"
        ssh root@${host} "modprobe ip_vs_rr"
    ssh root@${host} "systemctl daemon-reload && \
                      systemctl enable kube-proxy --now && \
                      systemctl status kube-proxy | grep Active"
done
```
5.2、查看kube-proxy端口
```
#!/usr/bin/env bash
# source /opt/k8s/bin/k8s-env.sh

# for host in ${NODE_IPS[@]}
do
    printf "\e[1;34m${host}\e[0m\n"
    ssh root@${host} "ss -nltp | grep kube-proxy"
done
```
到此，kubernetes集群扩容结束
