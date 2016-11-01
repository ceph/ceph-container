#!/bin/bash
set -xe

: ${CLUSTER:=ceph}
: ${CEPH_CLUSTER_NETWORK:=${CEPH_PUBLIC_NETWORK}}
: ${CEPH_DAEMON:=${1}} # default daemon to first argument
: ${CEPH_GET_ADMIN_KEY:=0}
: ${HOSTNAME:=$(hostname -s)}
: ${MON_NAME:=${HOSTNAME}}
: ${NETWORK_AUTO_DETECT:=0}
: ${MDS_NAME:=mds-${HOSTNAME}}
: ${OSD_FORCE_ZAP:=0}
: ${OSD_JOURNAL_SIZE:=100}
: ${OSD_BLUESTORE:=0}
: ${OSD_DMCRYPT:=0}
: ${CRUSH_LOCATION:=root=default host=${HOSTNAME}}
: ${CEPHFS_CREATE:=0}
: ${CEPHFS_NAME:=cephfs}
: ${CEPHFS_DATA_POOL:=${CEPHFS_NAME}_data}
: ${CEPHFS_DATA_POOL_PG:=8}
: ${CEPHFS_METADATA_POOL:=${CEPHFS_NAME}_metadata}
: ${CEPHFS_METADATA_POOL_PG:=8}
: ${RGW_NAME:=${HOSTNAME}}
: ${RGW_ZONEGROUP:=}
: ${RGW_ZONE:=}
: ${RGW_CIVETWEB_PORT:=8080}
: ${RGW_REMOTE_CGI:=0}
: ${RGW_REMOTE_CGI_PORT:=9000}
: ${RGW_REMOTE_CGI_HOST:=0.0.0.0}
: ${RGW_USER:="cephnfs"}
: ${RESTAPI_IP:=0.0.0.0}
: ${RESTAPI_PORT:=5000}
: ${RESTAPI_BASE_URL:=/api/v0.1}
: ${RESTAPI_LOG_LEVEL:=warning}
: ${RESTAPI_LOG_FILE:=/var/log/ceph/ceph-restapi.log}
: ${KV_TYPE:=none} # valid options: consul, etcd or none
: ${KV_IP:=127.0.0.1}
: ${KV_PORT:=4001} # PORT 8500 for Consul
: ${GANESHA_OPTIONS:=""}
: ${GANESHA_EPOCH:=""} # For restarting

if [ ! -z "${KV_CA_CERT}" ]; then
  KV_TLS="--ca-cert=${KV_CA_CERT} --client-cert=${KV_CLIENT_CERT} --client-key=${KV_CLIENT_KEY}"
  CONFD_KV_TLS="-scheme=https -client-ca-keys=${KV_CA_CERT} -client-cert=${KV_CLIENT_CERT} -client-key=${KV_CLIENT_KEY}"
fi

CEPH_OPTS="--cluster ${CLUSTER}"
MOUNT_OPTS="-t xfs -o noatime,inode64"


####################
# COMMON FUNCTIONS #
####################

# log arguments with timestamp
function log {
  if [ -z "$*" ]; then
    return 1
  fi

  TIMESTAMP=$(date '+%F %T')
  echo "${TIMESTAMP}  $0: $*"
  return 0
}

# ceph config file exists or die
function check_config {
  if [[ ! -e /etc/ceph/${CLUSTER}.conf ]]; then
    log "ERROR- /etc/ceph/${CLUSTER}.conf must exist; get it from your existing mon"
    exit 1
  fi
}

# ceph admin key exists or die
function check_admin_key {
  if [[ ! -e /etc/ceph/${CLUSTER}.client.admin.keyring ]]; then
      log "ERROR- /etc/ceph/${CLUSTER}.client.admin.keyring must exist; get it from your existing mon"
      exit 1
  fi
}

