ceph-container
==============

![Ceph Daemon Stars](https://img.shields.io/docker/stars/ceph/daemon.svg)
![Ceph Daemon Pulls](https://img.shields.io/docker/pulls/ceph/daemon.svg)

Build Ceph into container images with upstream support for the latest few Ceph releases on
Ubuntu-based containers. ceph-container also supports builds for multiple distributions but does not
support the containers non-Ubuntu released images.


Core Components
---------------

- [`ceph/daemon-base`](src/daemon-base/): Base container image containing Ceph core components.
- [`ceph/daemon`](daemon/): All-in-one container containing all Ceph daemons.

See README files in subdirectories for instructions on using containers.


Demo
-----

- [`ceph/demo`](ceph-releases/jewel/ubuntu/14.04/demo/): Demonstration cluster for testing and
  learning. This container runs all the major Ceph and Ganesha components installed, bootstrapped,
  and executed for you to play with. (not intended for use in building a production cluster)


Video demonstration
-------------------

### Manually

A recorded video on how to deploy your Ceph cluster entirely in Docker containers is available here:

[![Demo Running Ceph in Docker containers](http://img.youtube.com/vi/FUSTjTBA8f8/0.jpg)](http://youtu.be/FUSTjTBA8f8 "Demo Running Ceph in Docker containers")

### With Ansible

[![Demo Running Ceph in Docker containers with Ansible](http://img.youtube.com/vi/DQYZU1VsqXc/0.jpg)](http://youtu.be/DQYZU1VsqXc "Demo Running Ceph in Docker containers with Ansible")


Building ceph-container
-----------------------
`make` is used for ceph-container builds. See `make help` for all make options.

### Specifying flavors for make
The `make` tooling allows the environment variable `FLAVORS` to be optionally set by the user to
define which flavors to operate on. Flavor specifications follow a strict format that declares what
ceph-container source to use, what architecture to build for, and what container image to use as the
base for the build. See `make help` for a full description.

### Building a single flavor
Once the flavor is selected, specify its name in the `FLAVORS` environment variable and call the
`build` target:
```
make FLAVORS=luminous,x86_64,centos,7,_,centos,7 build
```

### Building multiple flavors
Multiple flavors are specified by separating each flavor by a space and surrounding the entire
specification in quotes and built the same as a single flavor:
```
make FLAVORS="luminous,x86_64,centos,7,_,centos,7 kraken,x86_64,centos,7,_,centos,7"  build
```

Flavors can be built in parallel easily with the `build.parallel` target:
```
make FLAVORS="<flavor> <other flavor> <...>" build.parallel
```
