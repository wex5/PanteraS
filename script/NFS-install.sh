#!/bin/bash
# --------------------------------------------------------------------------------------
# check your user id
# --------------------------------------------------------------------------------------
# this script need root user access on target node. if you have root user id, please
# execute with 'sudo' command.

if [ $UID -ne 0 ]; then
  echo "warning: this script was designed for root user."
  exit 1
fi
yum update -y
yum upgrade -y

sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
setenforce 0
systemctl stop firewalld.service
systemctl disable firewalld.service

yum install -y nfs-utils

echo '=================Network Configuration==============='
echo 'Enter a private network network like: 192.168.1.0/24'
echo '====================================================='
read IP
[ ! -d "/store" ] && mkdir /store && touch /store/check_sum
echo "/store ${IP}(rw,sync,no_root_squash)" > /etc/exports

systemctl enable rpcbind.service
systemctl enable nfs-server.service

systemctl start rpcbind.service
systemctl start nfs-server.service

dir_ip=`exportfs`

if [ $? -eq 0 ] && [ ${#dir_ip} -gt 0 ]; then
	echo "Installed successfully. Export dir: $dir_ip"
else
	echo "Error: Failed to install NFS server,please check"
fi
