#! /bin/bash

set -e

## constants
BIN_DIR=$(dirname $(readlink -f $0))

NGFW_CONTAINER_BASE=ats-ngfw
CLIENT_CONTAINER_BASE=ats-client
EXTERNAL_NET_BASE=external
INTERNAL_NET_BASE=internal
NGFW_NETWORK_SETTINGS=/usr/share/untangle/settings/untangle-vm/network.js
JUNIT_CONTAINER_VOLUME=/junit
MANUAL_SYSCTLS="vm.max_map_count=262144 net.ipv4.ip_local_reserved_ports=4500,5432,8009,8123,8484"
SKU_MONTH=UN-82-PRM-0010-MONTH

## main

# CLI parameters
if [ $# != 1 ] ; then
  echo "Usage: $0 <image>"
  exit 1
fi

IMAGE=$1

# extract version
VERSION=$(echo ${IMAGE} | perl -pe 's/.*?:([\d.]+)-?.*/$1/')
[ -n "$VERSION" ] || VERSION=0
VERSION_TS=$(echo $IMAGE | sed -e 's/.*:// ; s/\./-/g')
NGFW_CONTAINER=${NGFW_CONTAINER_BASE}-$VERSION_TS
CLIENT_CONTAINER=${CLIENT_CONTAINER_BASE}-$VERSION_TS
EXTERNAL_NET=${EXTERNAL_NET_BASE}-$VERSION_TS
INTERNAL_NET=${INTERNAL_NET_BASE}-$VERSION_TS
JUNIT_LOCAL_VOLUME=./junit-$VERSION_TS

# load modules
echo -n "loading required kernel modules: "
find /lib/modules/*-untangle-amd64 -iregex '.*/\(ip6t\|ipt\|ebtables\|nf\|xt_\|connt\|wg\).*\.ko' | while read f ; do
  modprobe $(basename $f | sed -e 's/.ko//')
done
echo "done"

# create the networks
echo -n "creating podman networks: "
for net in $EXTERNAL_NET $INTERNAL_NET ; do
  podman network inspect $net > /dev/null 2>&1 || podman network create $net > /dev/null
done
echo done

# run the NGFW container
echo -n "starting container ${NGFW_CONTAINER}: "
rm -fr ${JUNIT_LOCAL_VOLUME}
mkdir -p ${JUNIT_LOCAL_VOLUME}
podman run -it --rm \
	   --sysctl net.ipv4.ip_forward=1 \
	   --sysctl net.ipv4.ip_nonlocal_bind=1 \
	   --sysctl net.ipv4.ip_local_port_range="3200 8999" \
	   --sysctl net.netfilter.nf_conntrack_tcp_loose=0 \
	   --sysctl net.ipv6.conf.all.disable_ipv6=1 \
	   --cap-add CAP_NET_RAW \
	   --cap-add CAP_NET_ADMIN \
	   --device /dev/net/tun \
	   --dns=none \
	   --no-hosts \
	   --network ${EXTERNAL_NET},${INTERNAL_NET} \
	   --volume ${JUNIT_LOCAL_VOLUME}:${JUNIT_CONTAINER_VOLUME} \
	   -d \
	   --name $NGFW_CONTAINER \
	   $IMAGE > /dev/null
echo done

# set sysctls that podman can't handle itself. The values are taken
# from /usr/bin/uvm
#
#   /proc/sys/vm/max_map_count: no access at all
#   /proc/sys/net/ipv4/ip_local_reserved_ports: can't pass commas to podman's --sysctl
echo -n "setting sysctls: "
ns=$(basename $(podman inspect --format '{{.NetworkSettings.SandboxKey}}' $NGFW_CONTAINER))
for sysctl in $MANUAL_SYSCTLS ; do
  ip netns exec $ns sysctl $sysctl > /dev/null
done
echo "done"


# create and inject network config chosen by podman
network_config=$(mktemp /tmp/network-config-static-XXXXXXXX.js)
${BIN_DIR}/generate-static-network-config.py $NGFW_CONTAINER $EXTERNAL_NET > $network_config

echo -n "waiting for UVM startup before injecting network settings: "
while ! podman cp $network_config ${NGFW_CONTAINER}:${NGFW_NETWORK_SETTINGS} 2> /dev/null ; do
  echo -n "."
  sleep 1
done
rm $network_config
podman exec -it ${NGFW_CONTAINER} /etc/init.d/untangle-vm restart > /dev/null
echo " done"

# get MONTH license
echo -n "assigning license: "
uid=$(podman exec ${NGFW_CONTAINER} cat /usr/share/untangle/conf/uid)
ts=$(date +"%m%%2F%d%%2F%Y")
curl --fail "https://license.untangle.com/api/licenseAPI.php?action=addLicense&uid=${uid}&sku=${SKU_MONTH}&libitem=untangle-libitem-&start=${ts}&end=&notes=on-demand+ATS+${VERSION}"
echo " done"

# run the client
echo -n "starting container ${CLIENT_CONTAINER}: "
podman run -it --rm \
           --cap-add CAP_NET_RAW \
	   --cap-add CAP_NET_ADMIN \
	   --dns=none \
	   --no-hosts \
	   --network $INTERNAL_NET \
	   -h $CLIENT_CONTAINER \
	   -d \
	   --name $CLIENT_CONTAINER \
	   untangleinc/ngfw-ats:client-buster > /dev/null
echo "done"

# get the IP address it was assigned by the NGFW container through DHCP
echo -n "waiting for ATS client to get a DHCP lease from NGFW: "
while true ; do
  client_ip=$(podman exec $CLIENT_CONTAINER ip -4 ad show dev eth0 | awk '/inet/ { gsub(/\/.*/, "", $2) ; print $2 }')
  case $client_ip in
    192.168.2.*) break ;;
  esac
  echo -n "."
  sleep 1
done
echo " done (${client_ip})"
