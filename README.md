docker-ceph
===========

Ceph-related dockerfiles

Components:

* [`ceph/base`](base/):  Ceph base container image.  This is nothing but a fresh install of the latest Ceph on Ubuntu LTS (14.04)
* [`ceph/mds`](mds/): Ceph MDS (Metadata server)
* [`ceph/mon`](mon/): Ceph Mon(itor)
* [`ceph/osd`](osd/): Ceph OSD (object storage daemon)
* [`ceph/rados`](rados/): Convenience wrapper to execute the `rados` CLI tool
* [`ceph/radosgw`](radosgw/): Ceph Rados gateway service; S3/swift API server
* [`ceph/rbd`](rbd/): Convenience wrapper to execute the `rbd` CLI tool
* [`ceph/config`](config/): Initializes and distributes cluster configuration
* [`ceph/docker-registry`](docker-registry/): Rados backed docker-registry images repository

