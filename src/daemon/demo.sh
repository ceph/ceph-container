#!/bin/bash
set -e

unset "DAEMON_OPTS[${#DAEMON_OPTS[@]}-1]" # remove the last element of the array
: "${OSD_PATH:=/var/lib/ceph/osd/${CLUSTER}-0}"
PREPARE_OSD=$OSD_PATH
ACTIVATE_OSD=$OSD_PATH
# the following ceph version can start with a numerical value where the new ones need a proper name
if [[ "$CEPH_VERSION" == "luminous" ]]; then
  MDS_NAME=0
else
  MDS_NAME=demo
fi
MDS_PATH="/var/lib/ceph/mds/${CLUSTER}-$MDS_NAME"
RGW_PATH="/var/lib/ceph/radosgw/${CLUSTER}-rgw.${RGW_NAME}"
# shellcheck disable=SC2153
MGR_PATH="/var/lib/ceph/mgr/${CLUSTER}-$MGR_NAME"
RESTAPI_IP=$MON_IP
MGR_IP=$MON_IP
: "${DEMO_DAEMONS:=all}"
: "${RGW_ENABLE_USAGE_LOG:=true}"
: "${RGW_USAGE_MAX_USER_SHARDS:=1}"
: "${RGW_USAGE_MAX_SHARDS:=32}"
: "${RGW_USAGE_LOG_FLUSH_THRESHOLD:=1}"
: "${RGW_USAGE_LOG_TICK_INTERVAL:=1}"
: "${EXPOSED_IP:=127.0.0.1}"
: "${SREE_PORT:=5000}"

# rgw options
: "${RGW_CIVETWEB_IP:=0.0.0.0}"
: "${RGW_CIVETWEB_PORT:=8080}"
: "${RGW_FRONTEND_IP:=$RGW_CIVETWEB_IP}"
: "${RGW_FRONTEND_PORT:=$RGW_CIVETWEB_PORT}"
: "${RGW_FRONTEND_TYPE:="civetweb"}"

: "${RBD_POOL:="rbd"}"


RGW_CIVETWEB_OPTIONS="$RGW_CIVETWEB_OPTIONS port=$RGW_CIVETWEB_IP:$RGW_CIVETWEB_PORT"
RGW_BEAST_OPTIONS="$RGW_BEAST_OPTIONS endpoint=$RGW_FRONTEND_IP:$RGW_FRONTEND_PORT"

if [[ "$RGW_FRONTEND_TYPE" == "civetweb" ]]; then
  RGW_FRONTED_OPTIONS="$RGW_CIVETWEB_OPTIONS"
elif [[ "$RGW_FRONTEND_TYPE" == "beast" ]]; then
  RGW_FRONTED_OPTIONS="$RGW_BEAST_OPTIONS"
else
  log "ERROR: unsupported rgw backend type $RGW_FRONTEND_TYPE"
  exit 1
fi

: "${RGW_FRONTEND:="$RGW_FRONTEND_TYPE $RGW_FRONTED_OPTIONS"}"

if [[ "$RGW_FRONTEND_TYPE" == "beast" ]]; then
  if [[ "$CEPH_VERSION" == "luminous" ]]; then
    RGW_FRONTEND_TYPE=beast
    log "ERROR: unsupported rgw backend type $RGW_FRONTEND_TYPE for your Ceph release $CEPH_VERSION, use at least the Mimic version."
    exit 1
  fi
fi

CEPH_DISK_CLI_OPTS=()


