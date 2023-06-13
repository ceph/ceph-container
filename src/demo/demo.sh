#!/bin/bash
set -e

unset "DAEMON_OPTS[${#DAEMON_OPTS[@]}-1]" # remove the last element of the array
: "${CLUSTER:=ceph}"
: "${MON_NAME:=${HOSTNAME}}"
: "${RGW_NAME:=${HOSTNAME}}"
: "${RBD_MIRROR_NAME:=${HOSTNAME}}"
: "${MGR_NAME:=${HOSTNAME}}"
: "${MDS_NAME:=${HOSTNAME}}"
: "${MON_DATA_DIR:=/var/lib/ceph/mon/${CLUSTER}-${MON_NAME}}"
: "${CEPH_CLUSTER_NETWORK:=${CEPH_PUBLIC_NETWORK}}"
DAEMON_OPTS=(--cluster "${CLUSTER}" --setuser ceph --setgroup ceph --default-log-to-stderr=true --err-to-stderr=true --default-log-to-file=false)
ADMIN_KEYRING=/etc/ceph/${CLUSTER}.client.admin.keyring
MON_KEYRING=/etc/ceph/${CLUSTER}.mon.keyring
RGW_KEYRING=/var/lib/ceph/radosgw/${CLUSTER}-rgw.${RGW_NAME}/keyring
MONMAP=/etc/ceph/monmap-${CLUSTER}
# the following ceph version can start with a numerical value where the new ones need a proper name
MDS_NAME=demo
MDS_PATH="/var/lib/ceph/mds/${CLUSTER}-$MDS_NAME"
RGW_PATH="/var/lib/ceph/radosgw/${CLUSTER}-rgw.${RGW_NAME}"
# shellcheck disable=SC2153
MGR_PATH="/var/lib/ceph/mgr/${CLUSTER}-$MGR_NAME"
# shellcheck disable=SC2034
MGR_IP=$MON_IP
: "${DEMO_DAEMONS:=all}"
: "${RGW_ENABLE_USAGE_LOG:=true}"
: "${RGW_USAGE_MAX_USER_SHARDS:=1}"
: "${RGW_USAGE_MAX_SHARDS:=32}"
: "${RGW_USAGE_LOG_FLUSH_THRESHOLD:=1}"
: "${RGW_USAGE_LOG_TICK_INTERVAL:=1}"
: "${EXPOSED_IP:=127.0.0.1}"

# rgw options
: "${RGW_FRONTEND_IP:=0.0.0.0}"
: "${RGW_FRONTEND_PORT:=8080}"
: "${RGW_FRONTEND_TYPE:="beast"}"

function log {
  if [ -z "$*" ]; then
    return 1
  fi

  local timestamp
  timestamp=$(date '+%F %T')
  echo "$timestamp  $0: $*"
  return 0
}

