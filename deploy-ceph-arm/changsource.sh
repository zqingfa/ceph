#!/bin/bash

#install ceph 
wget -q -O- 'https://mirrors.aliyun.com/ceph/keys/release.asc' | sudo apt-key add -
echo 'deb https://mirrors.aliyun.com/ceph/debian-jewel/ xenial main' > /etc/apt/sources.list.d/ceph.list