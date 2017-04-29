#!/bin/bash
set -e

# Start the latest OSD
# In case of forego, we don't run ceph-osd, start_forego will do it later
start_osd() {
  mode=$1 #forego or empty

  OSD_ID=$(find /var/lib/ceph/osd/ -maxdepth 1 -mindepth 1 -printf '%TY-%Tm-%Td %TT %p\n' | sort -n | tail -n1 | awk -F '-' -v pattern="$CLUSTER" '$0 ~ pattern {print $4}')
  OSD_PATH=$(get_osd_path "$OSD_ID")
  OSD_KEYRING="$OSD_PATH/keyring"
  if [[ ${OSD_BLUESTORE} -eq 1 ]] && [ -e "${OSD_PATH}block" ]; then
    OSD_WEIGHT=$(awk "BEGIN { d= $(blockdev --getsize64 "${OSD_PATH}"block)/1099511627776 ; r = sprintf(\"%.2f\", d); print r }")
  else
    OSD_WEIGHT=$(df -P -k "$OSD_PATH" | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
  fi
  ceph "${CLI_OPTS[@]}" --name=osd."${OSD_ID}" --keyring="$OSD_KEYRING" osd crush create-or-move -- "${OSD_ID}" "${OSD_WEIGHT}" "${CRUSH_LOCATION}"

  # ceph-disk activiate has exec'ed /usr/bin/ceph-osd ${CLI_OPTS} -f -i ${OSD_ID}
  # wait till docker stop or ceph-osd is killed
  OSD_PID=$(ps -ef |grep ceph-osd |grep osd."${OSD_ID}" |awk '{print $2}')
  if [ -n "${OSD_PID}" ]; then
      log "OSD (PID ${OSD_PID}) is running, waiting till it exits"
      while [ -e /proc/"${OSD_PID}" ]; do sleep 1;done
  fi

  if [ "$mode" = "forego" ]; then
   echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd ${CLI_OPTS} -f -i ${OSD_ID} --setuser ceph --setgroup disk" | tee -a /etc/forego/"${CLUSTER}"/Procfile
  else
   log "SUCCESS"
   exec /usr/bin/ceph-osd "${CLI_OPTS[@]}" -f -i "${OSD_ID}" --setuser ceph --setgroup disk
  fi
}

# Starting forego
start_forego() {
   exec /usr/local/bin/forego start -f /etc/forego/"${CLUSTER}"/Procfile
}
