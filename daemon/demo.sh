#!/bin/bash
set -e

unset "DAEMON_OPTS[${#DAEMON_OPTS[@]}-1]" # remove the last element of the array
OSD_PATH="/var/lib/ceph/osd/${CLUSTER}-0"
MDS_PATH="/var/lib/ceph/mds/${CLUSTER}-0"
RGW_PATH="/var/lib/ceph/radosgw/$RGW_NAME"
MGR_PATH="/var/lib/ceph/mgr/${CLUSTER}-$MGR_NAME"
RESTAPI_IP=$MON_IP
MGR_IP=$MON_IP


#######
# MON #
#######
function bootstrap_mon {
  source start_mon.sh
  start_mon

  # change replica size
  ceph "${CLI_OPTS[@]}" osd pool set rbd size 1 || true # in Luminous this pool won't exist anymore and this patch runs on Luminous rc
  chown --verbose ceph. /etc/ceph/*
}


#######
# OSD #
#######
function bootstrap_osd {
  if [ ! -e "$OSD_PATH"/keyring ]; then
    # bootstrap OSD
    mkdir -p "$OSD_PATH"
    chown --verbose -R ceph. "$OSD_PATH"
    ceph-disk -v prepare --bluestore "$OSD_PATH"
    ceph-disk -v activate --mark-init none --no-start-daemon "$OSD_PATH"
  fi

  # start OSD
  chown --verbose -R ceph. "$OSD_PATH"
  ceph-osd "${DAEMON_OPTS[@]}" -i 0
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
    ceph "${CLI_OPTS[@]}" auth get-or-create mds.0 mds 'allow' osd 'allow *' mon 'allow profile mds' -o "$MDS_PATH"/keyring
    chown --verbose -R ceph. "$MDS_PATH"
  fi

  # start MDS
  ceph-mds "${DAEMON_OPTS[@]}" -i 0
}


#######
# RGW #
#######
function bootstrap_rgw {
  if [ ! -e "$RGW_PATH"/keyring ]; then
    # bootstrap RGW
    mkdir -p "$RGW_PATH"
    ceph "${CLI_OPTS[@]}" auth get-or-create client.radosgw.gateway osd 'allow rwx' mon 'allow rw' -o "$RGW_KEYRING"
    chown --verbose -R ceph. "$RGW_PATH"

    #configure rgw dns name
    cat <<ENDHERE >>/etc/ceph/"${CLUSTER}".conf

[client.radosgw.gateway]
rgw dns name = ${RGW_NAME}

ENDHERE
  fi

  # start RGW
  radosgw "${DAEMON_OPTS[@]}" -n client.radosgw.gateway -k "$RGW_PATH"/keyring --rgw-socket-path="" --rgw-frontends="civetweb port=${RGW_CIVETWEB_PORT}"
}

function bootstrap_demo_user {
  if [ -n "$CEPH_DEMO_UID" ] && [ -n "$CEPH_DEMO_ACCESS_KEY" ] && [ -n "$CEPH_DEMO_SECRET_KEY" ]; then
    if [ -f /ceph-demo-user ]; then
      log "Demo user already exists with credentials:"
      cat /ceph-demo-user
    else
      log "Setting up a demo user..."
      radosgw-admin "${CLI_OPTS[@]}" user create --uid="$CEPH_DEMO_UID" --display-name="Ceph demo user" --access-key="$CEPH_DEMO_ACCESS_KEY" --secret-key="$CEPH_DEMO_SECRET_KEY"
      sed -i s/AWS_ACCESS_KEY_PLACEHOLDER/"$CEPH_DEMO_ACCESS_KEY"/ /root/.s3cfg
      sed -i s/AWS_SECRET_KEY_PLACEHOLDER/"$CEPH_DEMO_SECRET_KEY"/ /root/.s3cfg
      echo "Access key: $CEPH_DEMO_ACCESS_KEY" > /ceph-demo-user
      echo "Secret key: $CEPH_DEMO_SECRET_KEY" >> /ceph-demo-user

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
  ganesha.nfsd -F "${GANESHA_OPTIONS[@]}" "${GANESHA_EPOCH}"
}


#######
# API #
#######
function bootstrap_rest_api {
  if ! grep -E "\[client.restapi\]" /etc/ceph/"${CLUSTER}".conf; then
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

  if ! grep -E "\[mgr\]" /etc/ceph/"${CLUSTER}".conf; then
    cat <<ENDHERE >>/etc/ceph/"${CLUSTER}".conf
[mgr]
mgr_modules = dashboard
ENDHERE
  fi

  ceph "${CLI_OPTS[@]}" config-key put mgr/dashboard/server_addr "$MGR_IP"

  # start ceph-mgr
  ceph-mgr "${DAEMON_OPTS[@]}" -i "$MGR_NAME"
}


#########
# WATCH #
#########
detect_ceph_files
bootstrap_mon
bootstrap_osd
bootstrap_mds
bootstrap_rgw
if ! grep -sq "Red Hat Enterprise Linux Server release" /etc/redhat-release; then
  bootstrap_demo_user
fi
bootstrap_rest_api
# bootstrap_nfs is temporarily disabled due to broken package dependencies with nfs-ganesha"
# For more info see: https://github.com/ceph/ceph-docker/pull/564"
#bootstrap_nfs
bootstrap_rbd_mirror
bootstrap_mgr

# create 2 files so we can later check that this is a demo container
touch /var/lib/ceph/I_AM_A_DEMO /etc/ceph/I_AM_A_DEMO

log "SUCCESS"
exec ceph "${CLI_OPTS[@]}" -w