# Given two strings, return the length of the shared prefix
function prefix_length {
  local maxlen=${#1}
  for ((i=maxlen-1;i>=0;i--)); do
    if [[ "${1:0:i}" == "${2:0:i}" ]]; then
      echo $i
      return
    fi
  done
}

# create socket directory
function create_socket_dir {
  mkdir -p /var/run/ceph
  chown ceph. /var/run/ceph
}

# Calculate proper device names, given a device and partition number
function dev_part {
  if [[ -L ${1} ]]; then
    # This device is a symlink. Work out it's actual device
    local actual_device=$(readlink -f ${1})
    local bn=$(basename $1)
    if [[ "${ACTUAL_DEVICE:0-1:1}" == [0-9] ]]; then
      local desired_partition="${actual_device}p${2}"
    else
      local desired_partition="${actual_device}${2}"
    fi
    # Now search for a symlink in the directory of $1
    # that has the correct desired partition, and the longest
    # shared prefix with the original symlink
    local symdir=$(dirname $1)
    local link=""
    local pfxlen=0
    for option in $(ls $symdir); do
    if [[ $(readlink -f $symdir/$option) == $desired_partition ]]; then
      local optprefixlen=$(prefix_length $option $bn)
      if [[ $optprefixlen > $pfxlen ]]; then
        link=$symdir/$option
        pfxlen=$optprefixlen
      fi
    fi
    done
    if [[ $pfxlen -eq 0 ]]; then
      >&2 log "Could not locate appropriate symlink for partition $2 of $1"
      exit 1
    fi
    echo "$link"
  elif [[ "${1:0-1:1}" == [0-9] ]]; then
    echo "${1}p${2}"
  else
    echo "${1}${2}"
  fi
}

function osd_trying_to_determine_scenario {
  if [ -z "${OSD_DEVICE}" ]; then
    log "Bootstrapped OSD(s) found; using OSD directory"
    osd_directory
  elif $(parted --script ${OSD_DEVICE} print | egrep -sq '^ 1.*ceph data'); then
    log "Bootstrapped OSD found; activating ${OSD_DEVICE}"
    osd_activate
  else
    log "Device detected, assuming ceph-disk scenario is desired"
    log "Preparing and activating ${OSD_DEVICE}"
    osd_disk
  fi
}


###########################
# CONFIGURATION GENERATOR #
###########################

# Load in the bootstrapping routines
# based on the data store
case "$KV_TYPE" in
   etcd|consul)
      source /config.kv.sh
      ;;
   k8s|kubernetes)
      source /config.k8s.sh
      ;;

   *)
      source /config.static.sh
      ;;
esac


##########
# CONFIG #
##########
function kv {
  # Note the 'cas' command puts a value in the KV store if it is empty
  KEY="$1"
  shift
  VALUE="$*"
  log "adding key ${KEY} with value ${VALUE} to KV store"
  kviator --kvstore=${KV_TYPE} --client=${KV_IP}:${KV_PORT} ${KV_TLS} cas ${CLUSTER_PATH}"${KEY}" "${VALUE}" || log "value is already set"
}

function populate_kv {
    CLUSTER_PATH=ceph-config/${CLUSTER}
    case "$KV_TYPE" in
       etcd|consul)
          # if ceph.defaults found in /etc/ceph/ use that
          if [[ -e "/etc/ceph/ceph.defaults" ]]; then
            DEFAULTS_PATH="/etc/ceph/ceph.defaults"
          else
          # else use defaults
            DEFAULTS_PATH="/ceph.defaults"
          fi
          # read defaults file, grab line with key<space>value without comment #
          cat "$DEFAULTS_PATH" | grep '^.* .*' | grep -v '#' | while read line; do
            kv `echo $line`
          done
          ;;
       *)
          ;;
    esac
}


#######
# MON #
#######

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

  # If we don't have a monitor keyring, this is a new monitor
  if [ ! -e /var/lib/ceph/mon/${CLUSTER}-${MON_NAME}/keyring ]; then

    get_mon_config
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
    mkdir -p /var/lib/ceph/mon/${CLUSTER}-${MON_NAME}
    chown ceph. /var/lib/ceph/mon/${CLUSTER}-${MON_NAME}

    # Prepare the monitor daemon's directory with the map and keyring
    ceph-mon --setuser ceph --setgroup ceph --mkfs -i ${MON_NAME} --monmap /etc/ceph/monmap-${CLUSTER} --keyring /tmp/${CLUSTER}.mon.keyring --mon-data /var/lib/ceph/mon/${CLUSTER}-${MON_NAME}

    # Clean up the temporary key
    rm /tmp/${CLUSTER}.mon.keyring
  fi

  log "SUCCESS"

  # start MON
  exec /usr/bin/ceph-mon ${CEPH_OPTS} -d -i ${MON_NAME} --public-addr "${MON_IP}:6789" --setuser ceph --setgroup ceph
}


################
# OSD (common) #
################

function start_osd {
  get_config
  check_config
  create_socket_dir

  if [ ${CEPH_GET_ADMIN_KEY} -eq "1" ]; then
    get_admin_key
    check_admin_key
  fi

  case "$OSD_TYPE" in
    directory)
      osd_directory
      ;;
    directory_single)
      osd_directory_single
      ;;
    disk)
      osd_disk
      ;;
    prepare)
      osd_disk_prepare
      ;;
    activate)
      osd_activate
      ;;
    devices)
      osd_disks
      ;;
    activate_journal)
      osd_activate_journal
      ;;
    *)
      osd_trying_to_determine_scenario
      ;;
  esac
}


