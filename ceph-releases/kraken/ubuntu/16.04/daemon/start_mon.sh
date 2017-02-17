#!/bin/bash
set -e

function start_mon {
  if [[ ! -n "$CEPH_PUBLIC_NETWORK" && ${NETWORK_AUTO_DETECT} -eq 0 ]]; then
    log "ERROR- CEPH_PUBLIC_NETWORK must be defined as the name of the network for the OSDs"
    exit 1
  fi

  if [[ ! -n "$MON_IP" && ${NETWORK_AUTO_DETECT} -eq 0 ]]; then
    log "ERROR- MON_IP must be defined as the IP address of the monitor"
    exit 1
  fi

  if [ ${NETWORK_AUTO_DETECT} -ne 0 ]; then
    NIC_MORE_TRAFFIC=$(grep -vE "lo:|face|Inter" /proc/net/dev | sort -n -k 2 | tail -1 | awk '{ sub (":", "", $1); print $1 }')
    if command -v ip; then
      if [ ${NETWORK_AUTO_DETECT} -eq 1 ]; then
        MON_IP=$(ip -6 -o a s $NIC_MORE_TRAFFIC | awk '{ sub ("/..", "", $4); print $4 }')
        CEPH_PUBLIC_NETWORK=$(ip -6 r | grep $NIC_MORE_TRAFFIC | awk '{ print $1 }')
        if [ -z "$MON_IP" ]; then
          MON_IP=$(ip -4 -o a s $NIC_MORE_TRAFFIC | awk '{ sub ("/..", "", $4); print $4 }')
          CEPH_PUBLIC_NETWORK=$(ip r | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}' | head -1)
        fi
      elif [ ${NETWORK_AUTO_DETECT} -eq 4 ]; then
        MON_IP=$(ip -4 -o a s $NIC_MORE_TRAFFIC | awk '{ sub ("/..", "", $4); print $4 }')
        CEPH_PUBLIC_NETWORK=$(ip r | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}' | head -1)
      elif [ ${NETWORK_AUTO_DETECT} -eq 6 ]; then
        MON_IP=$(ip -6 -o a s $NIC_MORE_TRAFFIC | awk '{ sub ("/..", "", $4); print $4 }')
        CEPH_PUBLIC_NETWORK=$(ip r | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}' | head -1)
      fi
    # best effort, only works with ipv4
    # it is tough to find the ip from the nic only using /proc
    # so we just take on of the addresses available
    # which is fairely safe given that containers usually have a single nic
    else
      MON_IP=$(grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' /proc/net/fib_trie | grep -vEw "^127|255$|0$" | head -1)
      CEPH_PUBLIC_NETWORK=$(grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[0-9]\{1,2\}' /proc/net/fib_trie | grep -vE "^127|^0" | head -1)
    fi
  fi

  if [[ -z "$MON_IP" || -z "$CEPH_PUBLIC_NETWORK" ]]; then
    log "ERROR- it looks like we have not been able to discover the network settings"
    exit 1
  fi

  get_mon_config
  # If we don't have a monitor keyring, this is a new monitor
  if [ ! -e "$MON_DATA_DIR/keyring" ]; then

    create_socket_dir

    if [ ! -e /etc/ceph/${CLUSTER}.mon.keyring ]; then
      log "ERROR- /etc/ceph/${CLUSTER}.mon.keyring must exist.  You can extract it from your current monitor by running 'ceph auth get mon. -o /etc/ceph/${CLUSTER}.mon.keyring' or use a KV Store"
      exit 1
    fi

    if [ ! -e /etc/ceph/monmap-${CLUSTER} ]; then
      log "ERROR- /etc/ceph/monmap-${CLUSTER} must exist.  You can extract it from your current monitor by running 'ceph mon getmap -o /etc/ceph/monmap-<cluster>' or use a KV Store"
      exit 1
    fi

    # Testing if it's not the first monitor, if one key doesn't exist we assume none of them exist
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --create-keyring --import-keyring /etc/ceph/${CLUSTER}.client.admin.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring
    ceph-authtool /tmp/${CLUSTER}.mon.keyring --import-keyring /etc/ceph/${CLUSTER}.mon.keyring
    chown ceph. /tmp/${CLUSTER}.mon.keyring

    # Make the monitor directory
    mkdir -p "$MON_DATA_DIR"
    chown ceph. "$MON_DATA_DIR"

    # Prepare the monitor daemon's directory with the map and keyring
    ceph-mon --setuser ceph --setgroup ceph --mkfs -i ${MON_NAME} --monmap /etc/ceph/monmap-${CLUSTER} --keyring /tmp/${CLUSTER}.mon.keyring --mon-data "$MON_DATA_DIR"

    # Clean up the temporary key
    rm /tmp/${CLUSTER}.mon.keyring
  else
    ceph-mon --setuser ceph --setgroup ceph -i ${MON_NAME} --inject-monmap /etc/ceph/monmap-${CLUSTER} --keyring /tmp/${CLUSTER}.mon.keyring --mon-data "$MON_DATA_DIR"
    # Ignore when we timeout in most cases that means the cluster has no qorum or
    # no mons are up and running
    timeout 7 ceph mon add ${MON_NAME} "${MON_IP}:6789" || true
  fi

  log "SUCCESS"

  # start MON
  exec /usr/bin/ceph-mon ${CEPH_OPTS} -d -i ${MON_NAME} --public-addr "${MON_IP}:6789" --setuser ceph --setgroup ceph --mon-data "$MON_DATA_DIR"
}
