#!/bin/bash
set -e

: ${RBD_IMAGE:=image0}
: ${RBD_POOL:=rbd}
: ${RBD_OPTS:=rw}
: ${RBD_FS:=xfs}
: ${RBD_TARGET:=/mnt/rbd}

# Map the rbd volume
function map {
	/usr/bin/rbd map ${RBD_IMAGE} --pool ${RBD_POOL} -o ${RBD_OPTS}
}

# Mount and wait for exit signal (after which, unmount and exit)
function mount {
	RBD_DEV=$1

	if [ -z $1 ]; then
		read RBD_DEV
	fi

	/mountWait -rbddev ${RBD_DEV} -fstype ${RBD_FS} -target ${RBD_TARGET} -o ${RBD_OPTS}
}

# Unmap rbd device
function unmap {
	/usr/bin/rbd unmap $( /usr/bin/rbd showmapped | grep -m 1 -E "^[0-9]{1,3}\s+${RBD_POOL}\s+${RBD_IMAGE}" | awk '{print $5}' )
}

case "$@" in
	"map" ) map;;
	"mount" ) mount;;
	"unmap" ) unmap;;
	* ) 
	RBD_DEV=$(map)
	mount $RBD_DEV
	;;
esac