########################
# OSD_DIRECTORY_SINGLE #
########################

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
        exec ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID} -k /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring
        break
      fi
    fi
  done

  log "Looks like all the OSDs are already running, doing nothing"
  log "Exiting the container"
  log "SUCCESS"
  exit 0
}


#################
# OSD_DIRECTORY #
#################

function osd_directory {
  if [[ ! -d /var/lib/ceph/osd ]]; then
    log "ERROR- could not find the osd directory, did you bind mount the OSD data directory?"
    log "ERROR- use -v <host_osd_data_dir>:/var/lib/ceph/osd"
    exit 1
  fi

  # make sure ceph owns the directory
  chown ceph. /var/lib/ceph/osd

  # check if anything is there, if not create an osd with directory
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

  # Create the directory and an empty Procfile
  mkdir -p /etc/forego/${CLUSTER}
  echo "" > /etc/forego/${CLUSTER}/Procfile

  for OSD_ID in $(ls /var/lib/ceph/osd |  awk 'BEGIN { FS = "-" } ; { print $2 }'); do
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

    # Check to see if our OSD has been initialized
    if [ ! -e /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring ]; then
      chown ceph. /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}
      # Create OSD key and file structure
      ceph-osd ${CEPH_OPTS} -i $OSD_ID --mkfs --mkkey --mkjournal --osd-journal ${OSD_J} --setuser ceph --setgroup ceph

      if [ ! -e /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring ]; then
        log "ERROR- /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring'"
        exit 1
      fi

      timeout 10 ceph ${CEPH_OPTS} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring health || exit 1

      # Add the OSD key
      ceph ${CEPH_OPTS} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring auth add osd.${OSD_ID} -i /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd 'allow *' mon 'allow profile osd'  || log $1
      log "done adding key"
      chown ceph. /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring
      chmod 0600 /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring

      # Add the OSD to the CRUSH map
      if [ ! -n "${HOSTNAME}" ]; then
        log "HOSTNAME not set; cannot add OSD to CRUSH map"
        exit 1
      fi
      OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
      ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}
    fi



    echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID} --osd-journal ${OSD_J} -k /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring" | tee -a /etc/forego/${CLUSTER}/Procfile

  done

  log "SUCCESS"

  exec /usr/local/bin/forego start -f /etc/forego/${CLUSTER}/Procfile
}


#########################
# OSD_CEPH_DISK_PREPARE #
#########################

function osd_disk_prepare {
  if [[ -z "${OSD_DEVICE}" ]];then
    log "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  if [ ! -e /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring ]; then
    log "ERROR- /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring'"
    exit 1
  fi

  timeout 10 ceph ${CEPH_OPTS} --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/${CLUSTER}.keyring health || exit 1

  mkdir -p /var/lib/ceph/osd
  chown ceph. /var/lib/ceph/osd

  # TODO:
  # -  add device format check (make sure only one device is passed

  # check device status first
  if ! parted --script ${OSD_DEVICE} print > /dev/null 2>&1; then
    ceph-disk -v zap ${OSD_DEVICE}
  fi

  if [[ "$(parted --script ${OSD_DEVICE} print | egrep '^ 1.*ceph data')" && ${OSD_FORCE_ZAP} -ne "1" ]]; then
    log "ERROR- It looks like ${OSD_DEVICE} is an OSD, set OSD_FORCE_ZAP=1 to use this device anyway and zap its content"
    log "You can also use the zap_device scenario on the appropriate device to zap it"
    exit 1
  elif [[ "$(parted --script ${OSD_DEVICE} print | egrep '^ 1.*ceph data')" && ${OSD_FORCE_ZAP} -eq "1" ]]; then
    log "It looks like ${OSD_DEVICE} is an OSD, however OSD_FORCE_ZAP is enabled so we are zapping the device anyway"
    ceph-disk -v zap ${OSD_DEVICE}
  fi

  if [[ ! -z "${OSD_JOURNAL}" ]]; then
    if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
      ceph-disk -v prepare ${CEPH_OPTS} --bluestore ${OSD_DEVICE} ${OSD_JOURNAL}
    elif [[ ${OSD_DMCRYPT} -eq 1 ]]; then
      get_admin_key
      check_admin_key
      # the admin key must be present on the node
      # in order to store the encrypted key in the monitor's k/v store
      ceph-disk -v prepare ${CEPH_OPTS} --dmcrypt ${OSD_DEVICE} ${OSD_JOURNAL}
    else
      ceph-disk -v prepare ${CEPH_OPTS} ${OSD_DEVICE} ${OSD_JOURNAL}
    fi
    chown ceph. ${OSD_JOURNAL}
  else
    if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
      ceph-disk -v prepare ${CEPH_OPTS} --bluestore ${OSD_DEVICE}
    elif [[ ${OSD_DMCRYPT} -eq 1 ]]; then
      get_admin_key
      check_admin_key
      # the admin key must be present on the node
      # in order to store the encrypted key in the monitor's k/v store
      ceph-disk -v prepare ${CEPH_OPTS} --dmcrypt ${OSD_DEVICE}
    else
      ceph-disk -v prepare ${CEPH_OPTS} ${OSD_DEVICE}
    fi
    chown ceph. $(dev_part ${OSD_DEVICE} 2)
  fi
}


