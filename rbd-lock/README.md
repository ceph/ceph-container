# rbd-lock

A convenience container to acquire a lock on an RBD image (or fail) and (optionally) set an etcd key with that lockid.

Make sure to pass your /etc/ceph path as a volume/bind-mount.

It uses the following environment variables, if present:

- `IMAGENAME`: this should be of the form `poolName/imageName`, and you may override this by passing the image name as the first argument
- `LOCKNAME`: this is an arbitrary text name for the lock, and you may override this by passing the lock name as the second argument. The `LOCKNAME` will default to the `HOSTNAME` of the machine.
- `ETCD_LOCKID_KEY`: this is the key name which will be set with the lock id acquired from Ceph after a successful lock.
- `ETCDCTL_PEERS` is a comma seperated list of etcd peers (e.g. `http://192.168.2.4:4001`)
- `etcdctl` is used to set the key, so any environment variable which acts upon etdctl will be honored within the execution.

Note: A lock is acquired if and only if the return value is 0. If the lock id was obtained, it will be returned as the output.

Example:

```
docker run --rm -v /etc/ceph:/etc/ceph ceph/rbd-lock myPool/myImage myLockName
```
