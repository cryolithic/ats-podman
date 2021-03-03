#! /bin/bash

set -e

## constants
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
VERSION=${IMAGE/*-}
[ -n "$VERSION" ] || VERSION=0
NGFW_CONTAINER=${NGFW_CONTAINER_BASE}-$VERSION
CLIENT_CONTAINER=${CLIENT_CONTAINER_BASE}-$VERSION
EXTERNAL_NET=${EXTERNAL_NET_BASE}-$VERSION
INTERNAL_NET=${INTERNAL_NET_BASE}-$VERSION

# get UID
uid=$(podman exec ${NGFW_CONTAINER} cat /usr/share/untangle/conf/uid 2> /dev/null || true)

# remove containers
echo -n "stopping containers: "
for container in $CLIENT_CONTAINER $NGFW_CONTAINER ; do
  if podman inspect $container > /dev/null 2>&1 ; then
    podman stop $container > /dev/null
  fi
done
echo "done"

# remove networks
echo -n "stopping networks: "
for network in $INTERNAL_NET $EXTERNAL_NET ; do
  if podman network inspect $network > /dev/null 2>&1 ; then
    podman network rm $network > /dev/null
  fi
done
echo done

# revoke license
echo -n "revoking license: "
if [ -n "$uid" ] ; then
  curl --fail "https://license.untangle.com/api/licenseAPI.php?action=revokeLicense&uid=${uid}&sku=${SKU_MONTH}&libitem=untangle-libitem-"
fi
echo done
