#!/bin/bash

set -e

## functions
usage() {
  echo "Usage: $0 [-e extra_apt_dev_distribution] <distribution> <image>"
  echo "  example: $0 current ngfw:current-some-name"
  echo "  example: $0 -e NGFW-12345 current-release163 ngfw:16.3-plus-PR-12345"
}

## main

# CLI parameters
while getopts "e:" opt ; do
  case "$opt" in
    e) EXTRA_DEV_DISTRIBUTION=$OPTARG ;;
    h) usage ;;
    \?) usage ;;
  esac
done

shift $(($OPTIND - 1))
if [[ $# != 2 ]] ; then
  usage
fi

DISTRIBUTION=$1
IMAGE=$2

# FIXME: CLI switch for pull vs. build
#podman --cgroup-manager=cgroupfs build --rm -f Dockerfile.ats-client-buster -t untangleinc/ngfw-ats:client-buster .
podman --cgroup-manager=cgroupfs pull untangleinc/ngfw-ats:client-buster

# FIXME: more CLI args (mirror, no-cache, etc)
podman --cgroup-manager=cgroupfs pull untangleinc/ngfw-ats:uvm-base-${DISTRIBUTION} || \
podman --cgroup-manager=cgroupfs build --no-cache --rm -f Dockerfile.ats-uvm-base --build-arg MIRROR=package-server.untangle.int/public --build-arg DISTRIBUTION=$DISTRIBUTION -t untangleinc/ngfw-ats:uvm-base-${DISTRIBUTION} .

# FIXME: more CLI args (mirror, no-cache, etc)
if [[ -z "$EXTRA_DEV_DISTRIBUTION" ]] || echo $EXTRA_DEV_DISTRIBUTION | grep -P '^(master|release-[\d.]+)$' ; then
  mirror=package-server.untangle.int/public
  distribution=$DISTRIBUTION
else
  mirror=package-server.untangle.int/dev
  distribution=$EXTRA_DEV_DISTRIBUTION

fi

podman --cgroup-manager=cgroupfs build --no-cache --rm -f Dockerfile.ats-uvm --build-arg MIRROR=$mirror --build-arg DISTRIBUTION=$DISTRIBUTION --build-arg EXTRA_DEV_DISTRIBUTION=$distribution -t $IMAGE .
