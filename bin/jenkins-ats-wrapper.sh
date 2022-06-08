#!/bin/bash 

set -eE

## functions
usage() {
  echo "Usage: $0 [-e extra_apt_dev_distribution] <distribution> <base_version> [...]"
  echo "(extra optional args are passed directly to ats-run-tests.sh)"
  echo "  example: $0 current 16.3.0"
  echo "  example: $0 -e NGFW-12345 16.4.0"
  exit 1
}

## constants (FIXME: common.sh)
BIN_DIR=$(dirname $(readlink -f $0))
REPORTS_HOST="aws-build-04.untangle.int"
REPORTS_USER="buildbot"
REPORTS_BASEDIR="/var/www/ats"
REPORTS_VERSIONDIR="/var/www/ats/by-version"
TS=$(date +"%Y%m%dt%H%M")
TS_ISO=${TS/t/T}

## main

# CLI parameters
while getopts "e:h" opt ; do
  case "$opt" in
    e)
      EXTRA_DEV_DISTRIBUTION=$OPTARG
      VERSION_QUALIFIER="_${EXTRA_DEV_DISTRIBUTION}" ;;
    h) usage ;;
  esac
done
shift $(($OPTIND - 1))

if [[ $# -lt 2 ]] ; then
  usage
fi

DISTRIBUTION=$1
VERSION=$2
shift 2

IMAGE=ngfw:${VERSION}${VERSION_QUALIFIER}_${TS}
ALLURE_LOCAL_VOLUME=./allure/${VERSION}${VERSION_QUALIFIER}/$TS_ISO

${BIN_DIR}/ats-build-containers.sh -e "$EXTRA_DEV_DISTRIBUTION" $DISTRIBUTION $IMAGE
${BIN_DIR}/ats-start-containers.sh $IMAGE

if ${BIN_DIR}/ats-run-tests.sh $IMAGE -m "not failure_in_podman" $@ ; then
  rc=0
  status="success"
  # make sure we use the correct key when run through sudo
  scp -i ~${USER}/.ssh/id_rsa -r ${ALLURE_LOCAL_VOLUME} ${REPORTS_USER}@${REPORTS_HOST}:${REPORTS_VERSIONDIR}/${VERSION}${VERSION_QUALIFIER}/
else
  rc=1
  status="failure"
fi

if [[ "$EXTRA_DEV_DISTRIBUTION" =~ "." ]] ; then
  # we're working off a GitHub PR, close the corresponding "pending"
  # status
  git_repo=${EXTRA_DEV_DISTRIBUTION%.*}
  git_branch=${EXTRA_DEV_DISTRIBUTION#*.}
  url="http://jenkins.untangle.int/blue/organizations/jenkins/ats-podman/activity?branch=${EXTRA_DEV_DISTRIBUTION}"
  ${BIN_DIR}/github-set-status.sh $git_repo $git_branch ATS $status "$url" "Completed"
fi

${BIN_DIR}/ats-stop-containers.sh $IMAGE

exit $rc
