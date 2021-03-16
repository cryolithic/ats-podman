#! /bin/bash 

## constants
SKU_MONTH=UN-82-PRM-0010-MONTH

## main

# CLI parameters
if [ $# != 1 ] ; then
  echo "Usage: $0 <NGFW_UID>"
  exit 1
fi

NGFW_UID=$1

ts=$(date +"%m%%2F%d%%2F%Y")

echo -n "assigning license: "

curl --fail "https://license.untangle.com/api/licenseAPI.php?action=addLicense&uid=${NGFW_UID}&sku=${SKU_MONTH}&libitem=untangle-libitem-&start=${ts}&end=&notes=on-demand+ATS+${VERSION}"
