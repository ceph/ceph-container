#!/bin/bash
set -e


IPV4_REGEXP='[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'
IPV4_NETWORK_REGEXP="$IPV4_REGEXP/[0-9]\\{1,2\\}"

function flat_to_ipv6 {
  # Get a flat input like fe800000000000000042acfffe110003 and output fe80::0042:acff:fe11:0003
  # This input usually comes from the ipv6_route or if_inet6 files from /proc

  # First, split the string in set of 4 bytes with ":" as separator
  local value
  value=$(echo "$@" | sed -e 's/.\{4\}/&:/g' -e '$s/\:$//')

  # Let's remove the useless 0000 and "::"
  value=${value//0000/:};
  while echo "$value" | grep -q ":::"; do
    value=${value//::/:};
  done
  echo "$value"
}

function get_ip {
  local nic=$1
  # IPv4 is the default unless we specify it
  local ip_version=${2:-4}
  # We should avoid reporting any IPv6 "scope local" interface that would make the ceph bind() call to fail
  if is_available ip; then
    ip -"$ip_version" -o a s "$nic" | grep "scope global" | awk '{ sub ("/..", "", $4); print $4 }' || true
  else
    case "$ip_version" in
      6)
        # We don't want local scope, so let's remove field 4 if not 00
        local ip
        ip=$(flat_to_ipv6 "$(grep "$nic" /proc/net/if_inet6 | awk '$4==00 {print $1}')")
        if [ -n "$ip" ]; then
          # IPv6 IPs should be surrounded by brackets to let ceph-monmap being happy
          echo "[$ip]"
        fi
        ;;
      *)
        grep -o "$IPV4_REGEXP" /proc/net/fib_trie | grep -vEw "^127|255$|0$" | head -1
        ;;
    esac
  fi
}

function get_network {
  local nic=$1
  # IPv4 is the default unless we specify it
  local ip_version=${2:-4}

  case "$ip_version" in
    6)
      if is_available ip; then
        ip -"$ip_version" route show dev "$nic" | grep proto | awk '{ print $1 }' | grep -v default | grep -vi ^fe80 || true
      else
        # We don't want the link local routes
        local line
        line=$(grep "$nic" /proc/1/task/1/net/ipv6_route | awk '$2==40' | grep -v ^fe80 || true)
        local base
        base=$(echo "$line" | awk '{ print $1 }')
        local base
        base=$(flat_to_ipv6 "$base")
        local mask
        mask=$(echo "$line" | awk '{ print $2 }')
        echo "$base/$((16#$mask))"
      fi
      ;;
    *)
      if is_available ip; then
        ip -"$ip_version" route show dev "$nic" | grep proto | awk '{ print $1 }' | grep -v default | grep "/" || true
      else
        grep -o "$IPV4_NETWORK_REGEXP" /proc/net/fib_trie | grep -vE "^127|^0" | head -1
      fi
      ;;
  esac
}

