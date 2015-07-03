ceph-osd
========

Run Ceph OSDs in docker

Usage
-----

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

Multiple OSDs
-------------

There is a problem when attempting run run multiple OSD containers on a single docker host.  See issue #19.

There are two workarounds, at present:
* Run each OSD with a separate IP address (e.g., use the new Docker 1.5 IPv6 support)
* Run multiple OSDs within the same container

To run multiple OSDs within the same container, simply bind-mount each OSD datastore directory:
* `docker run -v /osds/1:/var/lib/ceph/osd/ceph-1 -v /osds/2:/var/lib/ceph/osd/ceph-2`

Shared and/or separate journal
------------------------------

The default journal location for each OSD in this container (if and only if the `/var/lib/ceph/osd/journal/` directory exists) is `/var/lib/ceph/osd/journal/journal.<OSD_ID>/`.  This means that if you would like to have your journals (optionally shared) in a separate disk, all you have to do it mount that separate disk to the container's `/var/lib/ceph/osd/journal/` directory.

An easy way to have this all handled properly is to mount your journal and each OSD to their respective locations in your host's `/var/lib/ceph/osd` tree and make that entire tree available to this container by passing `-v /var/lib/ceph/osd:/var/lib/ceph/osd` to the `docker run` execution.

BTRFS and journal
-----------------

If your OSD is BTRFS and you want to use PARALLEL journal mode, you will need to run this container with `--privileged` set to true.  Otherwise, `ceph-osd` will have insufficient permissions and it will revert to the slower WRITEAHEAD mode.

Note
----

Re: [https://github.com/Ulexus/docker-ceph/issues/5]

A user has reported a consterning (and difficult to diagnose) problem wherein the OSD crashes frequently due to Docker running out of sufficient open file handles.  This is understandable, as the OSDs use a great many ports during periods of high traffic.  It is, therefore, recommended that you increase the number of open file handles available to Docker.

On CoreOS (and probably other systemd-based systems), you can do this by creating the a file named `/etc/systemd/system/docker.service.d/limits.conf` with content something like:

      [Service]
      LimitNOFILE=4096
