#!/bin/bash
set -e

function osd_directory {
  if [[ ! -d /var/lib/ceph/osd ]]; then
    log "ERROR- could not find the osd directory, did you bind mount the OSD data directory?"
    log "ERROR- use -v <host_osd_data_dir>:/var/lib/ceph/osd"
    exit 1
  fi

  # check if anything is present, if not, create an osd and its directory
  if [[ -n "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
    log "Creating osd"
    UUID=$(uuidgen)
    OSD_SECRET=$(ceph-authtool --gen-print-key)
    OSD_ID=$(echo "{\"cephx_secret\": \"${OSD_SECRET}\"}" | ceph --cluster "${CLUSTER}" osd new "${UUID}" -i - -n client.bootstrap-osd -k "$OSD_BOOTSTRAP_KEYRING")
    if is_integer "$OSD_ID"; then
      log "OSD created with ID: ${OSD_ID}"
    else
      log "OSD creation failed: ${OSD_ID}"
      exit 1
    fi

    OSD_PATH=$(get_osd_path "$OSD_ID")
    if [ -n "${JOURNAL_DIR}" ]; then
       OSD_J="${JOURNAL_DIR}/journal.${OSD_ID}"
       chown "${CHOWN_OPT[@]}" -R ceph. "${JOURNAL_DIR}"
    else
       if [ -n "${JOURNAL}" ]; then
          OSD_J=${JOURNAL}
          chown "${CHOWN_OPT[@]}" -R ceph. "$(dirname "${JOURNAL_DIR}")"
       else
          OSD_J=${OSD_PATH}/journal
       fi
    fi

    # create the folder and own it
    mkdir -p "$OSD_PATH"
    chown "${CHOWN_OPT[@]}" ceph. "$OSD_PATH"
    log "created folder $OSD_PATH"
    # write the secret to the osd keyring file
    ceph-authtool --create-keyring "${OSD_PATH}"/keyring --name osd."${OSD_ID}" --add-key "${OSD_SECRET}"
    chown "${CHOWN_OPT[@]}" ceph. "${OSD_PATH}"/keyring
    # init data directory
    ceph-osd --cluster "${CLUSTER}" -i "${OSD_ID}" --mkfs --osd-uuid "${UUID}" --mkjournal --osd-journal "${OSD_J}" --setuser ceph --setgroup ceph
  fi

  # create the directory and an empty Procfile
  mkdir -p /etc/forego/"${CLUSTER}"
  echo "" > /etc/forego/"${CLUSTER}"/Procfile

  for OSD_ID in $(find /var/lib/ceph/osd -maxdepth 1 -name "${CLUSTER}*" | sed 's/.*-//'); do
    OSD_PATH=$(get_osd_path "$OSD_ID")
    OSD_KEYRING="$OSD_PATH/keyring"

    if [ -n "${JOURNAL_DIR}" ]; then
       OSD_J="${JOURNAL_DIR}/journal.${OSD_ID}"
       chown "${CHOWN_OPT[@]}" -R ceph. "${JOURNAL_DIR}"
    else
       if [ -n "${JOURNAL}" ]; then
          OSD_J=${JOURNAL}
          chown "${CHOWN_OPT[@]}" -R ceph. "$(dirname "${JOURNAL_DIR}")"
       else
          OSD_J=${OSD_PATH}/journal
       fi
    fi
    echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd ${CLI_OPTS[*]} -f -i ${OSD_ID} --osd-journal ${OSD_J} -k $OSD_KEYRING" | tee -a /etc/forego/"${CLUSTER}"/Procfile
  done
  log "SUCCESS"
  source /opt/ceph-container/bin/osd_common.sh
  start_forego
}
