#!/bin/bash
set -e

IMAGENAME=${1:-${IMAGENAME}}
LOCKNAME=${2:-${HOSTNAME}}

# ETCDCTL_PEERS - a comma-delimited list of machine addresses in the cluster (default: "127.0.0.1:4001")
: ${ETCDCTL_PEERS:=127.0.0.1:4001}

function usage() {
   echo "$0 <pool/image> [lockName]"
   exit 255
}

# Make sure the image name is set
if [ ! -n "$IMAGENAME" ]; then
   usage
fi

# Make sure the lock name is set
if [ ! -n "$LOCKNAME" ]; then
   usage
fi

# Attempt to acquire a lock
rbd lock add $IMAGENAME $LOCKNAME
if [ $? -ne 0 ]; then
   echo "Failed to acquire lock"
   exit 1
fi

LOCKID=$(rbd lock list $IMAGENAME | grep $LOCKNAME | cut -f1 -d' ')
if [ ! -n "$LOCKID" ]; then
   # We return 0 here to indicate a lock was acquired,
   # but we cannot proceed because we failed to get
   # the lock id.  Hence, we return nothing for the
   # lock id.
   exit 0
fi

# If we were given an ETCD key for lockid storage, get the lockid and store it
if [ -n "$ETCD_LOCKID_KEY" ]; then
   etcdctl -C ${ETCDCTL_PEERS} --no-sync set $ETCD_LOCKID_KEY $LOCKID
fi

echo $LOCKID
exit 0
