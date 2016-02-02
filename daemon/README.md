Daemon container
================

This Dockerfile may be used to bootstrap a Ceph cluster with all the Ceph daemons running.
To run a certain type of daemon, simply use the name of the daemon as `$1`.
Valid values are:

* `mon` deploys a Ceph monitor
* `osd` deploys an OSD using the method specified by `OSD_TYPE`
* `osd_directory` deploys an OSD using a prepared directory (used in scenario where the operator doesn't want to use `--privileged=true`)
* `osd_ceph_disk` deploys an OSD using ceph-disk, so you have to provide a whole device (ie: /dev/sdb)
* `mds` deploys a MDS
* `rgw` deploys a Rados Gateway


Usage
-----

You can use this container to bootstrap any Ceph daemon.

* `CLUSTER` is the name of the cluster (DEFAULT: ceph)
* `HOSTNAME` is the hostname of the machine  (DEFAULT: $(hostname))


SELinux
-------

If SELinux is enabled, run the following commands:

```
$ sudo chcon -Rt svirt_sandbox_file_t /etc/ceph
$ sudo chcon -Rt svirt_sandbox_file_t /var/lib/ceph
```

KV backends
-----------

We currently support 2 KV backends to store our configuration flags, keys and maps:

* etcd
* consul

There is a `ceph.defaults` config file in the image that is used for defaults to bootstrap daemons. 
It will add the keys if they are not already present.
You can either pre-populate the KV store with your own settings, or provide a ceph.defaults config file 
To supply your own defaults, make sure to mount the /etc/ceph/ volume and place your ceph.defaults file there.

Important variables in `ceph.defaults` to add/change when you bootstrap an OSD:

* `/osd/journal_size`
* `/osd/cluster_network`
* `/osd/public_network`

Note: `cluster_network` and `public_network` are currently not populated in the defaults, but can be passed as environment 
variables with `-e CEPH_PUBLIC_NETWORK=...` for more flexibility

Populate Key Value store
------------------------

```
$ sudo docker run -d --net=host \
-e KV_TYPE=etcd \
-e KV_IP=127.0.0.1 \
-e KV_PORT=4001 \
ceph/daemon populate_kvstore
```

Deploy a monitor
----------------

Without KV store, run:

```
$ sudo docker run -d --net=host \
-v /etc/ceph:/etc/ceph \
-v /var/lib/ceph/:/var/lib/ceph/ \
-e MON_IP=192.168.0.20 \
-e CEPH_PUBLIC_NETWORK=192.168.0.0/24 \
ceph/daemon mon
```

With KV store, run:

```
$ sudo docker run -d --net=host \
-e MON_IP=192.168.0.20 \
-e CEPH_PUBLIC_NETWORK=192.168.0.0/24 \
-e KV_TYPE=etcd \
-e KV_IP=192.168.0.20 \
ceph/daemon mon
```

List of available options:

* `MON_NAME`: name of the monitor (default to hostname)
* `CEPH_PUBLIC_NETWORK`: CIDR of the host running Docker, it should be in the same network as the `MON_IP`
* `CEPH_CLUSTER_NETWORK`: CIDR of a secondary interface of the host running Docker. Used for the OSD replication traffic
* `MON_IP`: IP address of the host running Docker
* `NETWORK_AUTO_DETECT`: Whether and how to attempt IP and network autodetection. Meant to be used without `--net=host`.
    *  0 = Do not detect (default)
    *  1 = Detect IPv6, fallback to IPv4 (if no globally-routable IPv6 address detected)
    *  4 = Detect IPv4 only
    *  6 = Detect IPv6 only


Deploy an OSD
-------------

There are four available `OSD_TYPE` values:

* `<none>` - if no `OSD_TYPE` is set; one of `disk`, `activate` or `directory` will be used based on autodetection of the current OSD bootstrap state
* `activate` - the daemon expects to be passed a block device of a `ceph-disk`-prepared disk (via the `OSD_DEVICE` environment variable); no bootstrapping will be performed
* `directory` - the daemon expects to find the OSD filesystem(s) already mounted in `/var/lib/ceph/osd/`
* `disk` - the daemon expects to be passed a block device via the `OSD_DEVICE` environment variable

Options for OSDs (TODO: consolidate these options between the types):
* `JOURNAL_DIR` - if provided, new OSDs will be bootstrapped to use the specified directory as a common journal area.  This is usually used to store the journals for more than one OSD on a common, separate disk.  This currently only applies to the `directory` OSD type.
* `JOURNAL` - if provided, the new OSD will be bootstrapped to use the specified journal file (if you do not wish to use the default).  This is currently only supported by the `directory` OSD type
* `OSD_DEVICE` - mandatory for `activate` and `disk` OSD types; this specifies which block device to use as the OSD
* `OSD_JOURNAL` - optional override of the OSD journal file. this only applies to the `activate` and `disk` OSD types

### Without OSD_TYPE ###

If the operator does not specify an `OSD_TYPE` autodetection happens:
- `disk` is used if no bootstrapped OSD is found. `OSD_FORCE_ZAP=1` must be set at this point.
- `activate` is used if a bootstrapped OSD is found and `OSD_DEVICE` is also provided.
- `directory` is used if a bootstrapped OSD is found and no `OSD_DEVICE` is provided.

Without KV backend:
```
$ sudo docker run -d --net=host \
--pid=host \
--privileged=true \
-v /etc/ceph:/etc/ceph \
-v /var/lib/ceph/:/var/lib/ceph/ \
-v /dev/:/dev/ \
-e OSD_DEVICE=/dev/vdd \
-e OSD_FORCE_ZAP=1 \
ceph/daemon osd
```

With KV backend:
```
$ sudo docker run -d --net=host \
--privileged=true \
--pid=host \
-v /dev/:/dev/ \
-e OSD_DEVICE=/dev/vdd \
-e OSD_FORCE_ZAP=1 \
-e KV_TYPE=etcd \
-e KV_IP=192.168.0.20 \
ceph/daemon osd
```

### Ceph disk ###

Without KV backend:

```
$ sudo docker run -d --net=host \
--privileged=true \
--pid=host \
-v /etc/ceph:/etc/ceph \
-v /var/lib/ceph/:/var/lib/ceph/ \
-v /dev/:/dev/ \
-e OSD_DEVICE=/dev/vdd \
-e OSD_TYPE=disk \
ceph/daemon osd
```

With KV backend:

```
$ sudo docker run -d --net=host \
--privileged=true \
--pid=host \
-v /dev/:/dev/ \
-e OSD_DEVICE=/dev/vdd \
-e OSD_TYPE=disk \
-e KV_TYPE=etcd \
-e KV_IP=192.168.0.20 \
ceph/daemon osd
```

List of available options:

* `OSD_DEVICE` is the OSD device
* `OSD_JOURNAL` is the journal for a given OSD
* `HOSTNAME` is used to place the OSD in the CRUSH map

If you do not want to use `--privileged=true`, please fall back on the second example.


### Ceph disk activate ###

This function is balance between ceph-disk and osd directory where the operator can use ceph-disk outside of the container (directly on the host) to prepare the devices.
Devices will be prepared with `ceph-disk prepare`, then they will get activated inside the container.
A priviledged container is still required as ceph-disk needs to access /dev/.
So this has minimum value compare to the ceph-disk but might fit some use cases where the operators want to prepare their devices outside of a container.

```
$ sudo docker run -d --net=host \
--privileged=true \
--pid=host \
-v /etc/ceph:/etc/ceph \
-v /var/lib/ceph/:/var/lib/ceph/ \
-v /dev/:/dev/ \
-e OSD_DEVICE=/dev/vdd \
-e OSD_TYPE=activate \
ceph/daemon osd
```


### Ceph OSD directory ###

There are a number of environment variables which are used to configure
the execution of the OSD:

*  `CLUSTER` is the name of the ceph cluster (defaults to `ceph`)

If the OSD is not already created (key, configuration, OSD data), the
following environment variables will control its creation:

* `WEIGHT` is the of the OSD when it is added to the CRUSH map (default is `1.0`)
* `JOURNAL` is the location of the journal (default is the `journal` file inside the OSD data directory)
* `HOSTNAME` is the name of the host; it is used as a flag when adding the OSD to the CRUSH map

The old option `OSD_ID` is now unused.  Instead, the script will scan for each directory in `/var/lib/ceph/osd` of the form `<cluster>-<osd-id>`.

To create your OSDs simply run the following command:

`docker exec <mon-container-id> ceph osd create`.

Note that we now default to dropping root privileges, so it is important to set the proper ownership for your OSD directories.  The Ceph OSD runs as UID:64045, GID:64045, so:

`chown -R 64045:64045 /var/lib/ceph/osd/*`


#### Multiple OSDs ####

There is a problem when attempting run run multiple OSD containers on a single docker host.  See issue #19.

There are two workarounds, at present:
* Run each OSD with the `--pid=host` option
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

Without KV backend, run:

```
$ sudo docker run -d --net=host \
-v /var/lib/ceph/:/var/lib/ceph/ \
-v /etc/ceph:/etc/ceph \
-e CEPHFS_CREATE=1 \
ceph/daemon mds
```

With KV backend, run:

```
$ sudo docker run -d --net=host \
-e CEPHFS_CREATE=1 \
-e KV_TYPE=etcd \
-e KV_IP=192.168.0.20 \
ceph/daemon mds
```

List of available options:

* `MDS_NAME` is the name the MDS server (DEFAULT: mds-$(hostname)).
One thing to note is that metadata servers are not machine-restricted.
They are not bound by their data directories and can move around the cluster.
As a result, you can run more than one MDS on a single machine.
If you plan to do so, you better set this variable and do something like: `mds-$(hostname)-a`, `mds-$(hostname)-b`etc...


Deploy a Rados Gateway
----------------------

For the Rados Gateway, we deploy it with `civetweb` enabled by default.
However it is possible to use different CGI frontends by simply giving remote address and port.

Without kv backend, run:

```
$ sudo docker run -d --net=host \
-v /var/lib/ceph/:/var/lib/ceph/ \
-v /etc/ceph:/etc/ceph \
ceph/daemon rgw
```

With kv backend, run:

```
$ sudo docker run -d --net=host \
-e KV_TYPE=etcd \
-e KV_IP=192.168.0.20 \
ceph/daemon rgw
```

List of available options:

* `RGW_CIVETWEB_PORT` is the port to which civetweb is listening on (DEFAULT: 80)
* `RGW_NAME`: default to hostname

Administration via [radosgw-admin](http://docs.ceph.com/docs/infernalis/man/8/radosgw-admin/) from the Docker host if the `RGW_NAME` variable hasn't been supplied:

`docker exec <containerId> radosgw-admin -n client.rgw.$(hostname) -k /var/lib/ceph/radosgw/$(hostname)/keyring <commands>`

If otherwise, `$(hostname)`  has to be replaced by the value of `RGW_NAME`.

To enable an external CGI interface instead of civetweb set:

* `RGW_REMOTE_CGI=1`
* `RGW_REMOTE_CGI_HOST=192.168.0.1`
* `RGW_REMOTE_CGI_PORT=9000`

And run the container like this `docker run -d -v /etc/ceph:/etc/ceph -v /var/lib/ceph/:/var/lib/ceph -e CEPH_DAEMON=RGW -e RGW_NAME=myrgw -p 9000:9000 -e RGW_REMOTE_CGI=1 -e RGW_REMOTE_CGI_HOST=192.168.0.1 -e RGW_REMOTE_CGI_PORT=9000 ceph/daemon`

Deploy a REST API
-----------------

This is pretty straighforward. The `--net=host` is not mandatory, if you don't use it do not forget to expose the `RESTAPI_PORT`.

```
$ sudo docker run -d --net=host \
-e KV_TYPE=etcd \
-e KV_IP=192.168.0.20 \
ceph/daemon restapi
```

List of available options:

* `RESTAPI_IP` is the IP address to listen on (DEFAULT: 0.0.0.0)
* `RESTAPI_PORT` is the listening port of the REST API (DEFAULT: 5000)
* `RESTAPI_BASE_URL` is the base URL of the API (DEFAULT: /api/v0.1)
* `RESTAPI_LOG_LEVEL` is the log level of the API (DEFAULT: warning)
* `RESTAPI_LOG_FILE` is the location of the log file (DEFAULT: /var/log/ceph/ceph-restapi.log)
