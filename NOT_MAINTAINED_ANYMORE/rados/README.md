# rados

A convenience container to execute ceph rados for object manipulation.

Make sure to pass your /etc/ceph path as a volume/bind-mount.

Example:

```
docker run -v /etc/ceph:/etc/ceph ceph/rados lspools
```
