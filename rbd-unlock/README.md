# rbd-unlock

A convenience container to release a lock on an RBD image

Make sure to pass your /etc/ceph path as a volume/bind-mount.

It uses the following environment variables, if present:

- `IMAGENAME`: this should be of the form `poolName/imageName`, and you may override this by passing the image name as the first argument
- `LOCKNAME`: this is name of the lock, and you may override this by passing the lock name as the second argument. The `LOCKNAME` will default to the `HOSTNAME` of the machine.
- `LOCKID`: this is the id of the lock, and you may override this by passing the lock id as the third argument.
- `ETCD_LOCKID_KEY`: this is the key name from where the `LOCKID` should be read (thus obviating and overriding `LOCKID`)
- `ETCDCTL_PEERS` is a comma seperated list of etcd peers (e.g. <http://192.168.2.4:4001>)
- `etcdctl` is used to get the key, so any environment variable which acts upon etdctl will be honored within the execution.

Example:

```
docker run --rm -v /etc/ceph:/etc/ceph ceph/rbd-unlock myPool/myImage myLockName lockId
```
