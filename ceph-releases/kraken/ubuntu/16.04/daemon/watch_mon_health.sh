#!/bin/bash
set -e

function watch_mon_health {

  while [ true ]
  do
    log "checking for zombie mons"
    /check_zombie_mons.py || true
    log "sleep 30 sec"
    sleep 30
  done
}
