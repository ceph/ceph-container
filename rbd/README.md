# rbd

A convenience container to execute ceph rbd for block device manipulation

Make sure to pass your /etc/ceph path as a volume/bind-mount.

Example:

```
docker run -v /etc/ceph:/etc/ceph ceph/rbd -p vms ls
```
