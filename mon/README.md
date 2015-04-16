ceph-mon
========

This Dockerfile may be used to bootstrap a Ceph cluster or add a mon to an existing cluster.


Usage
-----

The environment variables `MON_NAME` and `MON_IP` are required:

*  `MON_NAME` is the name of the monitor
*  `MON_IP` is the IP address of the monitor (public) . If you are using container network set it to container.

For example:
`docker run --net="host" -e MON_IP=192.168.101.50 -e MON_NAME=mymon ceph/mon`
`docker run --net="container" -e MON_IP=container -e MON_NAME=mymon -p 6789:6789 ceph/mon`


If you have an existing Ceph cluster and are only looking to add a monitor, you will need at least four files in `/etc/ceph`:
*  `ceph.conf` - The main ceph configuration file, which may be obtained from an existing ceph monitor
*  `ceph.client.admin.keyring` - The administrator key of the cluster, which may be obtained from an existing ceph monitor by `ceph auth get client.admin -o /tmp/ceph.client.admin.keyring`
*  `ceph.mon.keyring` - The monitor key, which may be obtained from an existinv ceph monitor by `ceph auth get mon. -o /tmp/ceph.mon.keyring`
*  `monmap` - The present monitor map of the cluster, which may be obtained from an existing ceph monitor by `ceph mon getmap -o /tmp/monmap`

Otherwise, if you are bootstrapping a new cluster, these will be generated for you.

Commonly, you will want to bind-mount your host's `/etc/ceph` into the container.  For example:
`docker run -e MON_IP=192.168.101.50 -e MON_NAME=mymon -v /etc/ceph:/etc/ceph ceph/mon`
