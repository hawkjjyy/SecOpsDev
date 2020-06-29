#!/bin/bash
# ----------------------------------- #
# | CentOS 7.7 <= OS Kubernets Install|
# | Author: WeiyiGeek                 |
# ----------------------------------- #

# 脚本出错时终止执行
set -xe
if [[ $# -lt 2 ]];then
  echo -e "\e[32mUsage: $0 Action[init|master|node] HostName\e[0m"
  exit 1
fi

# 命令行参数获取
HOSTNAME=${2:-"notset"}
if [[ "$HOSTNAME" == "notset" ]];then
  echo -e "\e[31m参数有误，请查看Usage使用...\e[0m"
  exit 1
fi
ACTION=${1:-"init"}

IPADDR=$(hostname -I | cut -f 1 -d ' ')
# kubneets 版本号
export HOSTNAME=worker-01
export K8SVERSION="1.18.4"
# kubernetes 网络与APISERVER设置
export POD_SUBNET=10.100.0.1/16
export SERVICE_SUBNET=10.99.0.0/16
export APISERVER_PORT=6443
# 替换 x.x.x.x 为 master 节点的内网IP
# export 命令只在当前 shell 会话中有效，开启新的 shell 窗口后，如果要继续安装过程，请重新执行此处的 export 命令
export MASTER_IP=${IPADDR}
# 替换 apiserver.demo 为 您想要的 dnsName
export APISERVER_NAME=k8s.weiyigeek.top
# 阿里云 docker hub 镜像
export REGISTRY_MIRROR=https://xlx9erfu.mirror.aliyuncs.com
#https://registry.cn-hangzhou.aliyuncs.com


function baseSetting(){
  # 时间校准
  ntpdate -u ntp1.aliyun.com

  # 临时关闭swap和SELinux
  swapoff -a && setenforce 0
  # 永久关闭swap和SELinux
  yes | cp /etc/fstab /etc/fstab_bak
  cat /etc/fstab_bak |grep -v swap > /etc/fstab
  sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config

  # 主机名设置
  hostnamectl set-hostname $HOSTNAME
  hostnamectl status

  # 主机名设置
  echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
  cat >> /etc/hosts <<EOF
10.10.107.191 master-01
10.10.107.192 master-02
10.10.107.193 master-03
10.10.107.194 worker-01
10.10.107.196 worker-02
EOF

  # DNS 设置
  echo -e "nameserver 223.6.6.6\nnameserver 192.168.10.254" >> /etc/resolv.conf

  # 关闭防火墙
  systemctl stop firewalld
  systemctl disable firewalld
}

function dockerInstallSetting(){
  # 卸载旧版本
  yum remove -y docker \
  docker-client \
  docker-client-latest \
  docker-common \
  docker-latest \
  docker-latest-logrotate \
  docker-logrotate \
  docker-selinux \
  docker-engine-selinux \
  docker-engine

  # 安装基础依赖
  yum install -y yum-utils lvm2 wget
  # 安装 nfs-utils 必须先安装 nfs-utils 才能挂载 nfs 网络存储
  yum install -y nfs-utils
  # 添加 docker 镜像仓库
  yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

  # 查看可用Docker版本以及安装Docker
  yum list docker-ce --showduplicates | sort -r
  read -p '请输入需要安装的Docker-ce的版本号(例如:19.03.9):' VERSION
  yum install -y docker-ce-${VERSION} docker-ce-cli-${VERSION} containerd.io

  # 安装 Docker-compose
  curl -L https://get.daocloud.io/docker/compose/releases/download/1.25.5/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose

  # 镜像源加速配置
  # curl -sSL https://get.daocloud.io/daotools/set_mirror.sh | sh -s ${REGISTRY_MIRROR}
  # curl -sSL https://kuboard.cn/install-script/set_mirror.sh | sh -s ${REGISTRY_MIRROR}

  # 如果文件夹不存在则建立/etc/docker/
  if [[ ! -d "/etc/docker/" ]];then mkdir /etc/docker/;fi
  cat > /etc/docker/daemon.json <<EOF
{"registry-mirrors": ["REPLACE"]}
EOF
sed -i "s#REPLACE#${REGISTRY_MIRROR}#g" /etc/docker/daemon.json

# 启动docker并查看安装后的版本信息
  systemctl enable docker
  systemctl start docker

  docker-compose -v
  docker info
}


function kernerSetting(){
  # 修改 /etc/sysctl.conf 进行内核参数的配置
  egrep -q "^(#)?net.ipv4.ip_forward.*" /etc/sysctl.conf && sed -ri "s|^(#)?net.ipv4.ip_forward.*|net.ipv4.ip_forward = 1|g"  /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  egrep -q "^(#)?net.bridge.bridge-nf-call-ip6tables.*" /etc/sysctl.conf && sed -ri "s|^(#)?net.bridge.bridge-nf-call-ip6tables.*|net.bridge.bridge-nf-call-ip6tables = 1|g" /etc/sysctl.conf || echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.conf 
  egrep -q "^(#)?net.bridge.bridge-nf-call-iptables.*" /etc/sysctl.conf && sed -ri "s|^(#)?net.bridge.bridge-nf-call-iptables.*|net.bridge.bridge-nf-call-iptables = 1|g" /etc/sysctl.conf || echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.conf
  egrep -q "^(#)?net.ipv6.conf.all.disable_ipv6.*" /etc/sysctl.conf && sed -ri "s|^(#)?net.ipv6.conf.all.disable_ipv6.*|net.ipv6.conf.all.disable_ipv6 = 1|g" /etc/sysctl.conf || echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
  egrep -q "^(#)?net.ipv6.conf.default.disable_ipv6.*" /etc/sysctl.conf && sed -ri "s|^(#)?net.ipv6.conf.default.disable_ipv6.*|net.ipv6.conf.default.disable_ipv6 = 1|g" /etc/sysctl.conf || echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
  egrep -q "^(#)?net.ipv6.conf.lo.disable_ipv6.*" /etc/sysctl.conf && sed -ri "s|^(#)?net.ipv6.conf.lo.disable_ipv6.*|net.ipv6.conf.lo.disable_ipv6 = 1|g" /etc/sysctl.conf || echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf
  egrep -q "^(#)?net.ipv6.conf.all.forwarding.*" /etc/sysctl.conf && sed -ri "s|^(#)?net.ipv6.conf.all.forwarding.*|net.ipv6.conf.all.forwarding = 1|g"  /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding = 1"  >> /etc/sysctl.conf

  # 使修改的内核参数立即生效
  sysctl -p
}


function k8sInstallSetting(){

  #初始化 master 节点时，如果因为中间某些步骤的配置出错，想要重新初始化 master 节点
  local flag1=$(command -v kubeadm)
  local flag2=$(hostname | grep -c "master")
  if [[ "$flag1" == "0" && "$flag2" == "1" ]];then
    kubeadm reset
  fi

  # 卸载旧版本
  yum remove -y kubelet kubeadm kubectl

  # 配置K8S的yum源
  cat <<'EOF' > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
       http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
 
  # 查看安装kubelet、kubeadm、kubectl 指定统一的kubernetes 版本号，例如 1.17.2
  yum list kubelet --showduplicates | tail -n 10
  yum install -y kubelet-${K8SVERSION} kubeadm-${K8SVERSION} kubectl-${K8SVERSION}

  if [[ $? -ne 0 ]];
      echo -e "\e[31m应用安装失败请查看具体问题，解决后执行该脚本...\e[0m"
      exit 1
  fi
  
  # 修改docker Cgroup Driver为systemd
  # # 将/usr/lib/systemd/system/docker.service文件中的这一行 ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
  # # 修改为 ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock --exec-opt native.cgroupdriver=systemd
  # 如果不修改在添加 worker 节点时可能会碰到如下错误
  # [WARNING IsDockerSystemdCheck]: detected "cgroupfs" as the Docker cgroup driver. The recommended driver is "systemd". 
  # Please follow the guide at https://kubernetes.io/docs/setup/cri/    
  sed -i "s#^ExecStart=/usr/bin/dockerd.*#ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock --exec-opt native.cgroupdriver=systemd#g" /usr/lib/systemd/system/docker.service

  # 重启 docker，并启动 kubelet
  systemctl daemon-reload
  systemctl enable kubelet
  systemctl restart docker && systemctl restart kubelet
}


function k8sMaster(){
  # 只在 master 节点执行
  # Kubernetes 容器组所在的网段，该网段安装完成后，由 kubernetes 创建，事先并不存在于您的物理网络中
  echo "${APISERVER_IP} ${APISERVER_NAME}" >> /etc/hosts
  if [ ${#POD_SUBNET} -eq 0 ] || [ ${#APISERVER_NAME} -eq 0 ]; then
    echo -e "\033[31;1m请确保您已经设置了环境变量 POD_SUBNET 和 APISERVER_NAME \033[0m"
    echo 当前POD_SUBNET=$POD_SUBNET
    echo 当前APISERVER_NAME=$APISERVER_NAME
    exit 1
  fi

  # 查看完整配置选项 https://godoc.org/k8s.io/kubernetes/cmd/kubeadm/app/apis/kubeadm/v1beta2
  rm -f ./kubeadm-config.yaml
  cat <<EOF > ./kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: v${K8SVERSION}
imageRepository: mirrorgcrio
#imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers
#imageRepository: gcr.azk8s.cn/google_containers
controlPlaneEndpoint: "${APISERVER_NAME}:${APISERVER_PORT}"
networking:
  serviceSubnet: "${SERVICE_SUBNET}"
  podSubnet: "${POD_SUBNET}"
  dnsDomain: "cluster.local"
EOF

  # kubeadm init
  # 根据您服务器网速的情况，您需要等候 3 - 10 分钟
  kubeadm init --config=kubeadm-config.yaml --upload-certs

  # 配置 kubectl
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  # 安装 calico 网络插件
  # 参考文档 https://docs.projectcalico.org/v3.13/getting-started/kubernetes/self-managed-onprem/onpremises
  echo -e "---安装calico-3.13.1---"
  rm -f calico-3.13.1.yaml
  wget https://kuboard.cn/install-script/calico/calico-3.13.1.yaml
  kubectl apply -f calico-3.13.1.yaml

  # 只在 master 节点执行
  # 执行如下命令，等待 3-10 分钟，直到所有的容器组处于 Running 状态
  watch kubectl get pod -n kube-system -o wide
  echo -e "---等待容器组构建完成---" && sleep 180
  # 查看 master 节点初始化结果
  kubectl get nodes -o wide

  echo -e "集群节点认证信息: kubeadm token create --print-join-command"
}



function k8sNodes(){
  # 只在 worker 节点执行
  read -p "请输入K8s的Master节点的IP地址:" MASTER_IP
  echo "${MASTER_IP}  ${APISERVER_NAME}" >> /etc/hosts
  echo -e "\e[32m#只在 master 节点执行以下命令\n kubeadm token create --print-join-command\n可获取kubeadm join 命令及参数在Node节点运行即可\n"
  echo -e "[注意]:该 token 的有效时间为 2 个小时，2小时内，您可以使用此 token 初始化任意数量的 worker 节点\e[0m"
}


function main(){
  if [[ "$ACTION" == "init" ]];then
    baseSetting
    kernerSetting
    if [[ "$(command -v docker | grep -c 'docker')" -ne 1 && "$(command -v docker-compose | grep -c 'docker')" -ne 1 ]]; then
      dockerInstallSetting
    fi
    k8sInstallSetting
  elif [[ "$ACTION" == "master" ]];then
    k8sMaster
  elif [[ "$ACTION" == "node" ]];then
    k8sNodes
  else
    echo -e "-----参数有误-----"
  fi
}

main