Demo container
==============

This Dockerfile may be used to bootstrap a Ceph cluster with all the Ceph daemons running.

**/!\ THIS CONTAINER IS NOT RECOMMENDED FOR PRODUCTION USAGE /!\**

The main purpose of this container is to quickly get a Ceph cluster up and running by reducing all the setup steps.
The container provides all the Ceph daemons, so you can rapidly start playing with Ceph.


Usage
-----

The environment variables `MON_NAME` and `MON_IP` are required:

*  `MON_NAME` is the name of the monitor (DEFAULT: hostname)
*  `MON_IP` is the IP address of the monitor (public)
*  `RGW_NAME` is the name of rados gateway instance (DEFAULT: hostname)
*  `RGW_CIVETWEB_PORT` is the port of the rados gateway (DEFAULT: 80)
*  `CLUSTER` is the name of the cluster (DEFAULT: ceph)
*  `CEPH_NETWORK` is the network where the OSD should communicate

Commonly, you will want to bind-mount your host's `/etc/ceph` into the container.
For example:

`docker run -d --net=host -v /etc/ceph:/etc/ceph -e MON_IP=192.168.0.20 -e CEPH_NETWORK=192.168.0.0/24 ceph/demo`
