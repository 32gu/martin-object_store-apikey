#!/bin/sh
CONFIG=${MARTIN_CONFIG:-/etc/martin/config.yaml}

LAST=$(md5sum $CONFIG)
martin --config $CONFIG & M=$!

while true; do
  sleep 5
  CURR=$(md5sum $CONFIG)
  if [ "$CURR" != "$LAST" ]; then
    echo '[martin] Config changed, reloading...'
    kill $M 2>/dev/null
    wait $M
    martin --config $CONFIG & M=$!
    LAST=$CURR
  fi
done