function get_mon_config {
  # IPv4 is the default unless we specify it
  IP_LEVEL=${1:-4}

  if [ ! -e /etc/ceph/"${CLUSTER}".conf ]; then
    local fsid
    fsid=$(uuidgen)
    cat <<ENDHERE >/etc/ceph/"${CLUSTER}".conf
[global]
fsid = $fsid
mon initial members = ${MON_NAME}
mon host = v2:${MON_IP}:${MON_PORT}/0
osd crush chooseleaf type = 0
public network = ${CEPH_PUBLIC_NETWORK}
cluster network = ${CEPH_PUBLIC_NETWORK}
osd pool default size = 2
auth_allow_insecure_global_id_reclaim = false
ENDHERE

  # For ext4
  if [ "$(findmnt -n -o FSTYPE -T /var/lib/ceph)" = "ext4" ] || [ "$OSD_FORCE_EXT4" == "yes" ]; then
    cat <<ENDHERE >> /etc/ceph/"${CLUSTER}".conf
osd max object name len = 256
osd max object namespace len = 64
ENDHERE
  fi
    if [ "$IP_LEVEL" -eq 6 ]; then
      echo "ms bind ipv6 = true" >> /etc/ceph/"${CLUSTER}".conf
    fi
  else
    # extract fsid from ceph.conf
    fsid=$(grep "fsid" /etc/ceph/"${CLUSTER}".conf | awk '{print $NF}')
  fi

  if [ ! -e "$ADMIN_KEYRING" ]; then
    if [ -z "$ADMIN_SECRET" ]; then
      # Automatically generate administrator key
      CLI+=(--gen-key)
    else
      # Generate custom provided administrator key
      CLI+=("--add-key=$ADMIN_SECRET")
    fi
    ceph-authtool "$ADMIN_KEYRING" --create-keyring -n client.admin "${CLI[@]}" --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'
  fi

  if [ ! -e "$MON_KEYRING" ]; then
    # Generate the mon. key
    ceph-authtool "$MON_KEYRING" --create-keyring --gen-key -n mon. --cap mon 'allow *'
  fi

  # Apply proper permissions to the keys
  chown "${CHOWN_OPT[@]}" ceph. "$MON_KEYRING" "$ADMIN_KEYRING"

  if [ ! -e "$MONMAP" ]; then
    if [ -e /etc/ceph/monmap ]; then
      # Rename old monmap
      mv /etc/ceph/monmap "$MONMAP"
    else
      # Generate initial monitor map
      monmaptool --create --add "${MON_NAME}" "${MON_IP}:${MON_PORT}" --fsid "${fsid}" "$MONMAP"
    fi
    chown "${CHOWN_OPT[@]}" ceph. "$MONMAP"
  fi
}

function start_mon {
  if [[ -z "$CEPH_PUBLIC_NETWORK" ]]; then
    log "ERROR- CEPH_PUBLIC_NETWORK must be defined as the name of the network for the OSDs"
    exit 1
  fi

  if [[ -z "$MON_IP" ]]; then
    log "ERROR- MON_IP must be defined as the IP address of the monitor"
    exit 1
  fi

  # If we don't have a monitor keyring, this is a new monitor
  if [ ! -e "$MON_DATA_DIR/keyring" ]; then
    mkdir -p "$MON_DATA_DIR"
    chown 167:167 "$MON_DATA_DIR"
    get_mon_config "$IP_VERSION"

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
        get_mon_config "$IP_VERSION"
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
  fi

  # start MON
    /usr/bin/ceph-mon "${DAEMON_OPTS[@]}" -i "${MON_NAME}" --mon-data "$MON_DATA_DIR" --public-addr "${MON_IP}"

    if [ -n "$NEW_USER_KEYRING" ]; then
      echo "$NEW_USER_KEYRING" | ceph "${CLI_OPTS[@]}" auth import -i -
    fi
}

