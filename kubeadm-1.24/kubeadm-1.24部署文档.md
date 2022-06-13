# 引言
```
kubeadm 是 Kubernetes 官方提供的用于快速安部署 Kubernetes 集群的工具，伴随 Kubernetes 每个版本的发布都会同步更新，kubeadm 会对集群配置方面的一些实践做调整，通过实验 kubeadm 可以学习到 Kubernetes 官方在集群配置上一些新的最佳实践。
```

# 一、准备
1.1、系统配置
在安装之前，需要先做好如下准备。2 台 CentOS 7.9 主机如下：
```
# cat /etc/hosts
192.168.137.8    node1
192.168.137.9    node2
```

1.2、修改主机名
```
hostnamectl set-hostname node1
hostnamectl set-hostname node2
```
1.3 所有k8s节点关闭selinux及firewalld
```
# getenforce
# vi /etc/selinux/config
SELINUX=disabled

# setenforce 0
# systemctl disable firewalld
# systemctl stop firewalld
```
1.4 所有k8s节点禁用swap
```
# swapoff -a

禁用fstab中的swap项目
# vi /etc/fstab
#/dev/mapper/centos-swap swap                    swap    defaults        0 0

确认swap已经被禁用
# cat /proc/swaps
Filename                Type        Size    Used    Priority
```

1.5 同步时区及时间
```
# ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
# echo 'Asia/Shanghai' >/etc/timezone
# ntpdate time2.aliyun.com

计划任务同步时间
# echo '*/15 * * * *   ntpdate time2.aliyun.com' >>  /var/spool/cron/root
```
1.6 limit配置
```
# ulimit -SHn 65535
```
1.7 镜像源配置
```
# cd /etc/yum.repos.d
# mkdir bak
# mv *.repo bak/
```
```
# echo '[base]
name=CentOS-$releasever - Base - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/os/$basearch/
        http://mirrors.aliyuncs.com/centos/$releasever/os/$basearch/
        http://mirrors.cloud.aliyuncs.com/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7

#released updates
[updates]
name=CentOS-$releasever - Updates - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/updates/$basearch/
        http://mirrors.aliyuncs.com/centos/$releasever/updates/$basearch/
        http://mirrors.cloud.aliyuncs.com/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7

#additional packages that may be useful
[extras]
name=CentOS-$releasever - Extras - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/extras/$basearch/
        http://mirrors.aliyuncs.com/centos/$releasever/extras/$basearch/
        http://mirrors.cloud.aliyuncs.com/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7

#additional packages that extend functionality of existing packages
[centosplus]
name=CentOS-$releasever - Plus - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/centosplus/$basearch/
        http://mirrors.aliyuncs.com/centos/$releasever/centosplus/$basearch/
        http://mirrors.cloud.aliyuncs.com/centos/$releasever/centosplus/$basearch/
gpgcheck=1
enabled=0
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7

#contrib - packages by Centos Users
[contrib]
name=CentOS-$releasever - Contrib - mirrors.aliyun.com
failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/contrib/$basearch/
        http://mirrors.aliyuncs.com/centos/$releasever/contrib/$basearch/
        http://mirrors.cloud.aliyuncs.com/centos/$releasever/contrib/$basearch/
gpgcheck=1
enabled=0
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-7
' > CentOS-Base.repo
```
```
# echo '[epel]
name=Extra Packages for Enterprise Linux 7 - $basearch
baseurl=http://mirrors.aliyun.com/epel/7/$basearch
failovermethod=priority
enabled=1
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7

[epel-debuginfo]
name=Extra Packages for Enterprise Linux 7 - $basearch - Debug
baseurl=http://mirrors.aliyun.com/epel/7/$basearch/debug
failovermethod=priority
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
gpgcheck=0

[epel-source]
name=Extra Packages for Enterprise Linux 7 - $basearch - Source
baseurl=http://mirrors.aliyun.com/epel/7/SRPMS
failovermethod=priority
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
gpgcheck=0
' > epel-7.repo
```
```
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
        http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
```

