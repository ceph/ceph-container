#!/bin/sh
#  borrowed from ceph-docker/examples/coreos/tools
set -e

checksum()
{
	md5sum $1 | awk '{print $1}'
}

mkdir -p /opt/bin/

for UTIL in ceph rbd ceph-rbdnamer rados ceph-disk; do

    if [ ! -e /opt/bin/$UTIL ] || [ "$(checksum /opt/bin/$UTIL)" != "$(checksum /$UTIL)" ]; then
    	echo "Installing $UTIL to /opt/bin"
    	cp -pf /$UTIL /opt/bin/
    fi

done

if [ ! -e /etc/udev/rules.d/50-rbd.rules ] || [ "$(checksum /etc/udev/rules.d/50-rbd.rules)" != "$(checksum /50-rbd.rules)" ]; then
    echo "Installing 50-rbd.rules to /etc/udev/rules.d/"
    cp -pf /50-rbd.rules /etc/udev/rules.d/
fi

#  there's no current way to have a daemon set that is 'run once per node' so we'll have it sleep forever
echo "Begin sleep of 30 days"
while true; do sleep 30d; done
