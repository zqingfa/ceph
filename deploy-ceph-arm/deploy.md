长城飞腾(ARM)服务器k8s解决方案测试环境部署文档
------------------------------------------

<!-- TOC -->

- [测试环境](#测试环境)
    - [硬件](#硬件)
        - [CPU](#cpu)
        - [内存](#内存)
        - [硬盘设备](#硬盘设备)
        - [网卡设备](#网卡设备)
    - [软件](#软件)
- [部署方案](#部署方案)
- [部署ceph](#部署ceph)
    - [安装ceph](#安装ceph)
    - [部署第一个mon节点](#部署第一个mon节点)
    - [复制ceph配置文件](#复制ceph配置文件)
    - [添加osd节点](#添加osd节点)
    - [重建默认pool](#重建默认pool)
    - [启动systemd-udevd服务](#启动systemd-udevd服务)
    - [测试ceph rbd](#测试ceph-rbd)
- [从源码编译并部署frakti和greatwalld](#从源码编译并部署frakti和greatwalld)
    - [编译 frakti & cephrbd](#编译-frakti--cephrbd)
    - [编译greatwalld](#编译greatwalld)
    - [部署计算节点](#部署计算节点)
- [FAQ](#faq)
    - [ceph集群的osd都掉线](#ceph集群的osd都掉线)
    - [无法map ceph块设备](#无法map-ceph块设备)
    - [无法访问k8s](#无法访问k8s)

<!-- /TOC -->

# 测试环境

## 硬件

飞腾ARM服务器

三节点：k8s-master, k8s-node1, k8s-k8s-node1, k8s-k8s-node2, k8s-node4

### CPU

```
$ cat /proc/cpuinfo  | grep processor | wc -l
16

$ cat /proc/cpuinfo | head -n9
processor	: 0
model name	: phytium FT1500a
bogomips	: 3594.24
flags		: fp asimd evtstrm aes pmull sha1 sha2 crc32
CPU implementer	: 0x70
CPU architecture: 8
CPU variant	: 0x1
CPU part	: 0x660
CPU revision	: 1
```

### 内存
```
$ cat /proc/meminfo  | grep MemTotal
MemTotal:       65952304 kB
```

### 硬盘设备

> sdb暂无使用，ceph的osd节点使用sdb
```
root@k8s-master:~# lsblk | grep sdb

root@k8s-node1:~# lsblk | grep sdb

root@k8s-node2:~# lsblk | grep sdb
```

### 网卡设备
```
k8s-master: eth1 172.16.16.10
k8s-node1: eth1 172.16.16.8
k8s-node2: eth1 172.16.16.9
k8s-node3: eth1 172.16.16.11
k8s-node4: eth1 172.16.16.12
```


## 软件

- OS: Kylin 4.0.2
- Kubernetes v1.11
- Ceph 10.2.11 (Jewel)

```
//OS
$ lsb_release -a
No LSB modules are available.
Distributor ID:	Kylin
Description:	Kylin 4.0.2
Release:	4.0.2
Codename:	juniper
```


# 部署方案

1个mon节点，4个osd节点，3副本

- k8s-master: k8s master节点，将作为ceph的mon和osd节点
- k8s-node1: k8s 计算节点，将作为ceph的osd节点
- k8s-node2: k8s 计算节点，将作为ceph的osd节点
- k8s-node3: k8s 计算节点，将作为ceph的osd节点
- k8s-node4: k8s 计算节点，将作为ceph的osd节点

> osd: object storage daemon(对象存储守护进程), 提供块设备

# 部署ceph 

## 安装ceph

```
// 如需翻墙
$ export http_proxy=http://x.x.x.x:8118
$ export https_proxy=http://x.x.x.x:8118

// 导入key
wget -q -O- 'https://mirrors.aliyun.com/ceph/keys/release.asc' | sudo apt-key add -

// 添加安装源
echo 'deb https://mirrors.aliyun.com/ceph/debian-jewel/ xenial main' > /etc/apt/sources.list.d/ceph.list

// 安装ceph
$ apt update && apt install ceph

// 检查安装后版本，确认是10.2.11
$ dpkg -l | egrep -i 'ceph|rbd|rados'
```

## 部署第一个mon节点

> 在k8s-master上执行

```
//生产网推荐使用双网卡:
- 千兆网卡提供Ceph的Public Network通信
- 万兆网卡提供Ceph的Cluster Network通信

//本测试环境为单网卡(用法:1_ceph_bootstrap_mon.sh <publicNetworkIp> <publicNetworkPrefix> <clusterNetworkIp> <clusterNetworkPrefix>)
$ bash 1_ceph_bootstrap_mon.sh 172.16.16.10 24 172.16.16.10 24
```

## 复制ceph配置文件

将k8s-master上生成的ceph配置文件，复制到其他ceph节点

```
//在k8s-k8s-master和k8s-node1、k8s-node2、k8s-node3、k8s-node4上分别创建/etc/ceph目录
$ mkdir -p /etc/ceph

//从k8s-master上复制ceph配置文件到k8s-k8s-master、k8s-k8s-node1、k8s-k8s-node2、k8s-node4
$ scp /etc/ceph/{ceph.conf,ceph.client.admin.keyring} root@172.16.16.8:/etc/ceph
$ scp /etc/ceph/{ceph.conf,ceph.client.admin.keyring} root@172.16.16.9:/etc/ceph
$ scp /etc/ceph/{ceph.conf,ceph.client.admin.keyring} root@172.16.16.11:/etc/ceph
$ scp /etc/ceph/{ceph.conf,ceph.client.admin.keyring} root@172.16.16.12:/etc/ceph
```

## 添加osd节点

在需要做osd的节点上做如下操作：

```
在各个节点运行脚本，挂载速
bash 2_ceph_prepare_osd_disks.sh

//k8s-master, k8s-node1和k8s-node2的/dev/sdb设备已挂载，且用于vespace。没有其他空闲磁盘，但可以复用/dev/sdb。
因此可以跳过脚本2_ceph_prepare_osd_disks.sh

//k8s-master, k8s-node1, k8s-node2, k8s-node3, k8s-node4上分别执行，将创建osd相关的目录（格式：bash 3_ceph_add_osd.sh <osd数据目录>）
$ bash 3_ceph_add_osd.sh /data/sdb
$ bash 3_ceph_add_osd.sh /data/sdb
$ bash 3_ceph_add_osd.sh /data/sdb
```

## 创建pool 

默认pool为rbd，删除后新建pool，name为greatwall

```
//删除默认的rbd pool
$ ceph osd pool rm rbd rbd --yes-i-really-really-mean-it

//新建greatwall pool
$ ceph osd pool create greatwall 64 64
//检查greatwall pool
$ ceph osd pool get greatwall size && ceph osd pool get greatwall min_size
```

## 启动systemd-udevd服务

```
//所有osd节点需要运行systemd-udevd服务，否则ceph rbd设备无法map和unmap
$ systemctl start systemd-udevd

//确保systemd-udevd服务已启动
$ systemctl status systemd-udevd | grep Active -B1
   Loaded: loaded (/lib/systemd/system/systemd-udevd.service; static; vendor preset: enabled)
   Active: active (running) since 二 2018-08-07 10:42:28 CST; 6min ago
```

## 测试ceph rbd

```
//检查ceph集群状态
$ ceph status
$ ceph osd tree

$ rbd create -p greatwall --size 1G test
$ rbd ls -p greatwall
$ rbd map greatwall/test
$ rbd showmapped
$ rbd unmap greatwall/test
```
> 以上操作均正常，表示ceph集群可用


# 部署元数据服务器 MDS


## 1.分别在对应的服务器创建mds工作目录  
```bash
$ mkdir -p /var/lib/ceph/mds/ceph-node0
$ mkdir -p /var/lib/ceph/mds/ceph-node1
$ mkdir -p /var/lib/ceph/mds/ceph-node2
$ mkdir -p /var/lib/ceph/mds/ceph-node3
$ mkdir -p /var/lib/ceph/mds/ceph-node4
```

## 2.分别在服务器上注册mds的密钥。{$id} 是 MDS 的标识字母
```bash
$ ceph auth get-or-create mds.node0 mds 'allow *' osd 'allow rwx'  mon   'allow profile mds'  -o  /var/lib/ceph/mds/ceph-node0/keyring
$ ceph auth get-or-create mds.node1 mds 'allow *' osd 'allow rwx'  mon   'allow profile mds'  -o  /var/lib/ceph/mds/ceph-node1/keyring
$ ceph auth get-or-create mds.node2 mds 'allow *' osd 'allow rwx'  mon   'allow profile mds'  -o  /var/lib/ceph/mds/ceph-node2/keyring
$ ceph auth get-or-create mds.node3 mds 'allow *' osd 'allow rwx'  mon   'allow profile mds'  -o  /var/lib/ceph/mds/ceph-node3/keyring
$ ceph auth get-or-create mds.node4 mds 'allow *' osd 'allow rwx'  mon   'allow profile mds'  -o  /var/lib/ceph/mds/ceph-node4/keyring

```
## 3.启动mds进程
```bash
分别在服务器启动  
service ceph-mds@node0 start
service ceph-mds@node1 start
service ceph-mds@node2 start
service ceph-mds@node3 start
service ceph-mds@node4 start

手动启动  
ceph-mds  --cluster ceph --id node{$id} --setuser ceph --setgroup ceph
```
查看启动状态

```bash
$ ceph mds stat
e9: 1/1/1 up {0=node3=up:active}, 4 up:standby
```


# 部署cephfs
一个 Ceph 文件系统需要至少两个 RADOS 存储池，一个用于数据、一个用于元数据
```bash
ceph osd pool create cephfs_data 64
ceph osd pool create cephfs_metadata 64
ceph fs new cephfs cephfs_metadata cephfs_data
```
挂载使用
```bash
# 获取密钥存入admin.secret文件
cat /etc/ceph/ceph.client.admin.keyring | awk /key/{'print $3'} > /etc/ceph/admin.secret
# 创建挂载目录
sudo mkdir /mnt/cephfs
# 安装cephfs客户端
apt install ceph-fs-common
# 挂载使用文件系统
mount -t ceph 172.16.16.10:6789:/ /mnt/cephfs -o name=admin,secretfile=/etc/ceph/admin.secret
```

# FAQ

## ceph集群的osd都掉线


```
【现象】
root@k8s-node2:~# ceph -s
    cluster 4a4c83b0-5722-4cd8-815a-f7785deafaa2
     health HEALTH_ERR <<<<<<
            64 pgs are stuck inactive for more than 300 seconds
            64 pgs stale
            64 pgs stuck stale
            3/3 in osds are down
     monmap e1: 1 mons at {k8s-master=172.16.4.101:6789/0}
            election epoch 4, quorum 0 k8s-master
     osdmap e29: 3 osds: 0 up, 3 in
            flags sortbitwise,require_jewel_osds
      pgmap v472: 64 pgs, 1 pools, 75148 kB data, 41 objects
            60839 MB used, 4965 GB / 5024 GB avail

【原因】
ceph的osd数据目录共用了vespace的目录， vespace停掉之后，sdb被unmount

【解决】
重启ceph-osd服务，在每个node上执行下:
$ systemctl restart ceph.target

再次检查ceph集群状态，恢复
$ ceph -s
    cluster 4a4c83b0-5722-4cd8-815a-f7785deafaa2
    cluster 75b3a757-e365-43b3-854f-be6cbed0fe15
     health HEALTH_OK
     monmap e1: 1 mons at {k8s-master=172.16.16.10:6789/0}
            election epoch 3, quorum 0 k8s-master
      fsmap e2: 0/0/1 up
     osdmap e27: 5 osds: 5 up, 5 in
            flags sortbitwise,require_jewel_osds
      pgmap v78: 256 pgs, 4 pools, 16 bytes data, 3 objects
            100536 MB used, 8276 GB / 8374 GB avail
                 256 active+clean
               
```

## 无法map ceph块设备

```
【现象】
$ rbd create -p greatwall --size 1G test
$ rbd map greatwall/test
<此处挂起>

【原因】
systemd-udevd服务未启动

【解决】
$ systemctl start systemd-udevd

//再次检查，可以正常map设备
$ rbd map greatwall/test
/dev/rbd0

$ rbd showmapped
id pool  image snap device
0  greatwall test  -    /dev/rbd0

//可以正常unmap
$ rbd unmap greatwall/test
$ rbd showmapped
```

## 无法访问k8s

```
【现象】
$ kubectl get nodes
<此处挂起>
【原因】k8s-master的eth0未指定浮动ip

【解决】k8s-master上执行
$ ip add add 172.16.4.250/24 dev eth0

//再次测试
$ kubectl get nodes
NAME         STATUS    ROLES     AGE       VERSION
k8s-master   Ready     master    1d        v1.11.2
k8s-node1    Ready     <none>    1d        v1.11.2
k8s-node2    Ready     <none>    22h       v1.11.2
k8s-node3    Ready     <none>    1d        v1.11.2
k8s-node4    Ready     <none>    1d        v1.11.2

```

至此, ceph集群已部署完成，后面就可以在k8s pod中。详见[使用示例](usage.md)
