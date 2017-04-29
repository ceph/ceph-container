#!/bin/bash
set -e

function osd_directory {
  if [[ ! -d /var/lib/ceph/osd ]]; then
    log "ERROR- could not find the osd directory, did you bind mount the OSD data directory?"
    log "ERROR- use -v <host_osd_data_dir>:/var/lib/ceph/osd"
    exit 1
  fi

  if [ -z "${HOSTNAME}" ]; then
    log "HOSTNAME not set; This will prevent to add an OSD into the CRUSH map"
    exit 1
  fi

  # check if anything is present, if not, create an osd and its directory
  if [[ -n "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
    log "Creating osd with ceph --cluster ${CLUSTER} osd create"
    OSD_ID=$(ceph --cluster "${CLUSTER}" osd create)
    if is_integer "$OSD_ID"; then
      log "OSD created with ID: ${OSD_ID}"
    else
      log "OSD creation failed: ${OSD_ID}"
      exit 1
    fi

    OSD_PATH=$(get_osd_path "$OSD_ID")

    # create the folder and own it
    mkdir -p "$OSD_PATH"
    chown --verbose ceph. "$OSD_PATH"
    log "created folder $OSD_PATH"
  fi

  # create the directory and an empty Procfile
  mkdir -p /etc/forego/"${CLUSTER}"
  echo "" > /etc/forego/"${CLUSTER}"/Procfile

  for OSD_ID in $(find /var/lib/ceph/osd -maxdepth 1 -name "${CLUSTER}*" | sed 's/.*-//'); do
    OSD_PATH=$(get_osd_path "$OSD_ID")
    OSD_KEYRING="$OSD_PATH/keyring"

    if [ -n "${JOURNAL_DIR}" ]; then
       OSD_J="${JOURNAL_DIR}/journal.${OSD_ID}"
       chown --verbose -R ceph. "${JOURNAL_DIR}"
    else
       if [ -n "${JOURNAL}" ]; then
          OSD_J=${JOURNAL}
          chown -R ceph. "$(dirname "${JOURNAL_DIR}")"
       else
          OSD_J=${OSD_PATH}/journal
       fi
    fi
    # check to see if our osd has been initialized
    if [ ! -e "${OSD_PATH}"/keyring ]; then
      chown --verbose ceph. "$OSD_PATH"
      # create osd key and file structure
      ceph-osd "${CLI_OPTS[@]}" -i "$OSD_ID" --mkfs --mkkey --mkjournal --osd-journal "${OSD_J}" --setuser ceph --setgroup ceph
      if [ ! -e "$OSD_BOOTSTRAP_KEYRING"  ]; then
        log "ERROR- $OSD_BOOTSTRAP_KEYRING must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-osd -o $OSD_BOOTSTRAP_KEYRING '"
        exit 1
      fi
      ceph_health client.bootstrap-osd "$OSD_BOOTSTRAP_KEYRING"
      # add the osd key
      ceph "${CLI_OPTS[@]}" --name client.bootstrap-osd --keyring "$OSD_BOOTSTRAP_KEYRING" auth add osd."${OSD_ID}" -i "${OSD_KEYRING}" osd 'allow *' mon 'allow profile osd'  || log "$1"
      log "done adding key"
      chown --verbose ceph. "${OSD_KEYRING}"
      chmod 0600 "${OSD_KEYRING}"
      # add the osd to the crush map
      OSD_WEIGHT=$(df -P -k "$OSD_PATH" | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
      ceph "${CLI_OPTS[@]}" --name=osd."${OSD_ID}" --keyring="${OSD_KEYRING}" osd crush create-or-move -- "${OSD_ID}" "${OSD_WEIGHT}" "${CRUSH_LOCATION}"
    fi
    echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd ${CLI_OPTS[*]} -f -i ${OSD_ID} --osd-journal ${OSD_J} -k $OSD_KEYRING" | tee -a /etc/forego/"${CLUSTER}"/Procfile
  done
  log "SUCCESS"
  start_forego
}