#######
# MON #
#######
function bootstrap_mon {
  # shellcheck disable=SC1091
  source start_mon.sh
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
  if [[ -n "$OSD_DEVICE" ]]; then
    PREPARE_OSD=$OSD_DEVICE
    if [[ -b "$OSD_DEVICE" ]]; then
      ACTIVATE_OSD=${OSD_DEVICE}1
    else
      log "Invalid $OSD_DEVICE, only block device is supported"
      exit 1
    fi
  fi

  if [ ! -e "$OSD_PATH"/keyring ]; then
    if ! grep -qE "osd data = $OSD_PATH" /etc/ceph/"${CLUSTER}".conf; then
      echo "osd data = $OSD_PATH" >> /etc/ceph/"${CLUSTER}".conf
    fi
    CEPH_DISK_CLI_OPTS=(--bluestore)

    # bootstrap OSD
    mkdir -p "$OSD_PATH"
    chown --verbose -R ceph. "$OSD_PATH"
    if [ -n "$BLUESTORE_BLOCK_SIZE" ]; then
      size=$(parse_size "$BLUESTORE_BLOCK_SIZE")
      if ! grep -qE "bluestore_block_size = $size" /etc/ceph/"${CLUSTER}".conf; then
        echo "bluestore_block_size = $size" >> /etc/ceph/"${CLUSTER}".conf
      fi
    fi
    ceph-disk -v prepare "${CLI_OPTS[@]}" "${CEPH_DISK_CLI_OPTS[@]}" "$PREPARE_OSD"
    # this second chown will chown the partition created by ceph-disk e.g: /dev/sda1 and /dev/sda2
    chown --verbose -R ceph. "$PREPARE_OSD"*
    ceph-disk -v activate --mark-init none --no-start-daemon "$ACTIVATE_OSD"
  fi

  # start OSD
  chown --verbose -R ceph. "$OSD_PATH"
  ceph-osd "${DAEMON_OPTS[@]}" -i 0
  ceph "${CLI_OPTS[@]}" osd pool create "$RBD_POOL" 8
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
    ceph "${CLI_OPTS[@]}" auth get-or-create mds."$MDS_NAME" mds 'allow' osd 'allow *' mon 'allow profile mds' -o "$MDS_PATH"/keyring
    chown --verbose -R ceph. "$MDS_PATH"
  fi

  # start MDS
  ceph-mds "${DAEMON_OPTS[@]}" -i "$MDS_NAME"
}


#######
# RGW #
#######
function bootstrap_rgw {
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
  if [ -f /ceph-demo-user ]; then
    log "Demo user already exists with credentials:"
    cat /ceph-demo-user
  else
    log "Setting up a demo user..."
    if [ -n "$CEPH_DEMO_UID" ] && [ -n "$CEPH_DEMO_ACCESS_KEY" ] && [ -n "$CEPH_DEMO_SECRET_KEY" ]; then
      radosgw-admin "${CLI_OPTS[@]}" user create --uid="$CEPH_DEMO_UID" --display-name="Ceph demo user" --access-key="$CEPH_DEMO_ACCESS_KEY" --secret-key="$CEPH_DEMO_SECRET_KEY"
    else
      radosgw-admin "${CLI_OPTS[@]}" user create --uid="$CEPH_DEMO_UID" --display-name="Ceph demo user" > "${CEPH_DEMO_UID}_user_details"
      CEPH_DEMO_ACCESS_KEY=$(grep -Po '(?<="access_key": ")[^"]*' "${CEPH_DEMO_UID}_user_details")
      CEPH_DEMO_SECRET_KEY=$(grep -Po '(?<="secret_key": ")[^"]*' "${CEPH_DEMO_UID}_user_details")
    fi
    sed -i s/AWS_ACCESS_KEY_PLACEHOLDER/"$CEPH_DEMO_ACCESS_KEY"/ /root/.s3cfg
    sed -i s/AWS_SECRET_KEY_PLACEHOLDER/"$CEPH_DEMO_SECRET_KEY"/ /root/.s3cfg
    echo "Access key: $CEPH_DEMO_ACCESS_KEY" > /ceph-demo-user
    echo "Secret key: $CEPH_DEMO_SECRET_KEY" >> /ceph-demo-user

    radosgw-admin "${CLI_OPTS[@]}" caps add --caps="buckets=*;users=*;usage=*;metadata=*" --uid="$CEPH_DEMO_UID"

    # Use rgw port
    sed -i "s/host_base = localhost/host_base = ${RGW_NAME}:${RGW_CIVETWEB_PORT}/" /root/.s3cfg
    sed -i "s/host_bucket = localhost/host_bucket = ${RGW_NAME}:${RGW_CIVETWEB_PORT}/" /root/.s3cfg

    if [ -n "$CEPH_DEMO_BUCKET" ]; then
      log "Creating bucket..."
      # waiting for rgw to be ready, 5 seconds is usually enough
      sleep 5
      s3cmd mb s3://"$CEPH_DEMO_BUCKET"
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
  # Init RPC
  rpcbind || return 0
  rpc.statd -L || return 0
  rpc.idmapd || return 0

  # start ganesha
  ganesha.nfsd "${GANESHA_OPTIONS[@]}" "${GANESHA_EPOCH}"
}


