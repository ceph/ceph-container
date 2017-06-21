#!/bin/bash
set -e

function start_restapi {
  get_config
  check_config

  # Ensure we have the admin key
  get_admin_key
  check_admin_key

  # Check to see if we need to add a [client.restapi] section; add, if necessary
  if ! grep -qE "\[client.restapi\]" /etc/ceph/"${CLUSTER}".conf; then
    cat <<ENDHERE >>/etc/ceph/"${CLUSTER}".conf

[client.restapi]
  public addr = ${RESTAPI_IP}:${RESTAPI_PORT}
  restapi base url = ${RESTAPI_BASE_URL}
  restapi log level = ${RESTAPI_LOG_LEVEL}
  log file = ${RESTAPI_LOG_FILE}
ENDHERE
  fi

  log "SUCCESS"

  # start ceph-rest-api
  exec /usr/bin/ceph-rest-api "${CLI_OPTS[@]}" -n client.admin
}
