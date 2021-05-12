#! /bin/bash

# constants (FIXME: common.sh)
export PATH=/sbin:/usr/sbin:$PATH

NGFW_CONTAINER_BASE=ats-ngfw
CLIENT_CONTAINER_BASE=ats-client
JUNIT_CONTAINER_VOLUME=/junit
ALLURE_IMAGE=untangleinc/ngfw-ats:allure
ALLURE_CONTAINER_VOLUME=/allure

EXCLUDE_INHERITED_TESTS="not BaseTests"
EXCLUDE_BAD_TESTS="not this_test_does_not_exist"

## main

# CLI parameters
if [ $# -lt 1 ] ; then
  echo "Usage: $0 <image> [extra pytest args]"
  exit 1
fi

IMAGE=$1
shift
PYTEST_ARGS=("$@")

# extract version
VERSION=$(echo ${IMAGE} | perl -pe 's/.*?:([\d.]+)-?.*/$1/')
[ -n "$VERSION" ] || VERSION=0.0.0
TS=$(echo $IMAGE | sed -e 's/.*-//')
NGFW_CONTAINER=${NGFW_CONTAINER_BASE}-${VERSION}-$TS
CLIENT_CONTAINER=${CLIENT_CONTAINER_BASE}-${VERSION}-$TS
JUNIT_LOCAL_VOLUME=./junit/${VERSION}/${TS/t/T}
ALLURE_LOCAL_VOLUME=./allure/${VERSION}/${TS/t/T}

# client IP
CLIENT_IP=$(podman --cgroup-manager=cgroupfs exec $CLIENT_CONTAINER ip -4 ad show dev eth0 | awk '/inet/ { gsub(/\/.*/, "", $2) ; print $2 }')

# run ATS
podman --cgroup-manager=cgroupfs exec -it \
            -e PYTHONUNBUFFERED=1 \
            $NGFW_CONTAINER \
            pytest-3 -v \
                     --runtests-host=${CLIENT_IP} \
		     --skip-instantiated=false \
		     --junitxml ${JUNIT_CONTAINER_VOLUME}/ats.xml \
		     -k "${EXCLUDE_BAD_TESTS} and ${EXCLUDE_INHERITED_TESTS}" \
		     "${PYTEST_ARGS[@]}" \
		     /usr/lib/python3/dist-packages/tests/

# FIXME: ideally our metadata should be included directly in the junit
# XML, but the version of pytest in buster is too old for that
uvm_version=$(podman --cgroup-manager=cgroupfs exec $NGFW_CONTAINER dpkg-query -Wf '${Version}\n' untangle-vm)
public_version=$(echo ${uvm_version} | perl -pe 's/(\d+\.\d+\.\d+).+/$1/')
distributions=$(podman --cgroup-manager=cgroupfs exec $NGFW_CONTAINER apt-cache policy 2> /dev/null | awk '/http/ {gsub(/\/.+/, "", $3); print $3}' | uniq | xargs)
distributions="${distributions// /;};buster"
external_ip="$(curl -f https://ifconfig.co)"
if [[ $? != 0 ]] ; then
  external_ip="error on https://ifconfig.co"
fi
cat <<EOF > $JUNIT_LOCAL_VOLUME/environment.properties
uvm_version=${uvm_version}
public_version=${public_version}
distributions=${distributions}
pytest_args=$(printf "'%s' " "${PYTEST_ARGS[@]}")
hostname=$(hostname -s)
external_ip=${external_ip}
ngfw_container=${NGFW_CONTAINER}
time=$(date -Iseconds)
client_container=${CLIENT_CONTAINER}
uid=$(podman --cgroup-manager=cgroupfs exec ${NGFW_CONTAINER} cat /usr/share/untangle/conf/uid)
podman_version=$(dpkg-query -Wf '${Version}\n' podman)
EOF

# run Allure
mkdir -p $ALLURE_LOCAL_VOLUME
podman --cgroup-manager=cgroupfs run -it --rm \
           -v ${ALLURE_LOCAL_VOLUME}:${ALLURE_CONTAINER_VOLUME} \
	   -v ${JUNIT_LOCAL_VOLUME}:${JUNIT_CONTAINER_VOLUME} \
            ${ALLURE_IMAGE} \
            generate $JUNIT_CONTAINER_VOLUME -o $ALLURE_CONTAINER_VOLUME --clean

# copy properties into destination directory
cp $JUNIT_LOCAL_VOLUME/environment.properties $ALLURE_LOCAL_VOLUME

echo "Your report is in $ALLURE_LOCAL_VOLUME"
