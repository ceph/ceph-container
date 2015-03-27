#!/bin/bash
set -e

: ${RBD_IMAGE:=image0}
: ${RBD_POOL:=rbd}
: ${RBD_OPTS:=rw}
: ${RBD_FS:=xfs}
: ${RBD_TARGET:=/mnt/rbd}

MOUNT_OPTIONS=''

if [ "$RBD_OPTS" == "ro" ]; then
	MOUNT_OPTIONS="-r ${MOUNT_OPTIONS}"
fi

# Make sure the mountpoint exists
mkdir -p ${RBD_TARGET}

# Make sure the rbd module is loaded
/sbin/modprobe rbd

# Map the rbd volume
/usr/bin/rbd map ${RBD_IMAGE} --pool ${RBD_POOL} -o ${RBD_OPTS}

# Get rbd device
MOUNT_DEV=$( /usr/bin/rbd showmapped | grep -m 1 -E "^[0-9]{1,3}\s+${RBD_POOL}\s+${RBD_IMAGE}" | awk '{print $5}' )

# Mount and wait for exit signal (after which, unmount and exit)
/mountWait -rbddev ${MOUNT_DEV} -fstype ${RBD_FS} -target ${RBD_TARGET} ${MOUNT_OPTIONS}

