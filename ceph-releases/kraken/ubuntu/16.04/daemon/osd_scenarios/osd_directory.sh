#!/bin/bash
set -e

function osd_directory {
  if [[ ! -d /var/lib/ceph/osd ]]; then
    log "ERROR- could not find the osd directory, did you bind mount the OSD data directory?"
    log "ERROR- use -v <host_osd_data_dir>:/var/lib/ceph/osd"
    exit 1
  fi

  # make sure ceph owns the directory
  chown ceph. /var/lib/ceph/osd

  # check if anything is present, if not, create an osd and its directory
  if [[ -n "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
    log "Creating osd with ceph --cluster ${CLUSTER} osd create"
    OSD_ID=$(ceph --cluster ${CLUSTER} osd create)
    if [ "$OSD_ID" -eq "$OSD_ID" ] 2>/dev/null; then
        log "OSD created with ID: ${OSD_ID}"
    else
      log "OSD creation failed: ${OSD_ID}"
      exit 1
    fi
    # create the folder and own it
    mkdir -p /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}
    chown ceph. /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}
    log "created folder /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}"
  fi

  # create the directory and an empty Procfile
  mkdir -p /etc/forego/${CLUSTER}
  echo "" > /etc/forego/${CLUSTER}/Procfile

  for OSD_ID in $(ls /var/lib/ceph/osd | awk 'BEGIN { FS = "-" } ; { print $2 }'); do
    if [ -n "${JOURNAL_DIR}" ]; then
       OSD_J="${JOURNAL_DIR}/journal.${OSD_ID}"
       chown -R ceph. ${JOURNAL_DIR}
    else
       if [ -n "${JOURNAL}" ]; then
          OSD_J=${JOURNAL}
          chown -R ceph. $(dirname ${JOURNAL_DIR})
       else
          OSD_J=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/journal
       fi
    fi
    # check to see if our osd has been initialized
    if [ ! -e /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring ]; then
      chown ceph. /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}
      # create osd key and file structure
      ceph-osd ${CEPH_OPTS} -i $OSD_ID --mkfs --mkkey --mkjournal --osd-journal ${OSD_J} --setuser ceph --setgroup ceph
      if [ ! -e /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring ]; then
        log "ERROR- /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring'"
        exit 1
      fi
      timeout 10 ceph ${CEPH_OPTS} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring health || exit 1
      # add the osd key
      ceph ${CEPH_OPTS} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring auth add osd.${OSD_ID} -i /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd 'allow *' mon 'allow profile osd'  || log $1
      log "done adding key"
      chown ceph. /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring
      chmod 0600 /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring
      # add the osd to the crush map
      if [ ! -n "${HOSTNAME}" ]; then
        log "HOSTNAME not set; cannot add OSD to CRUSH map"
        exit 1
      fi
      OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
      ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}
    fi
    echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd ${CEPH_OPTS} -f -i ${OSD_ID} --osd-journal ${OSD_J} -k /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring" | tee -a /etc/forego/${CLUSTER}/Procfile
  done
  log "SUCCESS"
  exec /usr/local/bin/forego start -f /etc/forego/${CLUSTER}/Procfile
}
