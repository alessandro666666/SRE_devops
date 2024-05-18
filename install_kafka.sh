#!/bin/bash

# 参数配置
KAFKA_VERSION="3.6.1"
SCALA_VERSION="2.13"


# 1. 安装 JDK
if command -v java &>/dev/null; then
    echo "Java已安装"
else
    # 检查/opt目录下是否存在jdk-17_linux-x64_bin.tar.gz或者jdk-8u212-linux-x64.tar.gz包
    if [ -f "/opt/jdk-17_linux-x64_bin.tar.gz" ] || [ -f "/opt/jdk-8u212-linux-x64.tar.gz" ]; then
        # 如果存在相应的tar.gz包，则显示"正在安装 Java..."的提示信息
        echo "正在安装 Java..."
        # 解压对应的tar.gz包
        if [ -f "/opt/jdk-17_linux-x64_bin.tar.gz" ]; then
            tar zxvf /opt/jdk-17_linux-x64_bin.tar.gz -C /usr/local/src
        fi
        if [ -f "/opt/jdk-8u212-linux-x64.tar.gz" ]; then
            tar zxvf /opt/jdk-8u212-linux-x64.tar.gz -C /usr/local/src
        fi
        # 检查/usr/local/jdk目录是否存在，不存在则创建
        if [ ! -d "/usr/local/jdk" ]; then
            mkdir -p /usr/local/jdk
        fi
        # 将解压后的文件复制到/usr/local/jdk目录
        rsync -avz /usr/local/src/jdk*/* /usr/local/jdk/
        # 创建符号链接
        ln -sfnv /usr/local/jdk/bin/* /bin/
        ln -sfnv /usr/local/jdk/bin/* /usr/bin/
    else
        # 如果/opt目录下没有发现相应的tar.gz包，则打印提示信息并退出
        echo "未发现jdk-17_linux-x64_bin.tar.gz或jdk-8u212-linux-x64.tar.gz包，请先下载"
        exit 1
    fi
fi


# 2. 下载和配置 Zookeeper
KAFKA_BINARY_URL="https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
KAFKA_INSTALL_DIR="/usr/local"
KAFKA_DIR="${KAFKA_INSTALL_DIR}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}"

if [ ! -d "${KAFKA_DIR}" ]; then
    echo "正在下载并解压 Kafka..."
    if [ ! -f "/opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz" ]; then
        wget -q "${KAFKA_BINARY_URL}" -P /opt/
    fi
    tar -zxf "/opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz" -C "${KAFKA_INSTALL_DIR}"
    ln -s "${KAFKA_DIR}" "${KAFKA_INSTALL_DIR}/kafka"
    echo "Kafka 安装成功"
fi

# 配置 Zookeeper
ZOOKEEPER_CONFIG_FILE="/usr/local/kafka/config/zookeeper.properties"

cat >${ZOOKEEPER_CONFIG_FILE} <<EOF
tickTime=2000
initLimit=20
syncLimit=5
dataDir=/data/zookeeper
clientPort=2181
autopurge.snapRetainCount=30
autopurge.purgeInterval=72
EOF

# 通过手动输入获取 Zookeeper 节点
echo "请输入 Zookeeper 节点，用逗号分隔（例如：10.10.10.10,10.10.10.11,10.10.10.12）："
read -p "> " ZOOKEEPER_NODES_INPUT

IFS=',' read -ra NODES <<< "$ZOOKEEPER_NODES_INPUT"
# 遍历数组并拼接成需要的格式
ZOOKEEPER_INFORMATION=""
for NODE in "${NODES[@]}"; do
    ZOOKEEPER_INFORMATION+="$(echo "$NODE" | tr -d ' '):2181,"
done

# 删除末尾多余的逗号
ZOOKEEPER_INFORMATION="${ZOOKEEPER_INFORMATION%,}"
echo $ZOOKEEPER_INFORMATION
IFS=',' read -ra ZOOKEEPER_NODES <<<"${ZOOKEEPER_NODES_INPUT}"

for i in "${!ZOOKEEPER_NODES[@]}"; do
    echo "server.$((i + 1))=${ZOOKEEPER_NODES[i]}:2888:3888" >>"${ZOOKEEPER_CONFIG_FILE}"
done



myid_file="/data/zookeeper/myid"

if [ ! -d "/data/zookeeper/" ]; then
    mkdir /data/zookeeper/ 
fi

# 从用户输入中读取数字
read -p "请输入节点ID: " node_id

# 验证输入是否为数字
if [[ ! $node_id =~ ^[0-9]+$ ]]; then
    echo "错误: 请输入有效的数字 ID。"
    exit 1
fi

# 将数字写入myid文件
echo "$node_id" > "$myid_file"
echo "节点 ID $node_id 已写入到 $myid_file"
LOCAL_IP=$(hostname -I | awk '{print $1}')
BROKER_ID=$(echo $LOCAL_IP | tr -d '.')


# 配置 Zookeeper 服务
cat >/usr/lib/systemd/system/zookeeper.service <<EOF
[Unit]
Description=Zookeeper 服务
After=network.target remote-fs.target
[Service]
Type=forking
ExecStart=/usr/local/kafka/bin/zookeeper-server-start.sh -daemon /usr/local/kafka/config/zookeeper.properties
ExecStop=/usr/local/kafka/bin/zookeeper-server-stop.sh
Restart=on-abnormal
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable zookeeper && systemctl start zookeeper && systemctl status zookeeper
# 配置 Kafka
KAFKA_CONFIG_FILE="/usr/local/kafka/config/server.properties"
useradd kafka

if [ ! -d "/data/kafka/logs" ]; then
    mkdir -p /data/kafka/logs
fi
LOCAL_IP=$(hostname -I|awk '{print $1}')

# 从用户输入中获取Kafka端口号
read -p "请输入 Kafka 端口号: " KAFKA_PORT
# 验证输入是否为数字
if [[ ! $KAFKA_PORT =~ ^[0-9]+$ ]]; then
    echo "错误: 请输入有效的端口号。"
    exit 1
fi

cat >$KAFKA_CONFIG_FILE <<EOF
port=${KAFKA_PORT}
listeners=PLAINTEXT://${LOCAL_IP}:${KAFKA_PORT}
auto.create.topics.enable=false
unclean.leader.election.enable=false
auto.leader.rebalance.enable=false
num.network.threads=3
num.io.threads=8
message.max.bytes=10000120
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=/data/kafka/logs
num.partitions=10
num.recovery.threads.per.data.dir=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
log.retention.hours=120
default.replication.factor=3
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
zookeeper.connect=${ZOOKEEPER_INFORMATION}
zookeeper.connection.timeout.ms=6000
group.initial.rebalance.delay.ms=0
min.insync.replicas=1
default.replication.factor=3
num.replica.fetchers=2
controlled.shutdown.enable=true
# Kafka JVM 参数
export KAFKA_OPTS="-server -Xmx8G -Xms4G -XX:+UseG1GC"
EOF
# 修改 JVM 内存配置
sed -i s/-Xmx1G/-Xmx10G/g /usr/local/kafka/bin/kafka-server-start.sh
sed -i s/-Xms1G/-Xms10G/g /usr/local/kafka/bin/kafka-server-start.sh

# 配置 Kafka 服务
KAFKA_SERVICE_FILE="/usr/lib/systemd/system/kafka.service"

echo "[Unit]
Description=Kafka 服务
After=network.target remote-fs.target zookeeper.service

[Service]
Type=forking
User=kafka
Group=kafka
ExecStart=/usr/local/kafka/bin/kafka-server-start.sh -daemon /usr/local/kafka/config/server.properties
ExecStop=/usr/local/kafka/bin/kafka-server-stop.sh
LimitNOFILE=1024000
LimitMEMLOCK=65536

[Install]
WantedBy=multi-user.target" > "${KAFKA_SERVICE_FILE}"

systemctl daemon-reload
chown kafka. /usr/local/kafka/ -R
chown kafka. /data/kafka/ -R
systemctl enable kafka
systemctl start kafka
systemctl status kafka

#检查kafka是否启动成功
sleep 5  # 等待5秒，确保Logstash有足够的时间启动
if systemctl is-active --quiet kafka; then
    echo "kafka启动成功"
    rm -rf "$0" >> /dev/null  # 如果启动成功则删除脚本本身
else
    echo "kafka启动失败"
fi

