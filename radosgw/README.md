ceph-rgw
========

This Dockerfile creates a Ceph RADOS gateway server (RGW) image


Usage
-----

The environment variable `RGW_NAME` is required.  It describes the name of the RGW

For example:
`docker run -e RGW_NAME=myrgw ceph/radosgw`

It will look for `/etc/ceph/ceph.client.admin.keyring` with which to authenticate.  You can get `ceph.client.admin.keyring` from another Ceph node.

Commonly, you will want to bind-mount your host's `/etc/ceph` into the container.  For example:
`docker run -d --net=host -e RGW_NAME=myrgw -v /etc/ceph:/etc/ceph ceph/radosgw`
