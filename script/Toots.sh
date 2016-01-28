#!/bin/bash
source ./Toots.conf
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

tee /etc/yum.repos.d/docker.repo <<-'EOF'
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/$releasever/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF

yum install docker-engine wget git -y
systemctl start docker
systemctl enable docker.service

while [ ! -f "/usr/local/bin/docker-compose" ] || [ ! -s "/usr/local/bin/docker-compose" ]; do
	#wget -O /usr/local/bin/docker-compose https://github.com/docker/compose/releases/download/1.5.2/docker-compose-`uname -s`-`uname -m`
  wget -O /usr/local/bin/docker-compose https://raw.githubusercontent.com/VFT/imageStore/master/docker-compose
	chmod +x /usr/local/bin/docker-compose
done

cd /var

if [ ! -d "PanteraS" ]; then
	git clone https://github.com/VFT/PanteraS.git 
  cd PanteraS
else
  cd PanteraS
  git pull
fi



if [ ! -d "restricted" ]; then
	mkdir restricted
fi

MASTER="false"
SLAVE="false"
EDGE="false"

IFS=','
IPS=($MASTERS)
for i in ${!IPS[@]}
do
        ZOOKEEPER_HOSTS=$ZOOKEEPER_HOSTS"${IPS[$i]}:2181,"
        CONSUL_HOSTS=$CONSUL_HOSTS"-join=${IPS[$i]} "
        if [ $IP = ${IPS[$i]} ]; then
                ZOOKEEPER_ID=$[$i+1]
                MASTER="true"
        fi
done
if [ $ZOOKEEPER_ID ]; then
  echo '========Install Mode========'
  echo '1. Master'
  echo '2. Master + Slave'
  echo '3. Master + Slave + Edge'
  echo '============================'
  echo 'Please enter your choice(Default:1):'
  read option
  case "$option" in
    "1"|"" ) 
      SLAVE="false"
      EDGE="false"
      ;;
    "2" ) 
      SLAVE="true"
      EDGE="false"
      ;;
    "3" )
      SLAVE="true"
      EDGE="true"
      ;;
    * ) echo 'Error: Your choice is incorrect!' && exit 1;;
  esac
else
  echo '========Install Mode========'
  echo '1. Slave'
  echo '2. Edge'
  echo '3. Slave + Edge'
  echo '============================'
  echo 'Please enter your choice(Default:1):'
  read option
   case "$option" in
    "1"|"" ) 
      SLAVE="true"
      EDGE="false"
      ;;
    "2" ) 
      SLAVE="false"
      EDGE="true"
      ;;
    "3" )
      SLAVE="true"
      EDGE="true"
      ;;
    * ) echo 'Error: Your choice is incorrect!' && exit 1;;
  esac
fi
#
if [ "$MASTER" == "true" ] && [ "$SLAVE" == "false" ]; then
 echo '============Register Master Service============='
 echo '1. Yes'
 echo '2. No'
 echo '================================================'
 echo 'Please enter your choice(Default:1):'
 read option
   case "$option" in
    "1"|"" ) 
      REGISTRATOR="true"
      ;;
    "2" ) 
      REGISTRATOR="false"
      ;;
    * ) echo 'Error: Your choice is incorrect!' && exit 1;;
  esac
fi
#
if [ "$EDGE" == "true" ] && [ ! $VIP ]; then
  echo '==========================VIP Configuration==========================='
  echo 'Enter a private valid network ip to enable or empty to disable the VIP'
  echo '======================================================================'
  read VIP
fi
#
if [ "$SLAVE" == "true" ]; then
  echo '========Slave Node Mode========'
  echo '1. Stateless'
  echo '2. Persistent'
  echo '==============================='
  echo 'Please enter your choice(Default:1):'
  read option
   case "$option" in
    "1"|"" ) 
      ATTRIBUTES="--attributes=type:normal"
      if [ -e "/var/store/check_sum" ]; then
        umount /var/store && rm -rf /var/store
      fi
      ;;
    "2" ) 
      ATTRIBUTES="--attributes=type:data"
      if [ ! -d "/var/store" ]; then
        mkdir /var/store
        if [ ! $NFS ]; then
          echo '===================NFS Configuration================='
          echo 'Enter remote nfs dir like : 192.168.1.9:/store'
          echo '====================================================='
          read NFS
        fi
        yum install -y nfs-utils
        systemctl enable rpcbind.service
        systemctl start rpcbind.service
      
        IFS=':'
        PARAMS=($NFS)
        showmount -e ${PARAMS[0]}
        [ $? -ne 0 ] && echo 'Error: Remote nfs server is invalid!' && exit 1
        mount -t nfs4 "$NFS" /var/store -o proto=tcp -o nolock
        [ $? -ne 0 ] && echo 'Error: Remote nfs dir is invalid!' && exit 1
        echo "$NFS /var/store nfs auto,noatime,nolock,bg,nfsvers=4,intr,tcp,actimeo=1800 0 0" >> /etc/fstab
      else
        echo 'Warning: dir /var/store is already exist,make sure it was mount nfs dir!'
      fi
      ;;
    * ) echo 'Error: Your choice is incorrect!' && exit 1;;
  esac
fi

ZOOKEEPER_HOSTS=${ZOOKEEPER_HOSTS/%,/}
CONSUL_HOSTS=${CONSUL_HOSTS/% /}
QUORUM=$[${#IPS[@]}/2+1]

echo '#Config Paramaters of Marathon' > restricted/host
echo "MASTER=$MASTER" >> restricted/host
echo "SLAVE=$SLAVE" >> restricted/host
echo "EDGE=$EDGE" >> restricted/host
echo "ZOOKEEPER_HOSTS=\"$ZOOKEEPER_HOSTS\"" >> restricted/host
echo "CONSUL_HOSTS=\"$CONSUL_HOSTS\"" >> restricted/host
echo "MESOS_MASTER_QUORUM=$QUORUM" >> restricted/host
echo "IP=$IP" >> restricted/host
echo "HOSTNAME=$IP" >> restricted/host
# echo "CONSUL_DOMAIN=$DOMAIN" >> restricted/host
[ $DOMAIN ] && echo "HAPROXY_ADD_DOMAIN=$DOMAIN" >> restricted/host
[ "$MASTER" == "true" ] && echo "ZOOKEEPER_ID=$ZOOKEEPER_ID" >> restricted/host
[ "$SLAVE" == "true" ] && echo "MESOS_SLAVE_PARAMS=\"$ATTRIBUTES --docker_remove_delay=1mins\"" >> restricted/host
[ $VIP ] && echo "KEEPALIVED_VIP=$VIP" >> restricted/host
[ "$ZOOKEEPER_ID" == "1" ] && echo 'CONSUL_PARAMS="-bootstrap-expect 3"' >> restricted/host
[ "$REGISTRATOR" == "true" ] && echo "START_REGISTRATOR=$REGISTRATOR" >> restricted/host
# if [ "$EDGE" == "true" ]; then
#   echo "START_DNSMASQ=true" >> restricted/host
#   grep -q "127.0.0.1" /etc/resolv.conf || sed -i '1a nameserver 127.0.0.1' /etc/resolv.conf
# fi
if [ "$SLAVE" == "true" ]; then
  if [ ! -f "/etc/resolv.conf.orig" ];then
    cp /etc/resolv.conf /etc/resolv.conf.orig 
    echo "nameserver $IP" > /etc/resolv.conf
  fi
  # grep -q "127.0.0.1" /etc/resolv.conf || sed -i '1a nameserver 127.0.0.1' /etc/resolv.conf
fi
./generate_yml.sh
docker-compose up -d