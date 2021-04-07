#! /bin/bash

set -e

# CLI parameters
if [ $# != 2 ] ; then
  echo "Usage: $0 <distribution> <image>"
  exit 1
fi

DISTRIBUTION=$1
IMAGE=$2

# extract version
VERSION=$(echo ${IMAGE} | perl -pe 's/.*?:([\d.]+)-?.*/$1/')

# FIXME: CLI switch for pull vs. build
#podman --cgroup-manager=cgroupfs build --rm -f Dockerfile.ats-client-buster -t untangleinc/ngfw-ats:client-buster .
podman --cgroup-manager=cgroupfs pull untangleinc/ngfw-ats:client-buster

# FIXME: more CLI args (mirror, no-cache, etc)
podman --cgroup-manager=cgroupfs pull untangleinc/ngfw-ats:uvm-base-${DISTRIBUTION} || \
podman --cgroup-manager=cgroupfs build --no-cache --rm -f Dockerfile.ats-uvm-base --build-arg MIRROR=package-server.untangle.int --build-arg DISTRIBUTION=$DISTRIBUTION -t untangleinc/ngfw-ats:uvm-base-${DISTRIBUTION} .

# FIXME: more CLI args (mirror, no-cache, etc)
podman --cgroup-manager=cgroupfs build --no-cache --rm -f Dockerfile.ats-uvm --build-arg MIRROR=package-server.untangle.int --build-arg DISTRIBUTION=$DISTRIBUTION -t $IMAGE .
