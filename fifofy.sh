#!/usr/bin/env bash
BASE_PATH="http://release.project-fifo.net"
RELEASE="pre-release/0.1.0"
REDIS_DOMAIN="fifo"
COOKIE="fifo"
DATASET="f9e4be48-9466-11e1-bc41-9f993f5dff36"

read_ip() {
    if [ "x${IP1}x" == "xx" ]
    then
	if [ "x${1}x" != "xx" ]
	then
	    read -p "ip($1)> " IP
	    if [ "x${IP}x" == "xx" ]
	    then
		IP=$1
	    fi
	else
	    read -p "ip> " IP
	fi
    else
	IP=$IP1
	if [ "$IP" == "-d" ]
	then
	    IP=$1
	fi
	IP1=$IP2
	IP2=$IP3
	IP3=$IP4
	IP4=$IP5
	IP5=""
    fi
    
    if echo $IP | grep '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' > /dev/null
    then
	true
    else
	echo "Invalid IP address: $IP."
	read_ip
    fi
}

subs() {
    sed -e "s;_OWN_IP_;$OWN_IP;" -i $FILE
    sed -e "s;_FIFOCOOKIE_;$COOKIE;" -i $FILE
    sed -e "s;_REDIS_URL_;redis://$REDIS_IP;" -i $FILE
    sed -e "s;_REDIS_DOMAIN_;$REDIS_DOMAIN;" -i $FILE
}

install_chunter() {
    echo "[COMPONENT: $COMPONENT] Starting installation"
    if [ `zonename` != "global" ]
    then
	echo "chunter can only be installed in the global zone!"
	exit 1
    fi
    mkdir -p /opt >> fifo.log
    cd /opt >> fifo.log
    echo "[COMPONENT: $COMPONENT] Downloading."
    curl -sO $BASE_PATH/$RELEASE/$COMPONENT.tar.bz2 >> fifo.log
    tar jxvf $COMPONENT.tar.bz2 >> fifo.log
    echo "[COMPONENT: $COMPONENT] Cleanup."
    rm $COMPONENT.tar.bz2 >> fifo.log
    echo "[COMPONENT: $COMPONENT] Configuring."
    FILE=$COMPONENT/releases/*/vm.args
    subs
    FILE=$COMPONENT/releases/*/sys.config
    subs
    echo "[COMPONENT: $COMPONENT] Adding Service."
    mkdir -p /opt/custom/smf/
    cp /opt/$COMPONENT/$COMPONENT.xml /opt/custom/smf/
    svccfg import /opt/$COMPONENT/$COMPONENT.xml >> fifo.log
    echo "[COMPONENT: $COMPONENT] Done."
}


install_service() {
    echo "[COMPONENT: $COMPONENT] Starting installation"
    if [ `zonename` == "global" ]
    then
	echo "$COMPONENT can not be installed in the global zone!"
	#	exit 1
    fi
    mkdir -p /fifo >> fifo.log 
    cd /fifo >> fifo.log
    echo "[COMPONENT: $COMPONENT] Downloading."
    [ ! -f $BASE_PATH/$RELEASE/$COMPONENT.tar.bz2 ] || curl -sO $BASE_PATH/$RELEASE/$COMPONENT.tar.bz2 >> fifo.log
    tar jxvf $COMPONENT.tar.bz2 >> fifo.log
    echo "[COMPONENT: $COMPONENT] Cleanup."
    rm $COMPONENT.tar.bz2 >> fifo.log
    echo "[COMPONENT: $COMPONENT] Configuring."
    FILE=$COMPONENT/releases/*/vm.args
    subs
    FILE=$COMPONENT/releases/*/sys.config
    subs 
    echo "[COMPONENT: $COMPONENT] Adding Service."
    svccfg import /fifo/$COMPONENT/$COMPONENT.xml >> fifo.log
    echo "[COMPONENT: $COMPONENT] Done."
}

install_redis() {
    echo "[REDIS] Installing."
    if [ `zonename` == "global" ]
    then
	echo "$COMPONENT can not be installed in the global zone!"
	#	exit 1
    fi
    /opt/local/bin/pkgin -y install redis >> fifo.log
    echo "[REDIS] Fixing SVM."
    curl -sO  $BASE_PATH/$RELEASE/redis.xml >> fifo.log
    svccfg import redis.xml >> fifo.log
    rm redis.xml >> fifo.log
    echo "[REDIS] Enabeling."
    svcadm enabeling redis >> fifo.log
    echo "[REDIS] Done."
}