#################
# OSD_CEPH_DISK #
#################
function osd_disk {
  osd_disk_prepare
  osd_activate
}


##########################
# OSD_CEPH_DISK_ACTIVATE #
##########################

function osd_activate {
  if [[ -z "${OSD_DEVICE}" ]];then
    log "ERROR- You must provide a device to build your OSD ie: /dev/sdb"
    exit 1
  fi

  mkdir -p /var/lib/ceph/osd
  chown ceph. /var/lib/ceph/osd
  # resolve /dev/disk/by-* names
  ACTUAL_OSD_DEVICE=$(readlink -f ${OSD_DEVICE})
  # wait till partition exists then activate it
  if [[ ! -z "${OSD_JOURNAL}" ]]; then
    timeout 10  bash -c "while [ ! -e ${OSD_DEVICE} ]; do sleep 1; done"
    chown ceph. ${OSD_JOURNAL}
    if [[ ${OSD_DMCRYPT} -eq 1 ]]; then
      ceph-disk -v --setuser ceph --setgroup --dmcrypt disk activate $(dev_part ${OSD_DEVICE} 1)
    else
      ceph-disk -v --setuser ceph --setgroup disk activate $(dev_part ${OSD_DEVICE} 1)
    fi
    OSD_ID=$(ceph-disk list | grep "$(dev_part ${ACTUAL_OSD_DEVICE} 1) ceph data" | awk -F, '{print $4}' | awk -F. '{print $2}')
  else
    timeout 10  bash -c "while [ ! -e $(dev_part ${OSD_DEVICE} 1) ]; do sleep 1; done"
    chown ceph. $(dev_part ${OSD_DEVICE} 2)
    if [[ ${OSD_DMCRYPT} -eq 1 ]]; then
      ceph-disk -v --setuser ceph --setgroup disk --dmcrypt activate $(dev_part ${OSD_DEVICE} 1)
    else
      ceph-disk -v --setuser ceph --setgroup disk activate $(dev_part ${OSD_DEVICE} 1)
    fi
    OSD_ID=$(ceph-disk list | grep "$(dev_part ${ACTUAL_OSD_DEVICE} 1) ceph data" | awk -F, '{print $4}' | awk -F. '{print $2}')
  fi
  OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
  ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}

  # ceph-disk activiate has exec'ed /usr/bin/ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID}
  # wait till docker stop or ceph-osd is killed
  OSD_PID=$(pgrep -U ceph -f "^/usr/bin/ceph-osd \-\-cluster ${CLUSTER}.*\-i ${OSD_ID} \-\-setuser") || true
  if [ -n "${OSD_PID}" ]; then
      log "OSD (PID ${OSD_PID}) is running, waiting till it exits"
      while [ -e /proc/${OSD_PID} ]; do sleep 1;done
  else
      log "SUCCESS"
      exec /usr/bin/ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID} --setuser ceph --setgroup disk
  fi
}


#############
# OSD_DISKS #
#############
function get_osd_dev {
  for i in ${OSD_DISKS}
   do
    osd_id=$(echo ${i}|sed 's/\(.*\):\(.*\)/\1/')
    osd_dev="/dev/$(echo ${i}|sed 's/\(.*\):\(.*\)/\2/')"
    if [ ${osd_id} = ${1} ]; then
      echo -n "${osd_dev}"
    fi
  done
}

