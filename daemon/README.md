Daemon container
================

This Dockerfile may be used to bootstrap a Ceph cluster with all the Ceph daemons running.


Usage
-----

You can use this container to bootstrap any Ceph daemon.

* `CEPH_DAEMON` is the name the daemon you want to deploy (DEFAULT: none). Available values: `MON`, `OSD_DIRECTORY`, `OSD_CEPH_DISK`, `MDS`, `RGW`.
* `CLUSTER` is the name of the cluster (DEFAULT: ceph)
* `HOSTNAME` is the hostname of the machine  (DEFAULT: $(hostname))


Deploy a monitor
----------------

Run:

```
$ sudo docker run -d --net=host \
-v /etc/ceph:/etc/ceph \
-v /var/lib/ceph/:/var/lib/ceph/ \
-e CEPH_DAEMON=MON \
-e MON_IP=192.168.0.20 \
-e CEPH_PUBLIC_NETWORK=192.168.0.0/24 \
ceph/daemon
```

List of available options:

* `MON_IP`: IP address of the host running Docker
* `MON_NAME`: name of the monitor (default to hostname)
* `CEPH_PUBLIC_NETWORK`: CIDR of the host running Docker, it should be in the same network as the `MON_IP`
* `CEPH_CLUSTER_NETWORK`: CIDR of a secondary interface of the host running Docker. Used for the OSD replication traffic


Deploy an OSD
-------------

There are two available options:

* use `OSD_CEPH_DISK` where you only specify a block device
* use `OSD_DIRECTORY` where you specify an OSD mount point to your container


### Ceph disk ###

```
$ sudo docker run -d --net=host \
--privileged=true \
-v /etc/ceph:/etc/ceph \
-v /var/lib/ceph/:/var/lib/ceph/ \
-v /dev/:/dev/ \
-e CEPH_DAEMON=OSD \
-e OSD_DEVICE=/dev/vdd \
ceph/daemon
```

List of available options:

* `OSD_DEVICE`:
* `OSD_JOURNAL`:
* `HOSTNAME`:

If you do not want to use `--privileged=true`, please fall back on the second example.


### Ceph OSD directory ###

There are a number of environment variables which are used to configure
the execution of the OSD:

 -  `CLUSTER` is the name of the ceph cluster (defaults to `ceph`)

If the OSD is not already created (key, configuration, OSD data), the
following environment variables will control its creation:

 -  `WEIGHT` is the of the OSD when it is added to the CRUSH map (default is `1.0`)
 -  `JOURNAL` is the location of the journal (default is the `journal` file inside the OSD data directory)
 -  `HOSTNAME` is the name of the host; it is used as a flag when adding the OSD to the CRUSH map

The old option `OSD_ID` is now unused.  Instead, the script will scan for each directory in `/var/lib/ceph/osd` of the form `<cluster>-<osd-id>`.

To create your OSDs simply run the following command:

`docker exec <mon-container-id> ceph osd create`.


#### Multiple OSDs ####

There is a problem when attempting run run multiple OSD containers on a single docker host.  See issue #19.

There are two workarounds, at present:
* Run each OSD with a separate IP address (e.g., use the new Docker 1.5 IPv6 support)
* Run multiple OSDs within the same container

To run multiple OSDs within the same container, simply bind-mount each OSD datastore directory:
* `docker run -v /osds/1:/var/lib/ceph/osd/ceph-1 -v /osds/2:/var/lib/ceph/osd/ceph-2`


#### BTRFS and journal ####

If your OSD is BTRFS and you want to use PARALLEL journal mode, you will need to run this container with `--privileged` set to true.  Otherwise, `ceph-osd` will have insufficient permissions and it will revert to the slower WRITEAHEAD mode.


#### Note ####

Re: [https://github.com/Ulexus/docker-ceph/issues/5]

A user has reported a consterning (and difficult to diagnose) problem wherein the OSD crashes frequently due to Docker running out of sufficient open file handles.  This is understandable, as the OSDs use a great many ports during periods of high traffic.  It is, therefore, recommended that you increase the number of open file handles available to Docker.

On CoreOS (and probably other systemd-based systems), you can do this by creating the a file named `/etc/systemd/system/docker.service.d/limits.conf` with content something like:

      [Service]
      LimitNOFILE=4096


Deploy a MDS
------------

By default, the MDS does _NOT_ create a ceph filesystem.  If you wish to have this MDS create a ceph filesystem (it will only do this if the specified `CEPHFS_NAME` does not already exist), you _must_ set, at a minimum, `CEPHFS_CREATE=1`.  It is strongly recommended that you read the rest of this section, as well.

For most people, the defaults for the following optional environment variables are fine, but if you wish to customize the data and metadata pools in which your CephFS is stored, you may override the following as you wish:

  * `CEPHFS_CREATE`: Whether to create the ceph filesystem (0 = no / 1 = yes), if it doesn't exist.  Defaults to 0 (no)
  * `CEPHFS_NAME`: The name of the new ceph filesystem and the basis on which the later variables are created.  Defaults to `cephfs`
  * `CEPHFS_DATA_POOL`:  The name of the data pool for the ceph filesystem.  If it does not exist, it will be created.  Defaults to `${CEPHFS_NAME}_data`
  * `CEPHFS_DATA_POOL_PG`:  The number of placement groups for the data pool.  Defaults to `8`
  * `CEPHFS_METADATA_POOL`:  The name of the metadata pool for the ceph filesystem.  If it does not exist, it will be created.  Defaults to `${CEPHFS_NAME}_metadata`
  * `CEPHFS_METADATA_POOL_PG`:  The number of placement groups for the metadata pool.  Defaults to `8`

Run:

```
$ sudo docker run -d --net=host \
-v /var/lib/ceph/:/var/lib/ceph/ \
-v /etc/ceph:/etc/ceph \
-e CEPH_DAEMON=MDS \
-e CEPHFS_CREATE=1 \
ceph/daemon
```

List of available options:

* `MDS_NAME` is the name the MDS server (DEFAULT: $(hostname))


Deploy a Rados Gateway
----------------------

For the Rados Gateway, we deploy it with `civetweb` enabled by default.
However it is possible to use different CGI frontends by simply giving remote address and port.

```
$ sudo docker run -d --net=host \
-v /var/lib/ceph/:/var/lib/ceph/ \
-v /etc/ceph:/etc/ceph \
-e CEPH_DAEMON=RGW \
ceph/daemon
```

List of available options:

* `RGW_CIVETWEB_PORT` is the port to which civetweb is listening on (DEFAULT: 80)
* `RGW_NAME`: default to hostname

To enable an external CGI interface instead of civetweb set:

* `RGW_REMOTE_CGI=1`
* `RGW_REMOTE_CGI_HOST=192.168.0.1`
* `RGW_REMOTE_CGI_PORT=9000`

And run the container like this `docker run -d -v /etc/ceph:/etc/ceph -v /var/lib/ceph/:/var/lib/ceph -e CEPH_DAEMON=RGW -e RGW_NAME=myrgw -p 9000:9000 -e RGW_REMOTE_CGI=1 -e RGW_REMOTE_CGI_HOST=192.168.0.1 -e RGW_REMOTE_CGI_PORT=9000 ceph/daemon`