#######
# API #
#######
function bootstrap_rest_api {
  if ! grep -E "\\[client.restapi\\]" /etc/ceph/"${CLUSTER}".conf; then
    cat <<ENDHERE >>/etc/ceph/"${CLUSTER}".conf
[client.restapi]
public addr = ${RESTAPI_IP}:${RESTAPI_PORT}
restapi base url = ${RESTAPI_BASE_URL}
restapi log level = ${RESTAPI_LOG_LEVEL}
log file = ${RESTAPI_LOG_FILE}

ENDHERE
  fi

  # start ceph-rest-api
  ceph-rest-api "${CLI_OPTS[@]}" -c /etc/ceph/"${CLUSTER}".conf -n client.admin &
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
  ceph "${CLI_OPTS[@]}" auth get-or-create mgr."$MGR_NAME" mon 'allow *' -o "$MGR_PATH"/keyring
  chown --verbose -R ceph. "$MGR_PATH"

  ceph "${CLI_OPTS[@]}" mgr module enable dashboard --force
  ceph "${CLI_OPTS[@]}" config-key put mgr/dashboard/server_addr "$MGR_IP"

  # start ceph-mgr
  ceph-mgr "${DAEMON_OPTS[@]}" -i "$MGR_NAME"
}


########
# SREE #
########
function bootstrap_sree {
  if [ ! -f sree.tar.gz ]; then
    if [ -z "$SREE_VERSION" ]; then
      sree_latest=$(curl -s 'https://api.github.com/repos/leseb/Sree/releases/latest' | grep tarball_url | cut -d '"' -f 4)
      curl -L "$sree_latest" -o sree.tar.gz
    else
      curl -L https://github.com/leseb/Sree/archive/"$SREE_VERSION".tar.gz -o sree.tar.gz
    fi
    mkdir sree && tar xzvf sree.tar.gz -C sree --strip-components 1

    ACCESS_KEY=$(awk '/Access key/ {print $3}' /ceph-demo-user)
    SECRET_KEY=$(awk '/Secret key/ {print $3}' /ceph-demo-user)

    pushd sree
    sed -i "s|ENDPOINT|http://${EXPOSED_IP}:${RGW_CIVETWEB_PORT}|" static/js/base.js
    sed -i "s/ACCESS_KEY/$ACCESS_KEY/" static/js/base.js
    sed -i "s/SECRET_KEY/$SECRET_KEY/" static/js/base.js
    mv sree.cfg.sample sree.cfg
    sed -i "s/RGW_CIVETWEB_PORT_VALUE/$RGW_CIVETWEB_PORT/" sree.cfg
    sed -i "s/SREE_PORT_VALUE/$SREE_PORT/" sree.cfg
    popd
  fi

  # start Sree
  pushd sree
  python app.py &
  popd
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
    daemons_list="osd mds rgw nfs rbd_mirror rest_api"
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
        bootstrap_sree
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
      *)
        log "ERROR: unknown scenario!"
        log "Available scenarios are: mon mgr osd mds rgw nfs rbd_mirror rest_api"
        exit 1
        ;;
    esac
  done
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