function osd_disks {
  if [[ ! -d /var/lib/ceph/osd ]]; then
    log "ERROR- could not find the osd directory, did you bind mount the OSD data directory?"
    log "ERROR- use -v <host_osd_data_dir>:/var/lib/ceph/osd"
    exit 1
  fi

  if [[  -z ${OSD_DISKS} ]]; then
    log "ERROR- could not find the osd devices, did you configure OSD disks?"
    log "ERROR- use -e OSD_DISKS=\"0:sdd 1:sde 2:sdf\""
    exit 1
  fi

  # make sure ceph owns the directory
  chown ceph. /var/lib/ceph/osd

  # Create the directory and an empty Procfile
  mkdir -p /etc/forego/${CLUSTER}
  echo "" > /etc/forego/${CLUSTER}/Procfile

  # check if anything is there, if not create an osd with directory
  if [[ -z "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
    log "Mount existing and prepared OSD disks for ceph-cluster ${CLUSTER}"
    for OSD_ID in $(ls /var/lib/ceph/osd |  awk 'BEGIN { FS = "-" } ; { print $2 }'); do
      OSD_DEV=$(get_osd_dev ${OSD_ID})
      if [[ -z ${OSD_DEV} ]]; then
        log "No device mapping for ${CLUSTER}-${OSD_ID} for ceph-cluster ${CLUSTER}"
        exit 1
      fi
      mount ${MOUNT_OPTS} $(dev_part ${OSD_DEV} 1) /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/
      xOSD_ID=$(cat /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/whoami)
      if [[ "${OSD_ID}" != "${xOSD_ID}" ]]; then
        log "Device ${OSD_DEV} is corrupt for /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}"
        exit 1
      fi

      echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID} --setuser ceph --setgroup disk" | tee -a /etc/forego/${CLUSTER}/Procfile

    done

    exec /usr/local/bin/forego start -f /etc/forego/${CLUSTER}/Procfile
  else
    for i in ${OSD_DISKS}; do
      OSD_ID=$(echo ${i}|sed 's/\(.*\):\(.*\)/\1/')
      OSD_DEV="/dev/$(echo ${i}|sed 's/\(.*\):\(.*\)/\2/')"
      if [[ "$(parted --script ${OSD_DEV} print | egrep '^ 1.*ceph data')" && ${OSD_FORCE_ZAP} -ne "1" ]]; then
        log "ERROR- It looks like this device is an OSD, set OSD_FORCE_ZAP=1 to use this device anyway and zap its content"
        exit 1
      elif [[ "$(parted --script ${OSD_DEV} print | egrep '^ 1.*ceph data')" && ${OSD_FORCE_ZAP} -eq "1" ]]; then
        ceph-disk -v zap ${OSD_DEV}
      fi

      if [[ ! -z "${OSD_JOURNAL}" ]]; then
        ceph-disk -v prepare ${CEPH_OPTS} ${OSD_DEV} ${OSD_JOURNAL}
#        chown ceph. ${OSD_JOURNAL}
        ceph-disk -v --setuser ceph --setgroup disk activate $(dev_part ${OSD_DEV} 1)
      else
        ceph-disk -v prepare ${CEPH_OPTS} ${OSD_DEV}
#        chown ceph. $(dev_part ${OSD_DEV} 2)
        ceph-disk -v --setuser ceph --setgroup disk activate $(dev_part ${OSD_DEV} 1)
      fi

      OSD_ID=$(cat /var/lib/ceph/osd/$(ls -ltr /var/lib/ceph/osd/ | tail -n1 | awk -v pattern="$CLUSTER" '$0 ~ pattern {print $9}')/whoami)
      OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
      ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}

      # ceph-disk activiate has exec'ed /usr/bin/ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID}
      # wait till docker stop or ceph-osd is killed
      OSD_PID=$(ps -ef |grep ceph-osd |grep osd.${OSD_ID} |awk '{print $2}')
      if [ -n "${OSD_PID}" ]; then
          log "OSD (PID ${OSD_PID}) is running, waiting till it exits"
          while [ -e /proc/${OSD_PID} ]; do sleep 1;done
      fi

      echo "${CLUSTER}-${OSD_ID}: /usr/bin/ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID} --setuser ceph --setgroup disk" | tee -a /etc/forego/${CLUSTER}/Procfile


    done

    log "SUCCESS"

    exec /usr/local/bin/forego start -f /etc/forego/${CLUSTER}/Procfile
  fi
}


##########################
# OSD_ACTIVATE_JOURNAL   #
##########################

