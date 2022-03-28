

#### kubecm

kubecm由 golang 编写，支持 `Mac` `Linux` 和 `windows` 平台，`delete` `rename` `switch` 提供比较实用的交互式的操作，目前的功能包括：

- add ：添加新的 `kubeconfig` 到 `$HOME/.kube/config` 中
- completion ：命令行自动补全功能
- delete：删除已有的 `context` ，提供交互式和指定删除两种方式
- merge：将指定目录中的 `kubeconfig` 合并为一个 `kubeconfig` 文件
- rename：重名指定的 `context`，提供交互式和指定重命名两种方式
- switch：交互式切换 `context`

#### kubeconfig文件结构

`kubeconfig` 文件主要由下面几部分构成： 集群参数、用户参数、上下文参数、当前上下文

```
apiVersion: v1
clusters: #集群参数
- cluster:
    certificate-authority-data: 
    server: https://172.16.xx.xx:6443
  name: cluster1
contexts: #上下文参数
- context:
    cluster: cluster1
    user: admin
  name: context-cluster1-admin #集群上下文名称
current-context: context-cluster1-admin # 当前上下文
kind: Config
preferences: {}
users: #用户参数
- name: admin
  user:
    client-certificate-data: 
    client-key-data: 
```

#### kubecm安装

```
# 下载地址如下(根据自己的操作系统，这里是centos):
https://github.com/sunny0826/kubecm/releases
wget https://github.com/sunny0826/kubecm/releases/download/v0.16.3/kubecm_0.16.3_Linux_x86_64.tar.gz

# 解压
tar xf kubecm_0.16.3_Linux_x86_64.tar.gz
# 移动到/usr/local/bin
mv kubecm /usr/local/bin/
```

##### 命令行自动补全

```
source <(kubecm completion bash)
echo "source <(kubecm completion bash)" >> ~/.bashrc
source  ~/.bashrc
```

##### kubecm使用

###### 查看

```
# 查看 $HOME/.kube/config 中所有的 context
$ +------------+---------------------------+-------------+----------+--------------+
|   CURRENT  |            NAME           |   CLUSTER   |   USER   |   Namespace  |
+============+===========================+=============+==========+==============+
|      *     |   context-cluster1-admin  |   cluster1  |   admin  |              |
+------------+---------------------------+-------------+----------+--------------+
...
```

###### 添加

```
# 添加 example.yaml(也可以直接用config文件) 到 $HOME/.kube/config.yaml，该方式不会覆盖源 kubeconfig，只会在当前目录中生成一个 config.yaml 文件
# 我这里没用.yaml文件。直接用的config文件
$ ls
all_config  config-aliyun
$ kubecm add -f config-aliyun
generate ./config.yaml
$ ls
all_config  config-aliyun  config.yaml


# 功能同上，但是会将 example.yaml 中的 context 命名为 test
$ kubecm add -f config-aliyun -n test
generate ./config.yaml


# 添加 -c 会覆盖源 kubeconfig
$ kubecm add -f config-aliyun -c
「config-aliyun」 add successful!
+------------+---------------------------+-----------------------+--------------------+--------------+
|   CURRENT  |            NAME           |        CLUSTER        |        USER        |   Namespace  |
+============+===========================+=======================+====================+==============+
|            |       config-aliyun       |   cluster-bh6mb7k26h  |   user-bh6mb7k26h  |              |
+------------+---------------------------+-----------------------+--------------------+--------------+
|      *     |   context-cluster1-admin  |        cluster1       |        admin       |              |
+------------+---------------------------+-----------------------+--------------------+--------------+

```

###### 删除

```
# 交互式删除
$ kubecm delete
Use the arrow keys to navigate: ↓ ↑ → ←  and / toggles search
Select The Delete Kube Context
  😼 context-cluster1-admin(*)
    config-aliyun
    <Exit>

--------- Info ----------
Name:           context-cluster1-admin
Cluster:        cluster1
User:           admin

# 删除指定context
$  kubecm delete config-aliyun
Context Delete:「config-aliyun」
```

###### 合并

```
# 合并 all_config 目录中的 kubeconfig,该方式不会覆盖源 kubeconfig，只会在当前目录中生成一个 config.yaml 文件
$ kubecm merge -f all_config/
Loading kubeconfig file: [all_config//config-154 all_config//config-202]
Context Add: config-154
Context Add: config-202
# 添加 -c 会覆盖源 kubeconfig
$ kubecm merge -f all_config/ -c
Loading kubeconfig file: [all_config//config-154 all_config//config-202]
Context Add: config-154
Context Add: config-202

$ kubecm
+------------+---------------+-----------------------+--------------------+--------------+
|   CURRENT  |      NAME     |        CLUSTER        |        USER        |   Namespace  |
+============+===============+=======================+====================+==============+
|            |   config-154  |   cluster-8ft42c2chh  |   user-8ft42c2chh  |              |
+------------+---------------+-----------------------+--------------------+--------------+
|      *     |   config-202  |   cluster-h55g4kbd78  |   user-h55g4kbd78  |              |
+------------+---------------+-----------------------+--------------------+--------------+
...
```

###### 重命名

```
# 交互式重命名
$ kubecm rename
😸 Select:config-202
Rename: congig-202-1█
+------------+-----------------+-----------------------+--------------------+--------------+
|   CURRENT  |       NAME      |        CLUSTER        |        USER        |   Namespace  |
+============+=================+=======================+====================+==============+
|      *     |   congig-202-1  |   cluster-h55g4kbd78  |   user-h55g4kbd78  |              |
+------------+-----------------+-----------------------+--------------------+--------------+
|            |    config-154   |   cluster-8ft42c2chh  |   user-8ft42c2chh  |              |
+------------+-----------------+-----------------------+--------------------+--------------+

# 将 congig-202-1 重命名为 test
$ kubecm rename -o congig-202-1 -n test
+------------+---------------+-----------------------+--------------------+--------------+
|   CURRENT  |      NAME     |        CLUSTER        |        USER        |   Namespace  |
+============+===============+=======================+====================+==============+
|            |   config-154  |   cluster-8ft42c2chh  |   user-8ft42c2chh  |              |
+------------+---------------+-----------------------+--------------------+--------------+
|      *     |      test     |   cluster-h55g4kbd78  |   user-h55g4kbd78  |              |
+------------+---------------+-----------------------+--------------------+--------------+
# 重命名当前current-context 为 dev
$ kubecm rename -n dev -c
Rename test to dev
+------------+---------------+-----------------------+--------------------+--------------+
|   CURRENT  |      NAME     |        CLUSTER        |        USER        |   Namespace  |
+============+===============+=======================+====================+==============+
|            |   config-154  |   cluster-8ft42c2chh  |   user-8ft42c2chh  |              |
+------------+---------------+-----------------------+--------------------+--------------+
|      *     |      dev      |   cluster-h55g4kbd78  |   user-h55g4kbd78  |              |
+------------+---------------+-----------------------+--------------------+--------------+
```

###### 切换

```
# 集群切换
$ kubecm switch
Use the arrow keys to navigate: ↓ ↑ → ←  and / toggles search
Select Kube Context
  😼 config-154(*)
    dev
    <Exit>

--------- Info ----------
Name:           config-154
Cluster:        cluster-8ft42c2chh
User:           user-8ft42c2chh

# 切换命名空间
$ kubecm ns
Use the arrow keys to navigate: ↓ ↑ → ←  and / toggles search
Select Namespace:
↑ 🚩  default *
   demo
   dev
↓  exdns
```