#######
# MON #
#######
function bootstrap_mon {
  # shellcheck disable=SC2034
  MON_PORT=3300
  # shellcheck disable=SC1091

  start_mon

  chown --verbose ceph. /etc/ceph/*
}


#######
# OSD #
#######
function parse_size {
  # Taken from https://stackoverflow.com/questions/17615881/simplest-method-to-convert-file-size-with-suffix-to-bytes
  local SUFFIXES=('' K M G T P E Z Y)
  local MULTIPLIER=1

  shopt -s nocasematch

  for SUFFIX in "${SUFFIXES[@]}"; do
    local REGEX="^([0-9]+)(${SUFFIX}i?B?)?\$"

    if [[ $1 =~ $REGEX ]]; then
      echo $((BASH_REMATCH[1] * MULTIPLIER))
      return 0
    fi

    ((MULTIPLIER *= 1024))
  done

  echo "$0: invalid size \`$1'" >&2
  return 1
}

function bootstrap_osd {
  if [[ ${OSD_BLUESTORE} -eq 1 ]]; then
    tune_memory "$(get_available_ram)"
  fi

  if [[ -n "$OSD_DEVICE" ]]; then
    if [[ -b "$OSD_DEVICE" ]]; then
      if [ -n "$BLUESTORE_BLOCK_SIZE" ]; then
        size=$(parse_size "$BLUESTORE_BLOCK_SIZE")
        if ! grep -qE "bluestore_block_size = $size" /etc/ceph/"${CLUSTER}".conf; then
          echo "bluestore_block_size = $size" >> /etc/ceph/"${CLUSTER}".conf
        fi
      fi
    else
      log "Invalid $OSD_DEVICE, only block device is supported"
      exit 1
    fi
  fi

  : "${OSD_COUNT:=1}"

  for i in $(seq 1 1 "$OSD_COUNT"); do
    (( OSD_ID="$i"-1 )) || true
    OSD_PATH="/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}"

    if [ ! -e "$OSD_PATH"/keyring ]; then
      if ! grep -qE "osd objectstore = bluestore" /etc/ceph/"${CLUSTER}".conf; then
        echo "osd objectstore = bluestore" >> /etc/ceph/"${CLUSTER}".conf
      fi
      if ! grep -qE "osd data = $OSD_PATH" /etc/ceph/"${CLUSTER}".conf; then
        cat <<ENDHERE >>/etc/ceph/"${CLUSTER}".conf

[osd.${OSD_ID}]
osd data = ${OSD_PATH}

ENDHERE
      fi
      # bootstrap OSD
      mkdir -p "$OSD_PATH"
      chown --verbose -R ceph. "$OSD_PATH"

      # if $OSD_DEVICE exists we deploy with ceph-volume
      if [[ -n "$OSD_DEVICE" ]]; then
        ceph-volume lvm prepare --data "$OSD_DEVICE"
      else
        # we go for a 'manual' bootstrap
        ceph "${CLI_OPTS[@]}" auth get-or-create osd."$OSD_ID" mon 'allow profile osd' osd 'allow *' mgr 'allow profile osd' -o "$OSD_PATH"/keyring
        ceph-osd --conf /etc/ceph/"${CLUSTER}".conf --osd-data "$OSD_PATH" --mkfs -i "$OSD_ID"
      fi
    fi

    # activate OSD
    if [[ -n "$OSD_DEVICE" ]]; then
      OSD_FSID="$(ceph-volume lvm list --format json | $PYTHON -c "import sys, json; print(json.load(sys.stdin)[\"$OSD_ID\"][0][\"tags\"][\"ceph.osd_fsid\"])")"
      ceph-volume lvm activate --no-systemd --bluestore "${OSD_ID}" "${OSD_FSID}"
    fi

    # start OSD
    chown --verbose -R ceph. "$OSD_PATH"
    ceph-osd "${DAEMON_OPTS[@]}" -i "$OSD_ID"
  done
}

#######
# MDS #
#######
function bootstrap_mds {
  if [ ! -e "$MDS_PATH"/keyring ]; then
    # create ceph filesystem
    ceph "${CLI_OPTS[@]}" osd pool create cephfs_data 8
    ceph "${CLI_OPTS[@]}" osd pool create cephfs_metadata 8
    ceph "${CLI_OPTS[@]}" fs new cephfs cephfs_metadata cephfs_data

    # bootstrap MDS
    mkdir -p "$MDS_PATH"
    ceph "${CLI_OPTS[@]}" auth get-or-create mds."$MDS_NAME" mds 'allow *' osd 'allow *' mon 'profile mds' mgr 'profile mds' -o "$MDS_PATH"/keyring
    chown --verbose -R ceph. "$MDS_PATH"
  fi

  # start MDS
  ceph-mds "${DAEMON_OPTS[@]}" -i "$MDS_NAME"
}


#######
# RGW #
#######
function bootstrap_rgw {
  if [[ "$RGW_FRONTEND_TYPE" == "civetweb" ]]; then
    # shellcheck disable=SC2153
    RGW_FRONTED_OPTIONS="$RGW_FRONTEND_OPTIONS port=$RGW_FRONTEND_IP:$RGW_FRONTEND_PORT"
  elif [[ "$RGW_FRONTEND_TYPE" == "beast" ]]; then
    RGW_FRONTED_OPTIONS="$RGW_FRONTEND_OPTIONS endpoint=$RGW_FRONTEND_IP:$RGW_FRONTEND_PORT"
  else
    log "ERROR: unsupported rgw backend type $RGW_FRONTEND_TYPE"
    exit 1
  fi

  : "${RGW_FRONTEND:="$RGW_FRONTEND_TYPE $RGW_FRONTED_OPTIONS"}"

  if [ ! -e "$RGW_PATH"/keyring ]; then
    # bootstrap RGW
    mkdir -p "$RGW_PATH" /var/log/ceph
    ceph "${CLI_OPTS[@]}" auth get-or-create client.rgw."${RGW_NAME}" osd 'allow rwx' mon 'allow rw' -o "$RGW_KEYRING"
    chown --verbose -R ceph. "$RGW_PATH"

    #configure rgw dns name
    cat <<ENDHERE >>/etc/ceph/"${CLUSTER}".conf

[client.rgw.${RGW_NAME}]
rgw dns name = ${RGW_NAME}
rgw enable usage log = ${RGW_ENABLE_USAGE_LOG}
rgw usage log tick interval = ${RGW_USAGE_LOG_TICK_INTERVAL}
rgw usage log flush threshold = ${RGW_USAGE_LOG_FLUSH_THRESHOLD}
rgw usage max shards = ${RGW_USAGE_MAX_SHARDS}
rgw usage max user shards = ${RGW_USAGE_MAX_USER_SHARDS}
log file = /var/log/ceph/client.rgw.${RGW_NAME}.log
rgw frontends = ${RGW_FRONTEND}

ENDHERE
  fi

  # start RGW
  radosgw "${DAEMON_OPTS[@]}" -n client.rgw."${RGW_NAME}" -k "$RGW_KEYRING"
}

function bootstrap_demo_user {
  CEPH_DEMO_USER="/opt/ceph-container/tmp/ceph-demo-user"
  if [ -f "$CEPH_DEMO_USER" ]; then
    log "Demo user already exists with credentials:"
    cat "$CEPH_DEMO_USER"
  else
    mkdir -p "$(dirname $CEPH_DEMO_USER)"
    log "Setting up a demo user..."
    if [ -n "$CEPH_DEMO_UID" ] && [ -n "$CEPH_DEMO_ACCESS_KEY" ] && [ -n "$CEPH_DEMO_SECRET_KEY" ]; then
      radosgw-admin "${CLI_OPTS[@]}" user create --uid="$CEPH_DEMO_UID" --display-name="Ceph demo user" --access-key="$CEPH_DEMO_ACCESS_KEY" --secret-key="$CEPH_DEMO_SECRET_KEY"
    else
      radosgw-admin "${CLI_OPTS[@]}" user create --uid="$CEPH_DEMO_UID" --display-name="Ceph demo user" > "/opt/ceph-container/tmp/${CEPH_DEMO_UID}_user_details"
      # Until mimic is supported let's link the file to its original place not to break cn.
      # When mimic will be EOL, cn will only have containers having the fil in the /opt directory and so this symlink could be removed
      ln -sf /opt/ceph-container/tmp/"${CEPH_DEMO_UID}_user_details" /
      CEPH_DEMO_ACCESS_KEY=$(grep -Po '(?<="access_key": ")[^"]*' /opt/ceph-container/tmp/"${CEPH_DEMO_UID}_user_details")
      CEPH_DEMO_SECRET_KEY=$(grep -Po '(?<="secret_key": ")[^"]*' /opt/ceph-container/tmp/"${CEPH_DEMO_UID}_user_details")
    fi
    sed -i s/AWS_ACCESS_KEY_PLACEHOLDER/"$CEPH_DEMO_ACCESS_KEY"/ /root/.s3cfg
    sed -i s/AWS_SECRET_KEY_PLACEHOLDER/"$CEPH_DEMO_SECRET_KEY"/ /root/.s3cfg
    echo "Access key: $CEPH_DEMO_ACCESS_KEY" > "$CEPH_DEMO_USER"
    echo "Secret key: $CEPH_DEMO_SECRET_KEY" >> "$CEPH_DEMO_USER"

    radosgw-admin "${CLI_OPTS[@]}" caps add --caps="buckets=*;users=*;usage=*;metadata=*" --uid="$CEPH_DEMO_UID"

    # Use rgw port
    sed -i "s/host_base = localhost/host_base = ${RGW_NAME}:${RGW_FRONTEND_PORT}/" /root/.s3cfg
    sed -i "s/host_bucket = localhost/host_bucket = ${RGW_NAME}:${RGW_FRONTEND_PORT}/" /root/.s3cfg

    if [ -n "$CEPH_DEMO_BUCKET" ]; then
      log "Creating bucket..."

      # Trying to create a s3cmd within 30 seconds
      timeout 30 bash -c "until s3cmd mb s3://$CEPH_DEMO_BUCKET; do sleep .1; done"
    fi
  fi
}


################
# IMPORT IN S3 #
################
function import_in_s3 {
  if [[ -d "$DATA_TO_SYNC" ]]; then
    log "Syncing $DATA_TO_SYNC in S3!"
    s3cmd mb s3://"$DATA_TO_SYNC_BUCKET"
    s3cmd sync "$DATA_TO_SYNC" s3://"$DATA_TO_SYNC_BUCKET"
  else
    log "$DATA_TO_SYNC is not a directory, nothing to do!"
  fi
}

#######
# NFS #
#######
function bootstrap_nfs {
  # dbus
  mkdir -p /run/dbus
  dbus-daemon --system || return 0

  # Init RPC
  rpcbind || return 0
  rpc.statd -L || return 0

  cat <<ENDHERE >/etc/ganesha/ganesha.conf
EXPORT
{
        Export_id=20134;
        Path = "/";
        Pseudo = /cephobject;
        Access_Type = RW;
        Protocols = 3,4;
        Transports = TCP;
        SecType = sys;
        Squash = Root_Squash;
        FSAL {
                Name = RGW;
                User_Id = "${CEPH_DEMO_UID}";
                Access_Key_Id ="${CEPH_DEMO_ACCESS_KEY}";
                Secret_Access_Key = "${CEPH_DEMO_SECRET_KEY}";
        }
}

RGW {
        ceph_conf = "/etc/ceph/${CLUSTER}.conf";
        cluster = "${CLUSTER}";
        name = "client.rgw.${RGW_NAME}";
}
ENDHERE

  # start ganesha
  mkdir -p /var/run/ganesha
  ganesha.nfsd "${GANESHA_OPTIONS[@]}" -L STDOUT "${GANESHA_EPOCH}"
}


#######
# API #
#######
function bootstrap_rest_api {
  ceph "${CLI_OPTS[@]}" mgr module enable restful
  ceph "${CLI_OPTS[@]}" restful create-self-signed-cert
  ceph "${CLI_OPTS[@]}" restful create-key demo
}


##############
# RBD MIRROR #
##############
function bootstrap_rbd_mirror {
  # start rbd-mirror
  rbd-mirror "${DAEMON_OPTS[@]}"
}


#######
# MGR #
#######
function bootstrap_mgr {
  mkdir -p "$MGR_PATH"
  ceph "${CLI_OPTS[@]}" auth get-or-create mgr."$MGR_NAME" mon 'allow profile mgr' mds 'allow *' osd 'allow *' -o "$MGR_PATH"/keyring
  chown --verbose -R ceph. "$MGR_PATH"

  # start ceph-mgr
  ceph-mgr "${DAEMON_OPTS[@]}" -i "$MGR_NAME"
}


########
# SREE #
########
function bootstrap_sree {
  SREE_DIR="/opt/ceph-container/sree"
  if [ ! -d "$SREE_DIR" ]; then
    mkdir -p "$SREE_DIR"
    tar xzvf /opt/ceph-container/tmp/sree.tar.gz -C "$SREE_DIR" --strip-components 1

    ACCESS_KEY=$(awk '/Access key/ {print $3}' /opt/ceph-container/tmp/ceph-demo-user)
    SECRET_KEY=$(awk '/Secret key/ {print $3}' /opt/ceph-container/tmp/ceph-demo-user)

    pushd "$SREE_DIR"
    sed -i "s|ENDPOINT|http://${EXPOSED_IP}:${RGW_FRONTEND_PORT}|" static/js/base.js
    sed -i "s/ACCESS_KEY/$ACCESS_KEY/" static/js/base.js
    sed -i "s/SECRET_KEY/$SECRET_KEY/" static/js/base.js
    mv sree.cfg.sample sree.cfg
    sed -i "s/RGW_CIVETWEB_PORT_VALUE/$RGW_FRONTEND_PORT/" sree.cfg
    sed -i "s/SREE_PORT_VALUE/$SREE_PORT/" sree.cfg
    popd
  fi

  # start Sree
  pushd "$SREE_DIR"
  $PYTHON app.py &
  popd
}


#########
# CRASH #
#########
function bootstrap_crash {
  CRASH_NAME="client.crash"
  mkdir -p /var/lib/ceph/crash/posted
  ceph "${CLI_OPTS[@]}" auth get-or-create "${CRASH_NAME}" mon 'profile crash' mgr 'profile crash' -o /etc/ceph/"${CLUSTER}"."${CRASH_NAME}".keyring
  chown --verbose -R ceph. /etc/ceph/"${CLUSTER}"."${CRASH_NAME}".keyring /var/lib/ceph/crash

  # start ceph-crash
  nohup ceph-crash -n "${CRASH_NAME}" &
}


###################
# BUILD BOOTSTRAP #
###################

function build_bootstrap {
  # NOTE(leseb): always bootstrap a mon and mgr no matter what
  # this is will prevent someone writing daemons in the wrong order
  # once both mon and mgr are up we don't care about the order
  bootstrap_mon
  bootstrap_mgr

  if [[ "$DEMO_DAEMONS" == "all" ]]; then
    daemons_list="osd mds rgw nfs rbd_mirror rest_api crash"
  else
    # change commas to space
    comma_to_space=${DEMO_DAEMONS//,/ }

    # transform to an array
    IFS=" " read -r -a array <<< "$comma_to_space"

    # sort and remove potential duplicate
    daemons_list=$(echo "${array[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
  fi

  for daemon in $daemons_list; do
    case "$daemon" in
      mon)
        # the mon is already present so we skip this
        continue
        ;;
      mgr)
        # the mgr is already present so we skip this
        continue
        ;;
      osd)
        bootstrap_osd
        ;;
      mds)
        bootstrap_mds
        ;;
      rgw)
        bootstrap_rgw
        bootstrap_demo_user
        if [[ -n "$DATA_TO_SYNC" ]] && [[ -n "$DATA_TO_SYNC_BUCKET" ]]; then
          import_in_s3
        fi
        ;;
      nfs)
        bootstrap_nfs
        ;;
      rbd_mirror)
        bootstrap_rbd_mirror
        ;;
      rest_api)
        bootstrap_rest_api
        ;;
      crash)
        bootstrap_crash
        ;;
      *)
        log "ERROR: unknown scenario!"
        log "Available scenarios are: mon mgr osd mds rgw nfs rbd_mirror rest_api"
        exit 1
        ;;
    esac
  done
}

# For a 'demo' container, we must ensure there is no Ceph files
function detect_ceph_files {
  if [ -f /etc/ceph/I_AM_A_DEMO ] || [ -f /var/lib/ceph/I_AM_A_DEMO ]; then
    log "Found residual files of a demo container."
    log "This looks like a restart, processing."
    return 0
  fi
  if [ -d /var/lib/ceph ] || [ -d /etc/ceph ]; then
    # For /etc/ceph, it always contains a 'rbdmap' file so we must check for length > 1
    if [[ "$(find /var/lib/ceph/ -mindepth 3 -maxdepth 3 -type f | wc -l)" != 0 ]] || [[ "$(find /etc/ceph -mindepth 1 -type f| wc -l)" -gt "1" ]]; then
      log "I can see existing Ceph files, please remove them!"
      log "To run the demo container, remove the content of /var/lib/ceph/ and /etc/ceph/"
      log "Before doing this, make sure you are removing any sensitive data."
      exit 1
    fi
  fi
}

#########
# WATCH #
#########
detect_ceph_files
build_bootstrap

# create 2 files so we can later check that this is a demo container
touch /var/lib/ceph/I_AM_A_DEMO /etc/ceph/I_AM_A_DEMO

log "SUCCESS"
exec ceph "${CLI_OPTS[@]}" -w