function start_mon {
  if [[ ${NETWORK_AUTO_DETECT} -eq 0 ]]; then
      if [[ -z "$CEPH_PUBLIC_NETWORK" ]]; then
        log "ERROR- CEPH_PUBLIC_NETWORK must be defined as the name of the network for the OSDs"
        exit 1
      fi

      if [[ -z "$MON_IP" ]]; then
        log "ERROR- MON_IP must be defined as the IP address of the monitor"
        exit 1
      fi
  else
    local nic_more_traffic
    nic_more_traffic_actual=$(grep -vE "lo:|face|Inter" /proc/net/dev | sort -n -k 2 | tail -1 | awk '{ sub (":", "", $1); print $1 }')
    nic_more_traffic=${CEPH_NIC:=${nic_more_traffic_actual}}

    local ip_version=4
    if [ "${NETWORK_AUTO_DETECT}" -gt 1 ]; then
      MON_IP=$(get_ip "${nic_more_traffic}" "${NETWORK_AUTO_DETECT}")
      CEPH_PUBLIC_NETWORK=$(get_network "${nic_more_traffic}" "${NETWORK_AUTO_DETECT}")
      ip_version=${NETWORK_AUTO_DETECT}
    else # Means -eq 1
      MON_IP="$(get_ip "${nic_more_traffic}" 6)"
      CEPH_PUBLIC_NETWORK=$(get_network "${nic_more_traffic}" 6)
      ip_version=6
      if [ -z "$MON_IP" ]; then
        MON_IP=$(get_ip "${nic_more_traffic}")
        CEPH_PUBLIC_NETWORK=$(get_network "${nic_more_traffic}")
        ip_version=4
      fi
    fi
    if [[ "$(echo "$CEPH_PUBLIC_NETWORK" | wc -l)" -ne 1 ]]; then
      log "It seems that the interface ${nic_more_traffic} with most of the traffic has several subnets configured"
      log "I don't know which one to use."
      log "Please do not use NETWORK_AUTO_DETECT but specify which subnet you want to use for CEPH_PUBLIC_NETWORK"
      exit 1
    fi
  fi

  if [[ -z "$MON_IP" || -z "$CEPH_PUBLIC_NETWORK" ]]; then
    log "ERROR- it looks like we have not been able to discover the network settings"
    exit 1
  fi

  # If we don't have a monitor keyring, this is a new monitor
  if [ ! -e "$MON_DATA_DIR/keyring" ]; then
    get_mon_config $ip_version

    if [ ! -e "$MON_KEYRING" ]; then
      log "ERROR- $MON_KEYRING must exist.  You can extract it from your current monitor by running 'ceph auth get mon. -o $MON_KEYRING' or use a KV Store"
      exit 1
    fi

    if [ ! -e "$MONMAP" ]; then
      log "ERROR- $MONMAP must exist.  You can extract it from your current monitor by running 'ceph mon getmap -o $MONMAP' or use a KV Store"
      exit 1
    fi

    # Testing if it's not the first monitor, if one key doesn't exist we assume none of them exist
    for keyring in $OSD_BOOTSTRAP_KEYRING $MDS_BOOTSTRAP_KEYRING $RGW_BOOTSTRAP_KEYRING $RBD_MIRROR_BOOTSTRAP_KEYRING $ADMIN_KEYRING; do
      if [ -f "$keyring" ]; then
        ceph-authtool "$MON_KEYRING" --import-keyring "$keyring"
      fi
    done

    # Prepare the monitor daemon's directory with the map and keyring
    ceph-mon --setuser ceph --setgroup ceph --cluster "${CLUSTER}" --mkfs -i "${MON_NAME}" --inject-monmap "$MONMAP" --keyring "$MON_KEYRING" --mon-data "$MON_DATA_DIR"

    # Never re-use that monmap again, otherwise we end up with partitioned Ceph monitor
    # The initial mon **only** contains the current monitor, so this is useful for initial bootstrap
    # Always rely on what has been populated after the other monitors joined the quorum
    rm -f "$MONMAP"
  else
    log "Existing mon, trying to rejoin cluster..."
    if [[ "$KV_TYPE" != "none" ]]; then
      # This is needed for etcd or k8s deployments as new containers joining need to have a map of the cluster
      # The list of monitors will not be provided by the ceph.conf since we don't have the overall knowledge of what's already deployed
      # In this kind of environment, the monmap is the only source of truth for new monitor to attempt to join the existing quorum
      if [[ ! -f "$MONMAP" ]]; then
        get_mon_config $ip_version
      fi
      # Be sure that the mon name of the current monitor in the monmap is equal to ${MON_NAME}.
      # Names can be different in case of full qualifed hostnames
      MON_ID=$(monmaptool --print "${MONMAP}" | sed -n "s/^.*${MON_IP}:${MON_PORT}.*mon\\.//p")
      if [[ -n "$MON_ID" && "$MON_ID" != "$MON_NAME" ]]; then
        monmaptool --rm "$MON_ID" "$MONMAP" >/dev/null
        monmaptool --add "$MON_NAME" "$MON_IP" "$MONMAP" >/dev/null
      fi
      ceph-mon --setuser ceph --setgroup ceph --cluster "${CLUSTER}" -i "${MON_NAME}" --inject-monmap "$MONMAP" --keyring "$MON_KEYRING" --mon-data "$MON_DATA_DIR"
    fi
    if [[ "$CEPH_DAEMON" != demo ]]; then
      v2v1=$(ceph-conf -c /etc/ceph/"${CLUSTER}".conf 'mon host' | tr ',' '\n' | grep -c "${MON_IP}")
      # in case of v2+v1 configuration : [v2:xxxx:3300,v1:xxxx:6789]
      if [ "${v2v1}" -eq 2 ]; then
        timeout 7 ceph "${CLI_OPTS[@]}" mon add "${MON_NAME}" "${MON_IP}" || true
      # with v2 only : [v2:xxxx:3300]
      else
        timeout 7 ceph "${CLI_OPTS[@]}" mon add "${MON_NAME}" "${MON_IP}":"${MON_PORT}" || true
      fi
    fi
  fi

  # start MON
  if [[ "$CEPH_DAEMON" == demo ]]; then
    if [[ ! "${CEPH_VERSION}" =~ ^(luminous|mimic)$ ]]; then
      if ! grep -qE "mon warn on pool no redundancy = false" /etc/ceph/"${CLUSTER}".conf; then
          echo "mon warn on pool no redundancy = false" >> /etc/ceph/"${CLUSTER}".conf
      fi
    fi
    /usr/bin/ceph-mon "${DAEMON_OPTS[@]}" -i "${MON_NAME}" --mon-data "$MON_DATA_DIR" --public-addr "${MON_IP}"

    if [ -n "$NEW_USER_KEYRING" ]; then
      echo "$NEW_USER_KEYRING" | ceph "${CLI_OPTS[@]}" auth import -i -
    fi
  else
    # enable cluster/audit/mon logs on the same stream
    # Mind the extra space after 'debug'
    # DO NOT TOUCH IT, IT MUST BE PRESENT
    DAEMON_OPTS+=("--default-mon-cluster-log-to-stderr=true" "--default-log-stderr-prefix=debug ")
    if [[ ! "${CEPH_VERSION}" =~ ^(luminous|mimic)$ ]]; then
      DAEMON_OPTS+=("--default-mon-cluster-log-to-file=false")
    fi
    log "SUCCESS"
    exec /usr/bin/ceph-mon "${DAEMON_OPTS[@]}" -i "${MON_NAME}" --mon-data "$MON_DATA_DIR" --public-addr "${MON_IP}"
  fi
}
