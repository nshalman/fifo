#!/usr/bin/env bash
BASE_PATH="http://release.project-fifo.net"
RELEASE="pre-release/0.1.0"
REDIS_DOMAIN="fifo"
COOKIE="fifo"
DATASET="d6e2d9b2-a61c-11e1-b48e-13b3863ee438"

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
	IP1=$IP2
	IP2=$IP3
	IP3=$IP4
	IP4=$IP5
	IP5=""
    fi
    
    if echo $IP | egrep '[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}'
    then
	echo $IP
    else
	echo "Invalid IP address: $IP."
	read_ip
    fi
}

subs() {
    FILE=$1
    sed -e "s;_OWN_IP_;$OWN_IP;" -i $FILE
    sed -e "s;_FIFOCOOKIE_;$COOKIE;" -i $FILE
    sed -e "s;_REDIS_URL_;redis://$REDIS_IP;" -i $FILE
    sed -e "s;_REDIS_DOMAIN_;$REDIS_DOMAIN;" -i $FILE
}

install_chunter() {
    if [ `zonename` != "global" ]
    then
	echo "chunter can only be installed in the global zone!"
	exit 1
    fi
    mkdir -p /opt/fifo
    cd /opt/fifo
    curl -O $BASE_PATH/$RELEASE/$COMPONENT.tar.bz2
    tar jxvf $COMPONENT.tar.bz2
    subs $COMPONENT/releases/*/vm.args
    subs $COMPONENT/releases/*/sys.config
}


install_service() {
    if [ `zonename` == "global" ]
    then
	echo "$COMPONENT can not be installed in the global zone!"
	#	exit 1
    fi
    mkdir -p /fifo
    cd /fifo
    curl -O $BASE_PATH/$RELEASE/$COMPONENT.tar.bz2
    tar jxvf $COMPONENT.tar.bz2
    subs $COMPONENT/releases/*/vm.args
    subs $COMPONENT/releases/*/sys.config
}

install_redis() {
    if [ `zonename` == "global" ]
    then
	echo "$COMPONENT can not be installed in the global zone!"
	#	exit 1
    fi
    echo pkgin install redis
}

install_zone() {
    dsadm update
    dsadm import $DATASET
    vmadm create <<EOF
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
    cp $0 /zones/fifo/root/root
    "waiting for zone."
    sleep 30 
    zlogin fifo $0 redis $ZONE_IP
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
