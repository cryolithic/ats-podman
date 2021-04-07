#! /bin/bash

set -e

## constants
BIN_DIR=$(dirname $(readlink -f $0))

NGFW_CONTAINER_BASE=ats-ngfw
CLIENT_CONTAINER_BASE=ats-client
EXTERNAL_NET_BASE=external
INTERNAL_NET_BASE=internal

## main

# CLI parameters
if [ $# -lt 1 ] ; then
  echo "Usage: $0 <image> [<ext_net>] [<int_net>]"
  exit 1
fi

IMAGE=$1

# extract version
VERSION=$(echo ${IMAGE} | perl -pe 's/.*?:([\d.]+)-?.*/$1/')
[ -n "$VERSION" ] || VERSION=0.0.0
TS=$(echo $IMAGE | sed -e 's/.*-//')
NGFW_CONTAINER=${NGFW_CONTAINER_BASE}-${VERSION}-$TS
CLIENT_CONTAINER=${CLIENT_CONTAINER_BASE}-${VERSION}-$TS
EXTERNAL_NET=${EXTERNAL_NET_BASE}-${VERSION}-$TS
INTERNAL_NET=${INTERNAL_NET_BASE}-${VERSION}-$TS

# get UID
uid=$(podman --cgroup-manager=cgroupfs exec ${NGFW_CONTAINER} cat /usr/share/untangle/conf/uid 2> /dev/null || true)

# remove containers
echo -n "stopping containers: "
for container in $CLIENT_CONTAINER $NGFW_CONTAINER ; do
  if podman --cgroup-manager=cgroupfs inspect $container > /dev/null 2>&1 ; then
    echo -n "$container "
    podman --cgroup-manager=cgroupfs stop $container > /dev/null
  fi
done
echo

# remove networks
echo -n "stopping networks: "
for network in $INTERNAL_NET $EXTERNAL_NET ; do
  if podman --cgroup-manager=cgroupfs network inspect $network > /dev/null 2>&1 ; then
    echo -n "$network "
    podman --cgroup-manager=cgroupfs network rm -f $network > /dev/null
  fi
done
echo

# # revoke license
# ${BIN_DIR}/license-revoke.sh "$uid"
