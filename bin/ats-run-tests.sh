#! /bin/bash

# constants (FIXME: common.sh)
TS=$(date +"%Y%m%dT%H%M")
NGFW_CONTAINER_BASE=ats-ngfw
CLIENT_CONTAINER_BASE=ats-client
JUNIT_CONTAINER_VOLUME=/junit
ALLURE_IMAGE=untangleinc/ngfw-ats:allure
ALLURE_CONTAINER_VOLUME=/allure

INHERITED_TESTS="not BaseTests"

# FIXME: this list should eventually be empty
# - network: test_020_port_forward_80: takes *forever*
# - network: test_07*_ftp_modes: same
# - vb: test_009_bdamserverIsRunning: "Trying to download the updates from http://bd.untangle.com/av64bit [...] ERROR: [...] Connection timeout (FFFFF7C4)
# - vb & phish: test_009_clamdIsRunning: takes *forever*
BAD_TESTS="not test_020_port_forward_80 and not _ftp_modes_ and not test_009_bdamserverIsRunning and not test_009_clamdIsRunning"

## main

# CLI parameters
if [ $# -lt 1 ] ; then
  echo "Usage: $0 <image> [extra pytest args]"
  exit 1
fi

IMAGE=$1
shift

# extract version
VERSION=$(echo ${IMAGE} | perl -pe 's/.*?:([\d.]+)-?.*/$1/')
[ -n "$VERSION" ] || VERSION=0
VERSION_TS=$(echo $IMAGE | sed -e 's/.*:// ; s/\./-/g')
NGFW_CONTAINER=${NGFW_CONTAINER_BASE}-$VERSION_TS
CLIENT_CONTAINER=${CLIENT_CONTAINER_BASE}-$VERSION_TS
JUNIT_LOCAL_VOLUME=./junit-$VERSION_TS
ALLURE_LOCAL_VOLUME=./allure/${VERSION}/${TS}

# client IP
CLIENT_IP=$(podman exec $CLIENT_CONTAINER ip -4 ad show dev eth0 | awk '/inet/ { gsub(/\/.*/, "", $2) ; print $2 }')

# run ATS
podman exec -it \
            -e PYTHONUNBUFFERED=1 \
            $NGFW_CONTAINER \
            pytest-3 -v \
                     --runtests-host=${CLIENT_IP} \
		     --skip-instantiated=false \
		     -k "${BAD_TESTS} and ${INHERITED_TESTS}" \
		     --junitxml ${JUNIT_CONTAINER_VOLUME}/ats.xml \
		     $@ \
		     /usr/lib/python3/dist-packages/tests/

# run Allure
mkdir -p $ALLURE_LOCAL_VOLUME
podman run -it --rm \
           -v ${ALLURE_LOCAL_VOLUME}:${ALLURE_CONTAINER_VOLUME} \
	   -v ${JUNIT_LOCAL_VOLUME}:${JUNIT_CONTAINER_VOLUME} \
            ${ALLURE_IMAGE} \
            generate $JUNIT_CONTAINER_VOLUME -o $ALLURE_CONTAINER_VOLUME --clean

echo "Your report is in $ALLURE_LOCAL_VOLUME"