function osd_activate_journal {
  if [[ -z "${OSD_JOURNAL}" ]];then
    log "ERROR- You must provide a device to build your OSD journal ie: /dev/sdb2"
    exit 1
  fi

  # wait till partition exists
  timeout 10  bash -c "while [ ! -e ${OSD_JOURNAL} ]; do sleep 1; done"

  mkdir -p /var/lib/ceph/osd
  chown ceph. /var/lib/ceph/osd
  chown ceph. ${OSD_JOURNAL}
  ceph-disk -v --setuser ceph --setgroup disk activate-journal ${OSD_JOURNAL}

  OSD_ID=$(cat /var/lib/ceph/osd/$(ls -ltr /var/lib/ceph/osd/ | tail -n1 | awk -v pattern="$CLUSTER" '$0 ~ pattern {print $9}')/whoami)
  OSD_WEIGHT=$(df -P -k /var/lib/ceph/osd/${CLUSTER}-$OSD_ID/ | tail -1 | awk '{ d= $2/1073741824 ; r = sprintf("%.2f", d); print r }')
  ceph ${CEPH_OPTS} --name=osd.${OSD_ID} --keyring=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring osd crush create-or-move -- ${OSD_ID} ${OSD_WEIGHT} ${CRUSH_LOCATION}

  # ceph-disk activiate has exec'ed /usr/bin/ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID}
  # wait till docker stop or ceph-osd is killed
  OSD_PID=$(ps -ef |grep ceph-osd |grep osd.${OSD_ID} |awk '{print $2}')
  if [ -n "${OSD_PID}" ]; then
      log "OSD (PID ${OSD_PID}) is running, waiting till it exits"
      while [ -e /proc/${OSD_PID} ]; do sleep 1;done
  else
      log "SUCCESS"
      exec /usr/bin/ceph-osd ${CEPH_OPTS} -f -d -i ${OSD_ID} --setuser ceph --setgroup disk
  fi
}


#######
# MDS #
#######

function start_mds {
  get_config
  check_config
  create_socket_dir

  # Check to see if we are a new MDS
  if [ ! -e /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring ]; then

     mkdir -p /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}
     chown ceph. /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}

    if [ -e /etc/ceph/${CLUSTER}.client.admin.keyring ]; then
       KEYRING_OPT="--name client.admin --keyring /etc/ceph/${CLUSTER}.client.admin.keyring"
    elif [ -e /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring ]; then
       KEYRING_OPT="--name client.bootstrap-mds --keyring /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring"
    else
      log "ERROR- Failed to bootstrap MDS: could not find admin or bootstrap-mds keyring.  You can extract it from your current monitor by running 'ceph auth get client.bootstrap-mds -o /var/lib/ceph/bootstrap-mds/${CLUSTER}.keyring'"
      exit 1
    fi

    timeout 10 ceph ${CEPH_OPTS} $KEYRING_OPT health || exit 1

    # Generate the MDS key
    ceph ${CEPH_OPTS} $KEYRING_OPT auth get-or-create mds.$MDS_NAME osd 'allow rwx' mds 'allow' mon 'allow profile mds' -o /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring
    chown ceph. /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring
    chmod 600 /var/lib/ceph/mds/${CLUSTER}-${MDS_NAME}/keyring

  fi

  # NOTE (leseb): having the admin keyring is really a security issue
  # If we need to bootstrap a MDS we should probably create the following on the monitors
  # I understand that this handy to do this here
  # but having the admin key inside every container is a concern

  # Create the Ceph filesystem, if necessary
  if [ $CEPHFS_CREATE -eq 1 ]; then

    get_admin_key
    check_admin_key

    if [[ "$(ceph fs ls | grep -c name:.${CEPHFS_NAME},)" -eq "0" ]]; then
       # Make sure the specified data pool exists
       if ! ceph ${CEPH_OPTS} osd pool stats ${CEPHFS_DATA_POOL} > /dev/null 2>&1; then
          ceph ${CEPH_OPTS} osd pool create ${CEPHFS_DATA_POOL} ${CEPHFS_DATA_POOL_PG}
       fi

       # Make sure the specified metadata pool exists
       if ! ceph ${CEPH_OPTS} osd pool stats ${CEPHFS_METADATA_POOL} > /dev/null 2>&1; then
          ceph ${CEPH_OPTS} osd pool create ${CEPHFS_METADATA_POOL} ${CEPHFS_METADATA_POOL_PG}
       fi

       ceph ${CEPH_OPTS} fs new ${CEPHFS_NAME} ${CEPHFS_METADATA_POOL} ${CEPHFS_DATA_POOL}
    fi
  fi

  log "SUCCESS"
  # NOTE: prefixing this with exec causes it to die (commit suicide)
  /usr/bin/ceph-mds ${CEPH_OPTS} -d -i ${MDS_NAME} --setuser ceph --setgroup ceph
}


#######
# RGW #
#######

