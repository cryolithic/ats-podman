#! /bin/bash

set -eE

## constants
BIN_DIR=$(dirname $(readlink -f $0))
export PATH=/sbin:/usr/sbin:$PATH

NGFW_CONTAINER_BASE=ats-ngfw
CLIENT_CONTAINER_BASE=ats-client
EXTERNAL_NET_BASE=external
INTERNAL_NET_BASE=internal
NGFW_NETWORK_SETTINGS=/usr/share/untangle/settings/untangle-vm/network.js
JUNIT_CONTAINER_VOLUME=/junit
MANUAL_SYSCTLS="vm.max_map_count=262144 net.ipv4.ip_local_reserved_ports=4500,5432,8009,8123,8484"

## main

# CLI parameters
if [ $# != 1 ] ; then
  echo "Usage: $0 <image>"
  exit 1
fi

IMAGE=$1

# cleanup on error
on_err() {
  echo
  echo
  echo "FAILURE: now cleaning up with ${BIN_DIR}/ats-stop-containers.sh"
  echo
  ${BIN_DIR}/ats-stop-containers.sh $IMAGE
  echo
  echo "Please re-run $0"
}
trap on_err ERR

# extract version
VERSION=$(echo ${IMAGE} | perl -pe 's/.*?:([\d.]+)-?.*/$1/')
[ -n "$VERSION" ] || VERSION=0.0.0
TS=$(echo $IMAGE | sed -e 's/.*-//')
NGFW_CONTAINER=${NGFW_CONTAINER_BASE}-${VERSION}-$TS
CLIENT_CONTAINER=${CLIENT_CONTAINER_BASE}-${VERSION}-$TS
EXTERNAL_NET=${EXTERNAL_NET_BASE}-${VERSION}-$TS
INTERNAL_NET=${INTERNAL_NET_BASE}-${VERSION}-$TS
JUNIT_LOCAL_VOLUME=./junit/${VERSION}/${TS/t/T}

# load modules
echo -n "loading required kernel modules: "
find /lib/modules/*-untangle-amd64 -iregex '.*/\(ip6t\|ipt\|ebtables\|nf\|xt_\|connt\|wg\).*\.ko' | while read f ; do
  modprobe $(basename $f | sed -e 's/.ko//')
done
echo "done"

# create the networks
echo -n "creating podman networks: "
for net in $EXTERNAL_NET $INTERNAL_NET ; do
  echo -n "$net "
  podman --cgroup-manager=cgroupfs network inspect $net > /dev/null 2>&1 || podman network create $net > /dev/null
done
echo

# run the NGFW container
echo -n "starting NGFW container: "
rm -fr ${JUNIT_LOCAL_VOLUME}
mkdir -p ${JUNIT_LOCAL_VOLUME}
podman --cgroup-manager=cgroupfs run -it --rm \
	   --sysctl net.ipv4.ip_forward=1 \
	   --sysctl net.ipv4.ip_nonlocal_bind=1 \
	   --sysctl net.ipv4.ip_local_port_range="3200 8999" \
	   --sysctl net.netfilter.nf_conntrack_tcp_loose=0 \
	   --sysctl net.ipv6.conf.all.disable_ipv6=1 \
	   --cap-add CAP_NET_RAW \
	   --cap-add CAP_NET_ADMIN \
	   --cap-add CAP_SYS_RESOURCE \
	   --device /dev/net/tun \
	   --dns=none \
	   --no-hosts \
	   --network ${EXTERNAL_NET},${INTERNAL_NET} \
	   --hostname ${NGFW_CONTAINER//./-} \
	   --volume ${JUNIT_LOCAL_VOLUME}:${JUNIT_CONTAINER_VOLUME} \
	   -d \
	   --name $NGFW_CONTAINER \
	   $IMAGE > /dev/null
echo ${NGFW_CONTAINER}

# set sysctls that podman can't handle itself. The values are taken
# from /usr/bin/uvm
#
#   /proc/sys/vm/max_map_count: no access at all
#   /proc/sys/net/ipv4/ip_local_reserved_ports: can't pass commas to podman's --sysctl
echo -n "setting sysctls: "
ns=$(basename $(podman --cgroup-manager=cgroupfs inspect --format '{{.NetworkSettings.SandboxKey}}' $NGFW_CONTAINER))
for sysctl in $MANUAL_SYSCTLS ; do
  ip netns exec $ns sysctl $sysctl > /dev/null
done
echo "done"


# create and inject network config chosen by podman --cgroup-manager=cgroupfs
network_config=$(mktemp /tmp/network-config-static-XXXXXXXX.js)
${BIN_DIR}/generate-static-network-config.py $NGFW_CONTAINER $EXTERNAL_NET > $network_config

echo -n "injecting UVM network settings: "
# create the directory 1st: sometimes the NGFW container starts so
# fast that the 2 manual netns calls above happen only after the UVM
# startup has tried to started, resulting in a UVM crash. In that
# scenario, the directory doesn't exist and we loop forever
podman --cgroup-manager=cgroupfs exec ${NGFW_CONTAINER} mkdir -p $(dirname ${NGFW_NETWORK_SETTINGS})
while ! podman --cgroup-manager=cgroupfs cp $network_config ${NGFW_CONTAINER}:${NGFW_NETWORK_SETTINGS} 2> /dev/null ; do
  echo -n "."
  sleep 1
done
rm $network_config
podman --cgroup-manager=cgroupfs exec ${NGFW_CONTAINER} systemctl restart untangle-vm > /dev/null
echo " done"

# # get MONTH license
# uid=$(podman --cgroup-manager=cgroupfs exec ${NGFW_CONTAINER} cat /usr/share/untangle/conf/uid)
# ${BIN_DIR}/license-assign.sh $uid

# run the client
echo -n "starting ATS client container: "
podman --cgroup-manager=cgroupfs run -it --rm \
           --cap-add CAP_NET_RAW \
	   --cap-add CAP_NET_ADMIN \
	   --dns=none \
	   --no-hosts \
	   --network $INTERNAL_NET \
	   --hostname ${CLIENT_CONTAINER//./-} \
	   -d \
	   --name $CLIENT_CONTAINER \
	   untangleinc/ngfw-ats:client-buster > /dev/null
echo ${CLIENT_CONTAINER}

# get the IP address it was assigned by the NGFW container through DHCP
echo -n "waiting for ATS client to get a DHCP lease from NGFW: "
while true ; do
  client_ip=$(podman --cgroup-manager=cgroupfs exec $CLIENT_CONTAINER ip -4 ad show dev eth0 | awk '/inet/ { gsub(/\/.*/, "", $2) ; print $2 }')
  case $client_ip in
    192.168.2.*) break ;;
  esac
  echo -n "."
  sleep 1
done
echo " ${client_ip}"

echo -n "waiting for full UVM startup: "
while ! podman --cgroup-manager=cgroupfs exec ${NGFW_CONTAINER} grep -q "untangle-vm launched" /var/log/uvm/wrapper.log 2> /dev/null ; do
  echo -n "."
  sleep 1
done
while ! podman --cgroup-manager=cgroupfs exec ${NGFW_CONTAINER} ucli instances > /dev/null 2>&1 ; do
  echo -n "."
  sleep 1
done
echo " done"
