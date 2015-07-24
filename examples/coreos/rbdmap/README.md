Ceph RBDMAP
===========

Allows mounting ceph rbd block devices under a CoreOS host for bind-mounting to containers.

## Installing
- Copy rbdmap into /opt/sbin
- Copy ceph-rbdnaming to /opt/bin
- Copy 50-rbd.rules to /etc/udev/rules.d
