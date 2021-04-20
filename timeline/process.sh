#!/bin/bash

# constants
REPORTS_DIR=/reports
DB_PORT=8086

# CLI args
DB_HOST=$1
DB_NAME=$2

# main
inotifywait --monitor --recursive  -e CLOSE_WRITE $REPORTS_DIR | while read dir events file ; do
  echo "Event(s) detected for '$dir/$file': $events"
  [ "$file" = "influxDbData_ngfw.txt" ] || continue
  curl -s -X POST --data-binary @$dir/$file http://${DB_HOST}:${DB_PORT}/write?db=${DB_NAME}
done
