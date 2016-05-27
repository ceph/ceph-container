docker-ceph
===========

Ceph-related dockerfiles

## Core Components:

* [`ceph/base`](base/):  Ceph base container image.  This is nothing but a fresh install of the latest Ceph on Ubuntu LTS (14.04)
* [`ceph/daemon`](daemon/): All-in-one container for all core daemons.
* [`ceph/mds`](mds/): _DEPRECATED (use `daemon`)_ Ceph MDS (Metadata server)
* [`ceph/mon`](mon/): _DEPRECATED (use `daemon`)_ Ceph Mon(itor)
* [`ceph/osd`](osd/): _DEPRECATED (use `daemon`)_ Ceph OSD (object storage daemon)
* [`ceph/radosgw`](radosgw/): _DEPRECATED (use `daemon`)_ Ceph Rados gateway service; S3/swift API server

## Utilities and convenience wrappers

* [`ceph/config`](config/): Initializes and distributes cluster configuration
* [`ceph/docker-registry`](docker-registry/): Rados backed docker-registry images repository
* [`ceph/rados`](rados/): Convenience wrapper to execute the `rados` CLI tool
* [`ceph/rbd`](rbd/): Convenience wrapper to execute the `rbd` CLI tool
* [`ceph/rbd-lock`](rbd-lock/): Convenience wrapper to block waiting for an rbd lock
* [`ceph/rbd-unlock`](rbd-unlock/): Convenience wrapper to release an rbd lock
* [`ceph/rbd-volume`](rbd-volume/): Convenience wrapper to mount an rbd volume

## Demo

* [`ceph/demo`](demo/): Demonstration cluster for testing and learning.  This container runs all the major ceph components installed, bootstrapped, and executed for you to play with.  (not intended for use in building a production cluster)

# How to contribute?!

The following assumes that you already forked the repository, added the correct remote and are familiar with git commands.

## Prepare your development environment

Simply execute `./generate-dev-env.sh CEPH_RELEASE DISTRO DISTRO_VERSION`.
For example if you run `./generate-dev-env.sh jewel ubuntu 16.04` the script will:

* hardlink the files from `ceph-releases/jewel/ubuntu/16.04/{base,daemon}` in `./base` and `./daemon`.
* create a file in `{base,daemon}/SOURCE_TREE` which will remind you the version you are working on.

From this, you can start modifying your code and building your images locally.

## My code is ready, what's next?

Contributions must go in the 'ceph-releases' tree, in the appropriate Ceph version, distribution and distribution version.
So once you are done, we can just run `cp -av base $(cat base/SOURCE_TREE)` and `cp -av daemon $(cat base/SOURCE_TREE)`.

We identified 2 types of contributions:

### Distro specific contributions

The code only changes the `base` image content of a specific distro, nothing to replicate or change for the other images..

### New functionality contributions

If you look at the ceph-releases directory you will notice that most of the daemons images content is symlinked to the Ubuntu daemon.
Even if we support multi-distro, Ubuntu remains the default.
It would nice if you could get familiar with this approach.
So even if you change something in the `entrypoint` of CentOS please update the Ubuntu default file so symlinks can continue to operate.
With this method every distro can benefit from your change.
If your code touches one of the entrypoints from the daemon image, you **must** apply this change to **all** the `CEPH_RELEASE`, `DISTRO` and `DISTRO_VERSION` as it brings a new functionality.
At some point, we will start deprecating some `CEPH_RELEASE`, so the process will be smoother.
So please do not do work for your own distro if you believe your change can benefit other distributions.
So yes this is a bit painful but it's the price to pay to have a proper multi-distribution compliant workflow.

In the end, remember that Ubuntu owns the files that you should consider modifying, symlinks will do the rest.

# CI

We use Travis to run several tests on each pull request:

* we build both `base` and `daemon` images
* we run all the ceph processes in a container based on the images we just built
* we execute a validation script at the end to make sure Ceph is healthy

For each PR, we try to detect which Ceph release is being impacted.
Since we can only produce a single CI build with Travis, ideally this change will only be on a single release and distro.
If we have multiple ceph release and distro, we can only test one, since we have to build `base` and `daemon`.
By default, we just pick up the first line that comes from the changes.

You can check the files in `travis-builds` to learn more about the entire process.

If you don’t want to run a build for a particular commit, because all you are changing is the README for example, add `[ci skip]` to the git commit message.
Commits that have `[ci skip]` anywhere in the commit messages are ignored by Travis CI.

# Images workflow

Once your contribution is done and merged in master. Either @Ulexus or @leseb will execute `ceph-docker-workflow.sh`, this will basically compare the content of each tag/branch to master.
If any difference is found it will push the appropriate changes in each individual branches.
Ultimately new pushed tags will trigger a Docker build on the Docker Hub.

# Video demonstration

## Manually

A recorded video on how to deploy your Ceph cluster entirely in Docker containers is available here:

[![Demo Running Ceph in Docker containers](http://img.youtube.com/vi/FUSTjTBA8f8/0.jpg)](http://youtu.be/FUSTjTBA8f8 "Demo Running Ceph in Docker containers")

## With Ansible

[![Demo Running Ceph in Docker containers with Ansible](http://img.youtube.com/vi/DQYZU1VsqXc/0.jpg)](http://youtu.be/DQYZU1VsqXc "Demo Running Ceph in Docker containers with Ansible")
