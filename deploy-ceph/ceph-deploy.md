# 测试环境

## 硬件

三个VMWARE的虚拟机

三节点：k8s-master, k8s-node1, k8s-node2

### CPU

```bash
root@k8s-master:~# cat /proc/cpuinfo  | grep processor | wc -l
2

root@k8s-master:~# cat /proc/cpuinfo | head -n9
processor	: 0
vendor_id	: AuthenticAMD
cpu family	: 23
model		: 8
model name	: AMD Ryzen 5 2600X Six-Core Processor
stepping	: 2
microcode	: 0x8008206
cpu MHz		: 3600.005
cache size	: 512 KB

```

### 内存
```bash
root@k8s-master:~# cat /proc/meminfo  | grep MemTotal
MemTotal:       65952304 kB
```

### 硬盘设备

> sdb
```bash
root@k8s-master:~# lsblk | grep sdb
sdb      8:16   0   20G  0 disk
root@k8s-node1:~# lsblk | grep sdb
sdb      8:16   0   20G  0 disk
root@k8s-node2:~# lsblk | grep sdb
sdb      8:16   0   20G  0 disk
```

### 网卡设备
```
k8s-master: ens33 192.168.220.10
            ens38 192.168.221.10
k8s-node1: ens33 192.168.220.11
           ens38 192.168.221.11
k8s-node2: ens33 192.168.220.12
           ens38 192.168.221.12

```
### hosts文件
```bash
root@k8s-master:~# cat /etc/hosts
192.168.220.10	k8s-master
192.168.220.11	k8s-node1
192.168.220.12	k8s-node2
```

## 软件

- OS: ubuntu 16.04
- Kubernetes v1.10.3
- ceph version 13.2.1 mimic (stable)

```bash
//OS
root@k8s-master:~# lsb_release -a
Distributor ID:	Ubuntu
Description:	Ubuntu 16.04.4 LTS
Release:	16.04
Codename:	xenial

```


# 部署方案

1个mon节点，3个osd节点，3副本

- k8s-master: k8s master节点，将作为ceph的mgr、mon和osd节点
- k8s-node1: k8s master节点，将作为ceph的mon和osd节点
- k8s-node2: k8s 计算节点，将作为ceph的mon和osd节点

> osd: object storage daemon(对象存储守护进程), 提供块设备, 可以提供给pod作为flexVolume，直接挂载到hyperd虚拟机上




# 部署ceph 

## 安装ceph

```bash
// 导入key
root@k8s-master:~# wget -q -O- 'https://mirrors.aliyun.com/ceph/keys/release.asc' | sudo apt-key add -

// 添加安装源
root@k8s-master:~# sudo apt-add-repository 'deb https://download.ceph.com/debian-jewel/ xenial main'
或者
root@k8s-master:~# echo deb https://mirrors.aliyun.com/ceph/debian-mimic/ $(lsb_release -sc) main | sudo tee /etc/apt/sources.list.d/ceph.list

// 安装ceph
root@k8s-master:~# apt update && apt install ceph

```
## 安装 NTP
为了保证服务器时间同步，需要安装ntp服务。 
## 建立互信
```bash
root@k8s-master:~# ssh-keygen  
#拷贝密钥至从节点  
root@k8s-master:~# ssh-copy-id k8s-node1  
root@k8s-master:~# ssh-copy-id k8s-node2  
```
>删除所有，重新创建ceph  
ceph-deploy purge  k8s-master k8s-node1 k8s-node2  
ceph-deploy purgedata  k8s-master k8s-node1 k8s-node2  
ceph-deploy forgetkeys  
rm ceph.*  

## 创建ceph集群
```bash
#创建集群，并且添加3个监控节点
root@k8s-master:~/myclushter# ceph-deploy new k8s-master k8s-node1 k8s-node2

echo "osd pool default size = 2" >> ceph.conf  
echo "public network = 192.168.220.0/24" >> ceph.conf  
```

## 安装ceph
```bash
#安装ceph软件
root@k8s-master:~/myclushter# ceph-deploy install k8s-master k8s-node1 k8s-node2  
#初始化监控节点
root@k8s-master:~/myclushter# ceph-deploy mon create-initial 
#配置管理 
root@k8s-master:~/myclushter# ceph-deploy admin  k8s-master k8s-node1 k8s-node2  
#创建管理节点
root@k8s-master:~/myclushter# ceph-deploy mgr create k8s-master   
#添加各个主机上的磁盘
root@k8s-master:~/myclushter# ceph-deploy osd create --data /dev/sdb k8s-master
root@k8s-master:~/myclushter# ceph-deploy osd create --data /dev/sdb k8s-node1
root@k8s-master:~/myclushter# ceph-deploy osd create --data /dev/sdb k8s-node2 

root@k8s-master:~/myclushter# ceph -s
 ```
