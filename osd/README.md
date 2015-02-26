ceph-osd
========

Run Ceph OSDs in docker

Usage
-----

There are a number of environment variables which are used to configure
the execution of the OSD:

 -  `CLUSTER` is the name of the ceph cluster (defaults to `ceph`)
 -  `OSD_ID` is the (numeric) id of this OSD; if you don't have one, you can execute `ceph osd create` from another working node (such as a monitor).  There is no default, and this variable is REQUIRED.

If the OSD is not already created (key, configuration, OSD data), the
following environment variables will control its creation:

 -  `WEIGHT` is the of the OSD when it is added to the CRUSH map (default is `1.0`)
 -  `JOURNAL` is the location of the journal (default is the `journal` file inside the OSD data directory)
 -  `HOSTNAME` is the name of the host; it is used as a flag when adding the OSD to the CRUSH map


## BTRFS and journal

If your OSD is BTRFS and you want to use PARALLEL journal mode, you will need to run this container with `--privileged` set to true.  Otherwise, `ceph-osd` will have insufficient permissions and it will revert to the slower WRITEAHEAD mode.

Note
----

Re: [https://github.com/Ulexus/docker-ceph/issues/5]

A user has reported a consterning (and difficult to diagnose) problem wherein the OSD crashes frequently due to Docker running out of sufficient open file handles.  This is understandable, as the OSDs use a great many ports during periods of high traffic.  It is, therefore, recommended that you increase the number of open file handles available to Docker.

On CoreOS (and probably other systemd-based systems), you can do this by creating the a file named `/etc/systemd/system/docker.service.d/limits.conf` with content something like:

      [Service]
      LimitNOFILE=4096


