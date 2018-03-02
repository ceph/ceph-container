#!/bin/bash
set -e

function watch_mon_health {
  while true; do
    log "Checking for zombie mons"
    /check_zombie_mons.py || true
    log "Sleep 30 sec"
    sleep 30
  done
}
