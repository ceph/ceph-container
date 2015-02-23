#!/bin/bash
set -e

: ${RBD_IMAGE:=image0}
: ${RBD_POOL:=rbd}
: ${RBD_OPTS:=rw}
: ${RBD_FS:=xfs}
: ${RBD_TARGET:=/mnt/rbd}

# Make sure the mountpoint exists
mkdir -p ${RBD_TARGET}

# Make sure the rbd module is loaded
/sbin/modprobe rbd

# Map the rbd volume
/usr/bin/rbd map ${RBD_IMAGE} --pool ${RBD_POOL} -o ${RBD_OPTS}

# Mount and wait for exit signal (after which, unmount and exit)
/mountWait -image ${RBD_IMAGE} -pool ${RBD_POOL} -fstype ${RBD_FS} -target ${RBD_TARGET}

