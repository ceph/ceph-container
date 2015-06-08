ceph-mds
========

This Dockerfile creates a Ceph metadata server (MDS) image


Usage
-----

The environment variable `MDS_NAME` is required.  It describes the name of the MDS

For example:
`docker run -e MDS_NAME=mymds ceph/mds`

It will look for either `/etc/ceph/ceph.client.admin.keyring` or `/etc/ceph/ceph.mds.keyring` with which to authenticate.  You can get `ceph.client.admin.keyring` from another ceph node.

Commonly, you will want to bind-mount your host's `/etc/ceph` into the container.  For example:
`docker run -e MDS_NAME=mymds -v /etc/ceph:/etc/ceph ceph/mds`

CephFS
------

By default, the MDS does _NOT_ create a ceph filesystem.  If you wish to have this MDS create a ceph filesystem (it will only do this if the specified `CEPHFS_NAME` does not already exist), you _must_ set, at a minimum, `CEPHFS_CREATE=1`.  It is strongly recommended that you read the rest of this section, as well.

For most people, the defaults for the following optional environment variables are fine, but if you wish to customize the data and metadata pools in which your CephFS is stored, you may override the following as you wish:

  * `CEPHFS_CREATE`: Whether to create the ceph filesystem (0 = no / 1 = yes), if it doesn't exist.  Defaults to 0 (no)
  * `CEPHFS_NAME`: The name of the new ceph filesystem and the basis on which the later variables are created.  Defaults to `cephfs`
  * `CEPHFS_DATA_POOL`:  The name of the data pool for the ceph filesystem.  If it does not exist, it will be created.  Defaults to `${CEPHFS_NAME}_data`
  * `CEPHFS_DATA_POOL_PG`:  The number of placement groups for the data pool.  Defaults to `8`
  * `CEPHFS_METADATA_POOL`:  The name of the metadata pool for the ceph filesystem.  If it does not exist, it will be created.  Defaults to `${CEPHFS_NAME}_metadata`
  * `CEPHFS_METADATA_POOL_PG`:  The number of placement groups for the metadata pool.  Defaults to `8`

Miscellany
----------

`ceph/mds` seems to die _most_ of the time when trying to start it.  Trying repeatedly will eventually get it to run.  If run _manually_ within the container (enrtypoint to base, then manually run entrypoint.sh), it fails _less_ often, but still frequently (though less than 50% of the time).