1.8 免密登录
```
# ssh-keygen -t rsa
# for i in node1 node2; do ssh-copy-id -i /root/.ssh/id_rsa.pub $i; done
```

1.9 内核优化
```
# yum install wget jq psmisc vim net-tools -y

更新时不升级内核
# yum update --exclude=kernel* -y

升级内核下载rpm包，文明上网下载
# wget https://cbs.centos.org/kojifiles/packages/kernel/4.9.220/37.el7/x86_64/kernel-4.9.220-37.el7.x86_64.rpm

拷贝至其他机器
# for i in node1 node2; do scp kernel-4.9.220-37.el7.x86_64.rpm  $i:/root; done

# rpm -ivh kernel-4.9.220-37.el7.x86_64.rpm

更改内核启动顺序
# grub2-set-default 0 && grub2-mkconfig -o /etc/grub2.cfg
# grubby --args="user_namespace.enable=1" --update-kernel="$(grubby --default-kernel)"


查看默认的内核
# grubby --default-kernel

# reboot

安装ipvs：
# yum install ipvsadm ipset sysstat conntrack libseccomp -y

# cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack
modprobe -- ip_tables
modprobe -- ip_set
modprobe -- xt_set
modprobe -- ipt_set
modprobe -- ipt_rpfilter
modprobe -- ipt_REJECT
modprobe -- ipip
EOF

注意：在内核4.19版本nf_conntrack_ipv4已经改为nf_conntrack

# chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep -e ip_vs -e nf_conntrack

内核参数优化
# cat <<EOF > /etc/sysctl.d/k8s.conf

net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
fs.may_detach_mounts = 1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720
net.ipv4.tcp_keepalive_time = 850
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_max_orphans = 327680

net.ipv4.tcp_orphans_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.netfilter.nf_conntrack_max=65535
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384

EOF

# sysctl --system
```

