#!/bin/bash
set -e

: ${RBD_IMAGE:=image0}
: ${RBD_POOL:=rbd}

# Get rbd device
MOUNT_DEV=$( /usr/bin/rbd showmapped | grep -m 1 -E "^[0-9]{1,3}\s+${RBD_POOL}\s+${RBD_IMAGE}" | awk '{print $5}' )

#Unmap rbd device
/usr/bin/rbd unmap ${MOUNT_DEV}
