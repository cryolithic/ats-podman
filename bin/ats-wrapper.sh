#!/bin/bash 

set -eE

## constants (FIXME: common.sh)
BIN_DIR=$(dirname $(readlink -f $0))
REPORTS_HOST="build-it.untangleint.net"
REPORTS_USER="buildbot"
REPORTS_BASEDIR="/var/www/ats"
REPORTS_VERSIONDIR="/var/www/ats/by-version"
TS=$(date +"%Y%m%dt%H%M")
TS_ISO=${TS/t/T}

## main

# CLI parameters
if [ $# != 2 ] ; then
  echo "Usage: $0 <distribution> <version>"
  exit 1
fi

DISTRIBUTION=$1
VERSION=$2

IMAGE=ngfw:${VERSION}-${TS}
ALLURE_LOCAL_VOLUME=./allure/${VERSION}/$TS_ISO

${BIN_DIR}/ats-build-containers.sh $DISTRIBUTION $IMAGE
${BIN_DIR}/ats-start-containers.sh $IMAGE

if ${BIN_DIR}/ats-run-tests.sh $IMAGE -m "not failure_in_podman" ; then
  rc=0
  scp -i ~${USER}/.ssh/id_rsa -r $ALLURE_LOCAL_VOLUME ${REPORTS_USER}@${REPORTS_HOST}:${REPORTS_VERSIONDIR}/${VERSION}/
  # FIXME: the linking should be done server-side
  ts_epoch=$(awk '{gsub(/000000$/, "", $3) ; print $3 ; exit}' $ALLURE_LOCAL_VOLUME/export/influxDbData_ngfw.txt)
  ssh -i ~${USER}/.ssh/id_rsa ${REPORTS_USER}@${REPORTS_HOST} ln -sf ../../by-version/${VERSION}/$TS_ISO ${REPORTS_BASEDIR}/by-time/$ts_epoch
else
  rc=1
fi

${BIN_DIR}/ats-stop-containers.sh $IMAGE

exit $rc