# 二、准备部署容器运行时 Containerd
在各个服务器节点上安装容器运行时 Containerd。
cri-containerd-cni-1.6.6-linux-amd64.tar.gz 压缩包中已经按照官方二进制部署推荐的目录结构布局好。 里面包含了 systemd 配置文件，containerd 以及 cni 的部署文件。 将解压缩到系统的根目录 / 中:
```
# wget https://github.com/containerd/containerd/releases/download/v1.6.6/cri-containerd-cni-1.6.6-linux-amd64.tar.gz

#  tar -zxvf cri-containerd-cni-1.6.6-linux-amd64.tar.gz -C /
etc/
etc/systemd/
etc/systemd/system/
etc/systemd/system/containerd.service
etc/crictl.yaml
etc/cni/
etc/cni/net.d/
etc/cni/net.d/10-containerd-net.conflist
usr/
usr/local/
usr/local/sbin/
usr/local/sbin/runc
usr/local/bin/
usr/local/bin/critest
usr/local/bin/containerd-shim
usr/local/bin/containerd-shim-runc-v1
usr/local/bin/ctd-decoder
usr/local/bin/containerd
usr/local/bin/containerd-shim-runc-v2
usr/local/bin/containerd-stress
usr/local/bin/ctr
usr/local/bin/crictl
......
opt/cni/
opt/cni/bin/
opt/cni/bin/bridge
......
注意经测试 cri-containerd-cni-1.6.6-linux-amd64.tar.gz 包中包含的 runc 在 CentOS 7 下的动态链接有问题，这里从 runc 的 github 上单独下载 runc，并替换上面安装的 containerd 中的 runc:

# wget https://github.com/opencontainers/runc/releases/download/v1.1.2/runc.amd64
# chmod 755 runc.amd64
# mv runc.amd64 /usr/local/sbin/runc
# rm -rf /usr/sbin/bridge
# echo 'export PATH=$PATH:/opt/cni/bin' >> /etc/profile
# source /etc/profile

接下来生成 containerd 的配置文件:
# mkdir -p /etc/containerd
# containerd config default > /etc/containerd/config.toml
根据文档 Container runtimes 中的内容，对于使用 systemd 作为 init system 的 Linux 的发行版，使用 systemd 作为容器的 cgroup driver 可以确保服务器节点在资源紧张的情况更加稳定，因此这里配置各个节点上 containerd 的 cgroup driver 为 systemd。修改前面生成的配置文件 /etc/containerd/config.toml：

# vim /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true

[plugins."io.containerd.grpc.v1.cri"]
  ...
  # sandbox_image = "k8s.gcr.io/pause:3.6"
  sandbox_image = "registry.aliyuncs.com/google_containers/pause:3.7"

    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = ""

      [plugins."io.containerd.grpc.v1.cri".registry.auths]

      [plugins."io.containerd.grpc.v1.cri".registry.configs]

      [plugins."io.containerd.grpc.v1.cri".registry.headers]


      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]

      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.hrfax.net:5000"]
        endpoint = ["http://registry.hrfax.net:5000"]

      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://pkeh50sq.mirror.aliyuncs.com"]



配置 containerd 开机启动，并启动 containerd

# systemctl enable containerd --now
使用 crictl 测试一下，确保可以打印出版本信息并且没有错误信息输出:

# crictl version
Version:  0.1.0
RuntimeName:  containerd
RuntimeVersion:  v1.6.4
RuntimeApiVersion:  v1alpha2
```
# 三、使用 kubeadm 部署 Kubernetes
3.1、所有节点安装 kubeadm 和 kubelet
```
# yum install kubelet-1.24.1-0.x86_64  kubeadm-1.24.1-0.x86_64  kubectl.x86_64.0.1.24.1-0.x86_64

运行 kubelet --help 可以看到原来 kubelet 的绝大多数命令行 flag 参数都被 DEPRECATED 了，官方推荐我们使用 --config 指定配置文件，并在配置文件中指定原来这些 flag 所配置的内容。具体内容可以查看这里 Set Kubelet parameters via a config file。最初 Kubernetes 这么做是为了支持动态 Kubelet 配置（Dynamic Kubelet Configuration），但动态 Kubelet 配置特性从 k8s 1.22 中已弃用，并在 1.24 中被移除。如果需要调整集群汇总所有节点 kubelet 的配置，还是推荐使用 ansible 等工具将配置分发到各个节点。kubelet 的配置文件必须是 json 或 yaml 格式，具体可查看这里。
```

