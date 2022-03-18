#!/bin/bash
if [ -z "$4" ];then
   echo '请正确的传入四个启动参数,config.file、client.url、job名称、日志路径'
   exit 1
fi

echo 'client:      # 配置Promtail如何连接到Loki的实例
  backoff_config:      # 配置当请求失败时如何重试请求给Loki
    max_period: 5m 
    max_retries: 10
    min_period: 500ms
  batchsize: 1048576      # 发送给Loki的最大批次大小(以字节为单位)
  batchwait: 1s      # 发送批处理前等待的最大时间（即使批次大小未达到最大值）
  timeout: 10s      # 等待服务器响应请求的最大时间
positions:
  filename: /etc/promtail/positions.yaml
server:
  http_listen_port: 3101
  grpc_listen_port: 0
target_config:
  sync_period: 10s
scrape_configs:
- job_name: hrfax-log
  static_configs:
  - labels:
      __path__: logpath/**/*.log  ##占位符
      job: servicename  ##占位符
    targets:
    - localhost' > /etc/promtail/promtail.yaml

sed -i "s#servicename#$3#g" /etc/promtail/promtail.yaml
sed -i "s#logpath#$4#g" /etc/promtail/promtail.yaml
sleep 60 #延迟启动时间，防止启动的过快，业务服务日志没打印出来
/usr/bin/promtail $1 $2