function start_rgw {
  get_config
  check_config
  create_socket_dir

  if [ ${CEPH_GET_ADMIN_KEY} -eq "1" ]; then
    get_admin_key
    check_admin_key
  fi

  # Check to see if our RGW has been initialized
  if [ ! -e /var/lib/ceph/radosgw/${RGW_NAME}/keyring ]; then

    mkdir -p /var/lib/ceph/radosgw/${RGW_NAME}
    chown ceph. /var/lib/ceph/radosgw/${RGW_NAME}

    if [ ! -e /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring ]; then
      log "ERROR- /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring must exist. You can extract it from your current monitor by running 'ceph auth get client.bootstrap-rgw -o /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring'"
      exit 1
    fi

    timeout 10 ceph ${CEPH_OPTS} --name client.bootstrap-rgw --keyring /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring health || exit 1

    # Generate the RGW key
    ceph ${CEPH_OPTS} --name client.bootstrap-rgw --keyring /var/lib/ceph/bootstrap-rgw/${CLUSTER}.keyring auth get-or-create client.rgw.${RGW_NAME} osd 'allow rwx' mon 'allow rw' -o /var/lib/ceph/radosgw/${RGW_NAME}/keyring
    chown ceph. /var/lib/ceph/radosgw/${RGW_NAME}/keyring
    chmod 0600 /var/lib/ceph/radosgw/${RGW_NAME}/keyring
  fi

  log "SUCCESS"

  if [ "$RGW_REMOTE_CGI" -eq 1 ]; then
    /usr/bin/radosgw -d ${CEPH_OPTS} -n client.rgw.${RGW_NAME} -k /var/lib/ceph/radosgw/$RGW_NAME/keyring --rgw-socket-path="" --rgw-zonegroup="$RGW_ZONEGROUP" --rgw-zone="$RGW_ZONE" --rgw-frontends="fastcgi socket_port=$RGW_REMOTE_CGI_PORT socket_host=$RGW_REMOTE_CGI_HOST" --setuser ceph --setgroup ceph
  else
    /usr/bin/radosgw -d ${CEPH_OPTS} -n client.rgw.${RGW_NAME} -k /var/lib/ceph/radosgw/$RGW_NAME/keyring --rgw-socket-path="" --rgw-zonegroup="$RGW_ZONEGROUP" --rgw-zone="$RGW_ZONE" --rgw-frontends="civetweb port=$RGW_CIVETWEB_PORT" --setuser ceph --setgroup ceph
  fi
}

function create_rgw_user {

  # Check to see if our RGW has been initialized
  if [ ! -e /var/lib/ceph/radosgw/keyring ]; then
    log "ERROR- /var/lib/ceph/radosgw/keyring must exist. Please get it from your Rados Gateway"
    exit 1
  fi

  mkdir -p "/var/lib/ceph/radosgw/${RGW_NAME}"
  mv /var/lib/ceph/radosgw/keyring /var/lib/ceph/radosgw/${RGW_NAME}/keyring

  if [ -z "${RGW_USER_SECRET_KEY}" ]; then
    radosgw-admin user create --uid=${RGW_USER} --display-name="RGW ${RGW_USER} User" -c /etc/ceph/${CLUSTER}.conf
  else
    radosgw-admin user create --uid=${RGW_USER} --access-key=${RGW_USER_ACCESS_KEY} --secret=${RGW_USER_SECRET_KEY} --display-name="RGW ${RGW_USER} User" -c /etc/ceph/${CLUSTER}.conf
  fi
}


###########
# RESTAPI #
###########

function start_restapi {
  get_config
  check_config

  # Ensure we have the admin key
  get_admin_key
  check_admin_key

  # Check to see if we need to add a [client.restapi] section; add, if necessary
  if [[ ! "$(egrep "\[client.restapi\]" /etc/ceph/${CLUSTER}.conf)" ]]; then
    cat <<ENDHERE >>/etc/ceph/${CLUSTER}.conf

[client.restapi]
  public addr = ${RESTAPI_IP}:${RESTAPI_PORT}
  restapi base url = ${RESTAPI_BASE_URL}
  restapi log level = ${RESTAPI_LOG_LEVEL}
  log file = ${RESTAPI_LOG_FILE}
ENDHERE
  fi

  log "SUCCESS"

  # start ceph-rest-api
  exec /usr/bin/ceph-rest-api ${CEPH_OPTS} -n client.admin

}


##############
# RBD MIRROR #
##############

function start_rbd_mirror {
  get_config
  check_config
  create_socket_dir

  # ensure we have the admin key
  get_admin_key
  check_admin_key

  log "SUCCESS"
  # start rbd-mirror
  exec /usr/bin/rbd-mirror ${CEPH_OPTS} -d --setuser ceph --setgroup ceph

}


#######
# NFS #
#######

function start_rpc {
  rpcbind || return 0
  rpc.statd -L || return 0
  rpc.idmapd || return 0

}

function start_nfs {
  get_config
  check_config
  create_socket_dir

  # Init RPC
  start_rpc

  log "SUCCESS"
  # start ganesha
  exec /usr/bin/ganesha.nfsd -F ${GANESHA_OPTIONS} ${GANESHA_EPOCH}

}


##############
# ZAP DEVICE #
##############

