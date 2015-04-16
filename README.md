docker-ceph
===========

Ceph-related dockerfiles

## Core Components:

* [`ceph/base`](base/):  Ceph base container image.  This is nothing but a fresh install of the latest Ceph on Ubuntu LTS (14.04)
* [`ceph/mds`](mds/): Ceph MDS (Metadata server)
* [`ceph/mon`](mon/): Ceph Mon(itor)
* [`ceph/osd`](osd/): Ceph OSD (object storage daemon)
* [`ceph/radosgw`](radosgw/): Ceph Rados gateway service; S3/swift API server

## Utilities and convenience wrappers

* [`ceph/config`](config/): Initializes and distributes cluster configuration
* [`ceph/docker-registry`](docker-registry/): Rados backed docker-registry images repository
* [`ceph/rados`](rados/): Convenience wrapper to execute the `rados` CLI tool
* [`ceph/rbd`](rbd/): Convenience wrapper to execute the `rbd` CLI tool
* [`ceph/rbd-lock`](rbd-lock/): Convenience wrapper to block waiting for an rbd lock
* [`ceph/rbd-unlock`](rbd-unlock/): Convenience wrapper to release an rbd lock
* [`ceph/rbd-volume`](rbd-volume/): Convenience wrapper to mount an rbd volume

## Demo

* [`ceph/demo`](demo/): Demonstration cluster for testing and learning.  This container runs all the major ceph components, bootstrapped for you to play with.  (not intended for use in building a production cluster)
