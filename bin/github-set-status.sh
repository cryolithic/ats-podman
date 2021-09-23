#!/bin/bash

set -e

## constants
BIN_DIR=$(readlink -f $(dirname $0))
BASE_DIR=$(dirname $BIN_DIR)

## functions
log() {
  echo "$(basename $0): $@" >&2
}

usage() {
  echo "Usage: $(basename $0) <github_repo> <github_branch> <github_status_context> <github_status_state>"
  echo "  contexts supported: dev-packages, ATS" 
  exit 1
}

## main

# CLI parameters
if [[ $# != 4 ]] ; then
  usage
fi

GITHUB_REPO=$1
GITHUB_BRANCH=$2
GITHUB_STATUS_CONTEXT=$3
GITHUB_STATUS_STATE=$4
log "started with github_repo=$GITHUB_REPO, github_branch=$GITHUB_BRANCH, github_status_context=$GITHUB_STATUS_CONTEXT, github_status_state=$GITHUB_STATUS_STATE"

case $GITHUB_STATUS_CONTEXT in
  dev-packages)
    github_status_target_url=https://intranet.untangle.com/display/ngfw/Testing+packages+built+directly+from+GitHub+pull+requests
    github_status_desc="$(cat /dev/stdin)"
    ;;
  ATS)
    github_status_target_url="$(cat /dev/stdin)"
    github_status_desc="In progress - ATS started"
    ;;
  *) usage ;;
esac

# get GITHUB_TOKEN from .env file if it's there
[[ ! -f  ${BASE_DIR}/.env ]] || source ${BASE_DIR}/.env
export GITHUB_TOKEN

# latest commit in this PR
json=$(curl -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/search/issues?q=+head:${GITHUB_BRANCH}+repo:untangle/${GITHUB_REPO}+type:pr")
pr_number=$(echo $json | jq -r '.items[0].number')
log "  PR number: $pr_number"
log "  PR URL: https://github.com/untangle/$GITHUB_REPO/pull/$pr_number"
json=$(curl -s \
  -X GET \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/untangle/$GITHUB_REPO/pulls/$pr_number/commits?per_page=100")
last_commit=$(echo $json | jq -r '.[-1].sha')
log "  PR last commit: $last_commit"

# post status
curl -s \
  -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  -d '{"state":"'$GITHUB_STATUS_STATE'", "target_url":"'$github_status_target_url'", "context":"'$GITHUB_STATUS_CONTEXT'", "description":"'"${github_status_desc}"'"}' \
  https://api.github.com/repos/untangle/${GITHUB_REPO}/statuses/$last_commit > /dev/null