function zap_device {
  if [[ -z ${OSD_DEVICE} ]]; then
    log "Please provide device(s) to zap!"
    log "ie: '-e OSD_DEVICE=/dev/sdb' or '-e OSD_DEVICE=/dev/sdb,/dev/sdc'"
    exit 1
  fi

  # testing all the devices first so we just don't do anything if one device is wrong
  for device in $(echo ${OSD_DEVICE} | tr "," " "); do
    if ! file -s $device &> /dev/null; then
      log "Provided device $device does not exist."
      exit 1
    fi
    # if the disk passed is a raw device AND the boot system disk
    if echo $device | egrep -sq '/dev/([hsv]d[a-z]{1,2}|cciss/c[0-9]d[0-9]p|nvme[0-9]n[0-9]p){1,2}$' && parted -s $(echo $device | egrep -o '/dev/([hsv]d[a-z]{1,2}|cciss/c[0-9]d[0-9]p|nvme[0-9]n[0-9]p){1,2}') print | grep -sq boot; then
      log "Looks like $device has a boot partition,"
      log "if you want to delete specific partitions point to the partition instead of the raw device"
      log "Do not use your system disk!"
      exit 1
    fi
  done

  for device in $(echo ${OSD_DEVICE} | tr "," " "); do
    raw_device=$(echo $device | egrep -o '/dev/([hsv]d[a-z]{1,2}|cciss/c[0-9]d[0-9]p|nvme[0-9]n[0-9]p){1,2}')
    if echo $device | egrep -sq '/dev/([hsv]d[a-z]{1,2}|cciss/c[0-9]d[0-9]p|nvme[0-9]n[0-9]p){1,2}$'; then
      log "Zapping the entire device $device"
      sgdisk --zap-all --clear --mbrtogpt -g -- $device
    else
      # get the desired partition number(s)
      partition_nb=$(echo $device | egrep -o '[0-9]{1,2}$')
      log "Zapping partition $device"
      sgdisk --delete $partition_nb $raw_device
    fi
    log "Executing partprobe on $raw_device"
    partprobe $raw_device
    udevadm settle
  done
}


####################
# WATCH MON HEALTH #
####################

function watch_mon_health {
  log "checking for zombie mons"

  while [ true ]
  do
    log "checking for zombie mons"
    /check_zombie_mons.py || true;
    log "sleep 30 sec"
    sleep 30
  done
}


###############
# CEPH_DAEMON #
###############

# Normalize DAEMON to lowercase
CEPH_DAEMON=$(echo ${CEPH_DAEMON} |tr '[:upper:]' '[:lower:]')

# If we are given a valid first argument, set the
# CEPH_DAEMON variable from it
case "$CEPH_DAEMON" in
  populate_kvstore)
    populate_kv
    ;;
  mds)
    start_mds
    ;;
  mon)
    start_mon
    ;;
  osd)
    start_osd
    ;;
  osd_directory)
    OSD_TYPE="directory"
    start_osd
    ;;
  osd_directory_single)
    OSD_TYPE="directory_single"
    start_osd
    ;;
  osd_ceph_disk)
    OSD_TYPE="disk"
    start_osd
    ;;
  osd_ceph_disk_prepare)
    OSD_TYPE="prepare"
    start_osd
    ;;
  osd_ceph_disk_activate)
    OSD_TYPE="activate"
    start_osd
    ;;
  osd_ceph_activate_journal)
    OSD_TYPE="activate_journal"
    start_osd
    ;;
  rgw)
    start_rgw
    ;;
  rgw_user)
    create_rgw_user
    ;;
  restapi)
    start_restapi
    ;;
  rbd_mirror)
    start_rbd_mirror
    ;;
  nfs)
    start_nfs
    ;;
  zap_device)
    zap_device
    ;;
  mon_health)
    watch_mon_health
    ;;
  *)
  if [ ! -n "$CEPH_DAEMON" ]; then
    log "ERROR- One of CEPH_DAEMON or a daemon parameter must be defined as the name "
    log "of the daemon you want to deploy."
    log "Valid values for CEPH_DAEMON are MON, OSD, OSD_DIRECTORY, OSD_CEPH_DISK, OSD_CEPH_DISK_PREPARE, OSD_CEPH_DISK_ACTIVATE, OSD_CEPH_ACTIVATE_JOURNAL, MDS, RGW, RGW_USER, RESTAPI, ZAP_DEVICE, RBD_MIRROR, NFS"
    log "Valid values for the daemon parameter are mon, osd, osd_directory, osd_ceph_disk, osd_ceph_disk_prepare, osd_ceph_disk_activate, osd_ceph_activate_journal, mds, rgw, rgw_user, restapi, zap_device, rbd_mirror, nfs"
    exit 1
  fi
  ;;
esac

exit 0
