Ceph RBDMAP
===========

Allows mounting ceph rbd block devices under a CoreOS host for bind-mounting to containers.

## Installing
- Copy rbdmap into /opt/sbin
- Copy ceph-rbdnamer to /opt/bin
- Copy 50-rbd.rules to /etc/udev/rules.d

## Usage
1. Add rbd device to /etc/ceph/rbdmap

e.g.

```
  #poolname/imagename id=client,keyring=ceph.client.admin.keyring
  rbd/mysql id=admin,keyring=/etc/ceph/ceph.client.admin.keyring
```

2. Add mount directory to /etc/fstab

e.g.

```
  /dev/rbd/poolname/imagename mountpoint fstype mount-options 0 0
  /dev/rbd/rbd/mariadb1	/data/mariadb1 ext4	noatime,_netdev	0 0
```

Note: ensure the _netdev option is specified in the mount options.

```
_netdev
    The filesystem resides on a device that requires network access (used to prevent
    the system from attempting to mount these filesystems until the network has been
    enabled on the system).
```