3.2、使用 kubeadm init 初始化集群
在各节点开机启动 kubelet 服务：
```
systemctl enable kubelet.service
```
```
KubeletConfiguration 可以打印集群初始化默认的使用的配置：
# kubeadm config print init-defaults --component-configs
apiVersion: kubeadm.k8s.io/v1beta3
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 1.2.3.4
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  imagePullPolicy: IfNotPresent
  name: node
  taints: null
---
apiServer:
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta3
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns: {}
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: k8s.gcr.io
kind: ClusterConfiguration
kubernetesVersion: 1.24.0
networking:
  dnsDomain: cluster.local
  serviceSubnet: 10.96.0.0/12
scheduler: {}
---
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 0s
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 0s
    cacheUnauthorizedTTL: 0s
cgroupDriver: systemd
clusterDNS:
- 10.96.0.10
clusterDomain: cluster.local
cpuManagerReconcilePeriod: 0s
evictionPressureTransitionPeriod: 0s
fileCheckFrequency: 0s
healthzBindAddress: 127.0.0.1
healthzPort: 10248
httpCheckFrequency: 0s
imageMinimumGCAge: 0s
kind: KubeletConfiguration
logging:
  flushFrequency: 0
  options:
    json:
      infoBufferSize: "0"
  verbosity: 0
memorySwap: {}
nodeStatusReportFrequency: 0s
nodeStatusUpdateFrequency: 0s
rotateCertificates: true
runtimeRequestTimeout: 0s
shutdownGracePeriod: 0s
shutdownGracePeriodCriticalPods: 0s
staticPodPath: /etc/kubernetes/manifests
streamingConnectionIdleTimeout: 0s
syncFrequency: 0s
volumeStatsAggPeriod: 0s
```
从默认的配置中可以看到，可以使用 imageRepository 定制在集群初始化时拉取 k8s 所需镜像的地址。基于默认配置定制出本次使用 kubeadm 初始化集群所需的配置文件 kubeadm.yaml：
```
# vi kubeadm.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.137.8
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  taints:
  - effect: PreferNoSchedule
    key: node-role.kubernetes.io/master
---
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: v1.24.0
imageRepository: registry.aliyuncs.com/google_containers
networking:
  podSubnet: 10.244.0.0/16
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
failSwapOn: false
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
```
这里定制了 imageRepository 为阿里云的 registry，避免因 gcr 被墙，无法直接拉取镜像。criSocket 设置了容器运行时为 containerd。 同时设置 kubelet 的 cgroupDriver 为 systemd，设置 kube-proxy 代理模式为 ipvs。在开始初始化集群之前可以使用 kubeadm config images pull --config kubeadm.yaml 预先在各个服务器节点上拉取所 k8s 需要的容器镜像。
```
# kubeadm config images pull --config kubeadm.yaml
[config/images] Pulled registry.aliyuncs.com/google_containers/kube-apiserver:v1.24.0
[config/images] Pulled registry.aliyuncs.com/google_containers/kube-controller-manager:v1.24.0
[config/images] Pulled registry.aliyuncs.com/google_containers/kube-scheduler:v1.24.0
[config/images] Pulled registry.aliyuncs.com/google_containers/kube-proxy:v1.24.0
[config/images] Pulled registry.aliyuncs.com/google_containers/pause:3.7
[config/images] Pulled registry.aliyuncs.com/google_containers/etcd:3.5.3-0
[config/images] Pulled registry.aliyuncs.com/google_containers/coredns:v1.8.6
```
接下来使用 kubeadm 初始化集群，选择 node1 作为 Master Node，在 node1 上执行下面的命令：
```
# kubeadm init --config kubeadm.yaml
W0608 19:17:31.852120    1876 common.go:83] your configuration file uses a deprecated API spec: "kubeadm.k8s.io/v1beta2". Please use 'kubeadm config migrate --old-config old.yaml --new-config new.yaml', which will write the new, similar spec using a newer API version.
[init] Using Kubernetes version: v1.24.0
[preflight] Running pre-flight checks
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action in beforehand using 'kubeadm config images pull'
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "ca" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local node1] and IPs [10.96.0.1 192.168.137.8]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-ca" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Generating "etcd/ca" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [localhost node1] and IPs [192.168.137.8 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [localhost node1] and IPs [192.168.137.8 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests". This can take up to 4m0s
[apiclient] All control plane components are healthy after 10.005469 seconds
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config" in namespace kube-system with the configuration for the kubelets in the cluster
[upload-certs] Skipping phase. Please see --upload-certs
[mark-control-plane] Marking the node node1 as control-plane by adding the labels: [node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[mark-control-plane] Marking the node node1 as control-plane by adding the taints [node-role.kubernetes.io/master:PreferNoSchedule]
[bootstrap-token] Using token: m5ez5e.zk5m4q3mw2u57aaf
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] Configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] Configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.137.8:6443 --token m5ez5e.zk5m4q3mw2u57aaf \
	--discovery-token-ca-cert-hash sha256:706bd94e2bf10d1030453ceb4091ed44318b333c7f909708bf99107fdd024807 

上面记录了完成的初始化输出的内容，根据输出的内容基本上可以看出手动初始化安装一个 Kubernetes 集群所需要的关键步骤。 其中有以下关键内容：

[certs]生成相关的各种证书
[kubeconfig]生成相关的kubeconfig文件
[kubelet-start] 生成kubelet的配置文件"/var/lib/kubelet/config.yaml"
[control-plane]使用/etc/kubernetes/manifests目录中的yaml文件创建apiserver、controller-manager、scheduler的静态pod
[bootstraptoken]生成token记录下来，后边使用kubeadm join往集群中添加节点时会用到

# cat  <<EOF >> /root/.bashrc
export KUBECONFIG=/etc/kubernetes/admin.conf
EOF
# source  /root/.bashrc
```
3.3、安装包管理器 helm 3
Helm 是 Kubernetes 的包管理器，后续流程也将使用 Helm 安装 Kubernetes 的常用组件。 这里先在 master 节点 node1 上安装 helm。
```
# wget https://get.helm.sh/helm-v3.9.0-linux-amd64.tar.gz
# tar -zxvf helm-v3.9.0-linux-amd64.tar.gz
# mv linux-amd64/helm  /usr/local/bin/
执行 helm list 确认没有错误输出。
```

