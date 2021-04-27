#!/bin/bash

set -e

# constants
REPORTS_DIR=/reports
DB_PORT=8086
PROPERTIES_FILE=environment.properties
INFLUX_FILE=influxDbData.txt
INFLUX_NGFW_FILE=influxDbData_ngfw.txt

# CLI args
DB_HOST=$1
DB_NAME=$2

# main
inotifywait --monitor --recursive  -e CLOSE_WRITE $REPORTS_DIR | while read dir events file ; do
  [ "$file" = $INFLUX_FILE ] || continue
  in_file=$dir/$file
  echo "Event(s) detected for '$in_file': $events"

  # dir looks like /reports/by-version/16.4.0/20210426T0542/exports
  report_dir=$(dirname $dir)
  ts_iso=$(basename $report_dir)
  version=$(basename $(dirname $report_dir))
  
  out_file=$dir/$INFLUX_NGFW_FILE

  if [ ! -f "$out_file" ] ; then # include our tags in influxdb data
    source <(perl -pe 's/=/="/ ; s/$/"/' $report_dir/$PROPERTIES_FILE) # don't choke on single semi-colons
    perl -pe 's/ /,public_version='${public_version}',distributions='"${distributions}"' /' $in_file > $out_file
  fi

  ts_epoch=$(awk '{gsub(/000000$/, "", $3) ; print $3 ; exit}' $out_file)
  link_name=$REPORTS_DIR/by-time/$ts_epoch
  if [ ! -L $link_name ] ; then
    # symlink into by_time/ to allow http linking from grafana to allure
    ln -s ../by-version/$version/$ts_iso $link_name
  fi

  curl -s -X POST --data-binary @$out_file http://${DB_HOST}:${DB_PORT}/write?db=$DB_NAME
done
