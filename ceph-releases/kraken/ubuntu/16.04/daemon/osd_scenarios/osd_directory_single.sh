#!/bin/bash
set -e

function osd_directory_single {
  if [[ ! -d /var/lib/ceph/osd ]]; then
    log "ERROR- could not find the osd directory, did you bind mount the OSD data directory?"
    log "ERROR- use -v <host_osd_data_dir>:/var/lib/ceph/osd"
    exit 1
  fi

  # make sure ceph owns the directory
  chown -R ceph. /var/lib/ceph/osd

  # pick one osd and make sure no lock is held
  for OSD_ID in $(ls /var/lib/ceph/osd |  awk 'BEGIN { FS = "-" } ; { print $2 }'); do
    if [[ -n "$(find /var/lib/ceph/osd/${CLUSTER}-${OSD_ID} -prune -empty)" ]]; then
      log "Looks like OSD: ${OSD_ID} has not been bootstrapped yet, doing nothing, moving on to the next discoverable OSD"
    else
      # check if the osd has a lock, if yes moving on, if not we run it
      # many thanks to Julien Danjou for the python piece
      if python -c "import sys, fcntl, struct; l = fcntl.fcntl(open('/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/fsid', 'a'), fcntl.F_GETLK, struct.pack('hhllhh', fcntl.F_WRLCK, 0, 0, 0, 0, 0)); l_type, l_whence, l_start, l_len, l_pid, l_sysid = struct.unpack('hhllhh', l); sys.exit(0 if l_type == fcntl.F_UNLCK else 1)"; then
        log "Looks like OSD: ${OSD_ID} is not started, starting it..."
        log "SUCCESS"
        exec ceph-osd ${CEPH_OPTS} -f -i ${OSD_ID} -k /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring
        break
      fi
    fi
  done
  log "Looks like all the OSDs are already running, doing nothing"
  log "Exiting the container"
  log "SUCCESS"
  exit 0
}