3.4、部署 Pod Network 组件 Calico
选择 calico 作为 k8s 的 Pod 网络组件，下面使用 helm 在 k8s 集群中安装 calico。下载 tigera-operator 的 helm chart:
```
# wget https://github.com/projectcalico/calico/releases/download/v3.23.1/tigera-operator-v3.23.1.tgz
```
查看这个 chart 的中可定制的配置:
```
# helm show values tigera-operator-v3.23.1.tgz
imagePullSecrets: {}

installation:
  enabled: true
  kubernetesProvider: ""

apiServer:
  enabled: true

certs:
  node:
    key:
    cert:
    commonName:
  typha:
    key:
    cert:
    commonName:
    caBundle:

resources: {}

# Configuration for the tigera operator
tigeraOperator:
  image: tigera/operator
  version: v1.27.1
  registry: quay.io
calicoctl:
  image: docker.io/calico/ctl
  tag: v3.23.1
```
可针对上面的配置进行定制,例如 calico 的镜像改成从私有库拉取。
使用 helm 安装 calico：
```
# tar fx tigera-operator-v3.23.1.tgz
# helm install calico tigera-operator-v3.23.1.tgz -n kube-system  --create-namespace -f tigera-operator/values.yaml
```
等待并确认所有 pod 处于 Running状态:
```
# kubectl get pod -n kube-system | grep tigera-operator
tigera-operator-5fb55776df-wxbph   1/1     Running   0             5m10s

# kubectl get pods -n calico-system
NAME                                       READY   STATUS    RESTARTS   AGE
calico-kube-controllers-68884f975d-5d7p9   1/1     Running   0          5m24s
calico-node-twbdh                          1/1     Running   0          5m24s
calico-typha-7b4bdd99c5-ssdn2              1/1     Running   0          5m24s
```
查看一下 calico 向 k8s 中添加的 api 资源:
```
# kubectl api-resources | grep calico
bgpconfigurations                                                                 crd.projectcalico.org/v1               false        BGPConfiguration
bgppeers                                                                          crd.projectcalico.org/v1               false        BGPPeer
blockaffinities                                                                   crd.projectcalico.org/v1               false        BlockAffinity
caliconodestatuses                                                                crd.projectcalico.org/v1               false        CalicoNodeStatus
clusterinformations                                                               crd.projectcalico.org/v1               false        ClusterInformation
felixconfigurations                                                               crd.projectcalico.org/v1               false        FelixConfiguration
globalnetworkpolicies                                                             crd.projectcalico.org/v1               false        GlobalNetworkPolicy
globalnetworksets                                                                 crd.projectcalico.org/v1               false        GlobalNetworkSet
hostendpoints                                                                     crd.projectcalico.org/v1               false        HostEndpoint
ipamblocks                                                                        crd.projectcalico.org/v1               false        IPAMBlock
ipamconfigs                                                                       crd.projectcalico.org/v1               false        IPAMConfig
ipamhandles                                                                       crd.projectcalico.org/v1               false        IPAMHandle
ippools                                                                           crd.projectcalico.org/v1               false        IPPool
ipreservations                                                                    crd.projectcalico.org/v1               false        IPReservation
kubecontrollersconfigurations                                                     crd.projectcalico.org/v1               false        KubeControllersConfiguration
networkpolicies                                                                   crd.projectcalico.org/v1               true         NetworkPolicy
networksets                                                                       crd.projectcalico.org/v1               true         NetworkSet
bgpconfigurations                 bgpconfig,bgpconfigs                            projectcalico.org/v3                   false        BGPConfiguration
bgppeers                                                                          projectcalico.org/v3                   false        BGPPeer
caliconodestatuses                caliconodestatus                                projectcalico.org/v3                   false        CalicoNodeStatus
clusterinformations               clusterinfo                                     projectcalico.org/v3                   false        ClusterInformation
felixconfigurations               felixconfig,felixconfigs                        projectcalico.org/v3                   false        FelixConfiguration
globalnetworkpolicies             gnp,cgnp,calicoglobalnetworkpolicies            projectcalico.org/v3                   false        GlobalNetworkPolicy
globalnetworksets                                                                 projectcalico.org/v3                   false        GlobalNetworkSet
hostendpoints                     hep,heps                                        projectcalico.org/v3                   false        HostEndpoint
ippools                                                                           projectcalico.org/v3                   false        IPPool
ipreservations                                                                    projectcalico.org/v3                   false        IPReservation
kubecontrollersconfigurations                                                     projectcalico.org/v3                   false        KubeControllersConfiguration
networkpolicies                   cnp,caliconetworkpolicy,caliconetworkpolicies   projectcalico.org/v3                   true         NetworkPolicy
networksets                       netsets                                         projectcalico.org/v3                   true         NetworkSet
profiles                                                                          projectcalico.org/v3                   false        Profile
```
这些 api 资源是属于 calico 的，因此不建议使用 kubectl 来管理，推荐按照 calicoctl 来管理这些 api 资源。 将 calicoctl 安装为 kubectl 的插件:
```
# cd /usr/local/bin
# curl -o calicoctl -O -L  "https://github.com/projectcalico/calicoctl/releases/download/v3.21.5/calicoctl-linux-amd64" 
# chmod +x calicoctl
# calicoctl -h
```
3.5、验证 k8s DNS 是否可用
```
# kubectl run curl --image=radial/busyboxplus:curl -it
If you don't see a command prompt, try pressing enter.
[ root@curl:/ ]$
进入后执行 nslookup kubernetes.default 确认解析正常:

nslookup kubernetes.default
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
 
Name:      kubernetes.default
Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
```
3.6、向 Kubernetes 集群中添加 Node 节点
下面将 node2添加到 Kubernetes 集群中，在 node2上执行:
```
# kubeadm join 192.168.137.8:6443 --token m5ez5e.zk5m4q3mw2u57aaf \
	--discovery-token-ca-cert-hash sha256:706bd94e2bf10d1030453ceb4091ed44318b333c7f909708bf99107fdd024807 
```
在 master 节点上执行命令查看集群中的节点：
```
# kubectl get node
NAME    STATUS   ROLES                  AGE     VERSION
node1   Ready    control-plane,master   29m     v1.24.0
node2   Ready    <none>                 70s     v1.24.0

```

3.7 命令自动补全
```
# yum install -y bash-completion
# source /usr/share/bash-completion/bash_completion
# source <(kubectl completion bash)
# source <(crictl completion bash)
# echo "source <(kubectl completion bash)" >> ~/.bashrc
# echo "source <(crictl completion bash)" >> ~/.bashrc

```
