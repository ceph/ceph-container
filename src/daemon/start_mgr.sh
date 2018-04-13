#!/bin/bash
set -e

function start_mgr {
  get_config
  check_config

  # ensure we have the admin key
  get_admin_key

  # Check to see if our MGR has been initialized
  if [ ! -e "$MGR_KEYRING" ]; then
    check_admin_key
    # Create ceph-mgr key
    ceph "${CLI_OPTS[@]}" auth get-or-create mgr."$MGR_NAME" mon 'allow profile mgr' osd 'allow *' mds 'allow *' -o "$MGR_KEYRING"
    chown "${CHOWN_OPT[@]}" ceph. "$MGR_KEYRING"
    chmod 600 "$MGR_KEYRING"
  fi

  log "SUCCESS"
  ceph -v

  # Env. variables matching the pattern "<module>_" will be
  # found and parsed for config-key settings by
  # ceph config-key set mgr/<module>/<key> <value>
  MODULES_TO_DISABLE=$(ceph "${CLI_OPTS[@]}" mgr dump | python -c "import json, sys; print ' '.join(json.load(sys.stdin)['modules'])")

  for module in ${ENABLED_MODULES}; do
    # This module may have been enabled in the past
    # remove it from the disable list if present
    MODULES_TO_DISABLE=${MODULES_TO_DISABLE/$module/}

    options=$(env | grep ^"${module}"_ || true)
    for option in ${options}; do
      #strip module name
      option=${option/${module}_/}
      key=$(echo "$option" | cut -d= -f1)
      value=$(echo "$option" | cut -d= -f2)
      ceph "${CLI_OPTS[@]}" config-key set mgr/"$module"/"$key" "$value"
    done
    ceph "${CLI_OPTS[@]}" mgr module enable "${module}" --force
  done

  for module in $MODULES_TO_DISABLE; do
    ceph "${CLI_OPTS[@]}" mgr module disable "${module}"
  done

  log "SUCCESS"
  # start ceph-mgr
  exec /usr/bin/ceph-mgr "${DAEMON_OPTS[@]}" -i "$MGR_NAME"
}
