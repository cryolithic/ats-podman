#! /bin/bash 

## constants
SKU_MONTH=UN-82-PRM-0010-MONTH

## main

# CLI parameters
if [ $# != 1 ] ; then
  echo "Usage: $0 <UID>"
  exit 1
fi

NGFW_UID=$1

echo -n "revoking license: "

if [ -n "$NGFW_UID" ] ; then
  echo -n "$NGFW_UID "
  curl --fail "https://license.untangle.com/api/licenseAPI.php?action=revokeLicense&uid=${NGFW_UID}&sku=${SKU_MONTH}&libitem=untangle-libitem-"
fi
echo
