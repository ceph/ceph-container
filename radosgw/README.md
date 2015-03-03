ceph-rgw
========

This Dockerfile creates a Ceph RADOS gateway server (RGW) image
Both external CGI interface and civetweb are supported.
However civetweb is preferred so it's enabled by default.

Usage
-----

The environment variable `RGW_NAME` is required.  It describes the name of the RGW

For example:
`docker run -e RGW_NAME=myrgw ceph/radosgw`

It will look for `/etc/ceph/ceph.client.admin.keyring` with which to authenticate.  You can get `ceph.client.admin.keyring` from another Ceph node.

Commonly, you will want to bind-mount your host's `/etc/ceph` into the container.  For example:
`docker run -d -p 80:80 -e RGW_NAME=myrgw -v /etc/ceph:/etc/ceph ceph/radosgw`

To enable an external CGI interface instead of civetweb set:

* `RGW_REMOTE_CGI=1`
* `RGW_REMOTE_CGI_HOST=192.168.0.1`
* `RGW_REMOTE_CGI_PORT=9000`

And run the container like this `docker run -d -e RGW_NAME=myrgw -p 9000:9000 -e RGW_REMOTE_CGI=1 -e RGW_REMOTE_CGI_HOST=192.168.0.1 -e RGW_REMOTE_CGI_PORT=9000 -v /etc/ceph:/etc/ceph ceph/radosgw

To change the civetweb port binding set `RGW_CIVETWEB_PORT=8080`.
