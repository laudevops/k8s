### 部署步骤
#### 1.部署nfs
#### yum -y install nfs-utils rpcbind
#### 2.配置NFS主文件/etc/export
#### /data/consul *(rw,sync,no_root_squash)
#### 3. 使用exportfs -r命令使NFS配置生效
#### 4.启动
#### systemctl start nfs-server 
#### systemctl enable nfs-server
#### 5.查看是否启动
#### rpcinfo -p命令确认NFS是否已经启动
#### 6.使用showmount -e 127.0.0.1查看本机共享的路径
#### 一般挂载命令
#### mount -t nfs -o rw ip:/路径  /本地路径
#### 7.创建pv
#### 修改配置文件 改为上边nfs的目录
#### kubectl apply -f nfs_pv.yaml
#### 8.创建configmap
#### kubectl  create configmap consul-acl-config --from-file=Acl.json  --namespace=default
#### 9.创建StateFulSet.yaml  UiSrvice.yaml  PortService.yaml 

