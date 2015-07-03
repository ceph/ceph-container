ceph-mon
========

This Dockerfile may be used to bootstrap a Ceph cluster or add a mon to an existing cluster.


Usage
-----

Environment variables:

*  `MON_NAME` is the name of the monitor (defaults to `hostname -s`)
*  `MON_IP` is the IP address of the monitor (public) (required, if not using autodetection)
*  `MON_IP_AUTO_DETECT`: Whether and how to attempt IP autodetection.  
    *  0 = Do not detect (default)
    *  1 = Detect IPv6, fallback to IPv4 (if no globally-routable IPv6 address detected)
    *  4 = Detect IPv4 only
    *  6 = Detect IPv6 only

For example:
`docker run -e MON_IP=192.168.101.50 -e MON_NAME=mymon ceph/mon`

If you have an existing Ceph cluster and are only looking to add a monitor, you will need at least four files in `/etc/ceph`:
*  `ceph.conf` - The main ceph configuration file, which may be obtained from an existing ceph monitor
*  `ceph.client.admin.keyring` - The administrator key of the cluster, which may be obtained from an existing ceph monitor by `ceph auth get client.admin -o /tmp/ceph.client.admin.keyring`
*  `ceph.mon.keyring` - The monitor key, which may be obtained from an existinv ceph monitor by `ceph auth get mon. -o /tmp/ceph.mon.keyring`
*  `monmap` - The present monitor map of the cluster, which may be obtained from an existing ceph monitor by `ceph mon getmap -o /tmp/monmap`

Otherwise, if you are bootstrapping a new cluster, these will be generated for you.

Commonly, you will want to bind-mount your host's `/etc/ceph` into the container.  For example:
`docker run -e MON_IP=192.168.101.50 -e MON_NAME=mymon -v /etc/ceph:/etc/ceph ceph/mon`