install_zone() {
    echo "[ZONE] Starting Zone installation."
    echo "[ZONE] Updating datasets."
    dsadm update >> fifo.log
    echo "[ZONE] Inporting dataset."
    dsadm import $DATASET >> fifo.log
    echo "[ZONE] Creating VM."
    vmadm create >> fifo.log<<EOF
{
  "brand": "joyent",
  "quota": 40,
  "alias": "fifo",
  "zonename": "fifo",
  "nowait": true,
  "dataset_uuid": "$DATASET",
  "max_physical_memory": 2048,
  "resolvers": [
    "$ZONE_DNS"
  ],
  "nics": [
    {
      "nic_tag": "admin",
      "ip": "$ZONE_IP",
      "netmask": "$ZONE_MASK",
      "gateway": "$ZONE_GW"
    }
  ]
}
EOF
    cp $0 /zones/fifo/root/root >> fifo.log
    echo "[ZONE] Waiting..."
    while [ -f /zones/fifo/root/root/zoneinit ]
    do
	sleep 5
    done
    sleep 30
    zlogin fifo $0 redis $ZONE_IP
    echo "[ZONE] Prefetcing services."
    mkdir -p /zones/fifo/root/fifo
    cd /zones/fifo/root/fifo
    curl -sO $BASE_PATH/$RELEASE/snarl.tar.bz2 >> fifo.log
    curl -sO $BASE_PATH/$RELEASE/sniffle.tar.bz2 >> fifo.log
    curl -sO $BASE_PATH/$RELEASE/wiggle.tar.bz2 >> fifo.log
    
    zlogin fifo $0 snarl $ZONE_IP
    zlogin fifo $0 sniffle $ZONE_IP
    zlogin fifo $0 wiggle $ZONE_IP
}
read_component() {
    if [ "x${COMPONENT}x" == "xx" ] 
    then
	echo
	read -p "component> " COMPONENT
    fi
    case $COMPONENT in
	wiggle|sniffle|snarl)
	    echo "Please enter the IP for your zone."
	    read_ip
	    OWN_IP=$IP
	    REDIS_IP=$IP	    
	    install_service
	    ;;
	redis)
	    install_redis
	    ;;
	all)
	    echo "Please enter the IP for your hypervisor."
	    read_ip
	    OWN_IP=$IP
	    echo "Please enter the IP for your zone."
	    read_ip
	    ZONE_IP=$IP
	    echo "Please enter the Netmask for your zone."
	    read_ip `cat /usbkey/config | grep admin_netmask | sed -e 's/admin_netmask=//'`
	    ZONE_MASK=$IP
	    echo "Please enter the Gateway for your zone."
	    read_ip `cat /usbkey/config | grep admin_gateway | sed -e 's/admin_gateway=//'`
	    ZONE_GW=$IP
	    echo "Please enter the DNS for your zone."
	    read_ip `cat /etc/resolv.conf | grep nameserver | head -n1 | awk -e '{ print $2 }'`
	    ZONE_DNS=$IP
	    install_zone
	    REDIS_IP=$ZONE_IP
	    install_chunter 
	    ;;
	chunter)
	    echo "Please enter the IP for your zone."
	    read_ip
	    REDIS_IP=$IP
	    echo "Please enter the IP for your hypervisor."
	    read_ip
	    OWN_IP=$IP
	    install_chunter 
	    ;;
	zone)
	    echo "Please enter the IP for your zone."
	    read_ip
	    ZONE_IP=$IP
	    echo "Please enter the Netmask for your zone."
	    read_ip `cat /usbkey/config | grep admin_netmask | sed -e 's/admin_netmask=//'`
	    ZONE_MASK=$IP
	    echo "Please enter the Gateway for your zone."
	    read_ip `cat /usbkey/config | grep admin_gateway | sed -e 's/admin_gateway=//'`
	    ZONE_GW=$IP
	    echo "Please enter the DNS for your zone."
	    read_ip `cat /etc/resolv.conf | grep nameserver | head -n1 | awk -e '{ print $2 }'`
	    ZONE_DNS=$IP
	    install_zone
	    ;;
	*)
	    echo "Component '$COMPONENT' not supported."
	    echo "Please choose one of: wiggle, sniffle, snarl, redis, chunter, zone or type exit."
	    COMPONENT=""
	    IP1=""
	    IP2=""
	    read_component
	    ;;
	exit)
	    ;;
	
    esac
}

COMPONENT=$1
IP1=$2
IP2=$3
IP3=$4
IP4=$5
IP5=$6
read_component $0
