ceph-container
==============

As of August 2021, new container images are pushed to quay.io registry only.
Docker hub won't receive new content for that specific image but current images remain available.

[![Ceph Daemon Stars](https://img.shields.io/docker/stars/ceph/daemon.svg)](https://hub.docker.com/r/ceph/daemon)
[![Ceph Daemon Pulls](https://img.shields.io/docker/pulls/ceph/daemon.svg)](https://hub.docker.com/r/ceph/daemon)

Build Ceph into container images with upstream support for the latest few Ceph
releases on CentOS. ceph-container also supports builds for multiple distributions.

Find available container image tags
-----------------------------------

All tags for ceph/ceph can be found on the quay.io registry.
[visit](https://quay.io/repository/ceph/ceph?tab=tags)
As an alternative you can still use the docker hub registry but without the most recent images.
[visit](https://hub.docker.com/r/ceph/ceph/tags)

Alternatively, you can run the following command (install jq first):

For quay.io registry
```bash
$ curl -s -L https://quay.io/api/v1/repository/ceph/ceph/tag?page_size=100 | jq '."tags"[] .name'
```
For docker hub registry
```bash
$ curl -s https://registry.hub.docker.com/v2/repositories/ceph/ceph/tags/?page_size=100 | jq '."results"[] .name'
```

All tags for ceph/{daemon-base,daemon} can be found on the quay.io registry.
For the daemon-base tags [visit](https://quay.io/repository/ceph/daemon-base?tab=tags)
For the daemon tags [visit](https://quay.io/repository/ceph/daemon?tab=tags)
As an alternative you can still use the docker hub registry but without the most recent images.
For the daemon-base tags [visit](https://hub.docker.com/r/ceph/daemon-base/tags/).
For the daemon tags [visit](https://hub.docker.com/r/ceph/daemon/tags/).

Alternatively, you can run the following command (install jq first):

For quay.io registry
```bash
$ curl -s -L https://quay.io/api/v1/repository/ceph/daemon/tag?page_size=100 | jq '."tags"[] .name'
```
For docker hub registry
```bash
$ curl -s https://registry.hub.docker.com/v2/repositories/ceph/daemon/tags/?page_size=100 | jq '."results"[] .name'
```


Be careful, this will only show the latest 100 tags.  To improve your `curl` you can pass a page number: `https://registry.hub.docker.com/v2/repositories/ceph/daemon/tags/?page_size=100&page=2` or use the following bash script to search multiple pages:

This will search for all tags with both **stable** and **nautlius** in the latest 2000

```bash
for i in {1..20}; do \
    curl -s https://registry.hub.docker.com/v2/repositories/ceph/daemon/tags/?page_size=100\&page=$i | jq '."results"[] .name'; \
done | awk '/stable/ && /nautilus/'
```

Stable images
-------------
Since everyone doesn't use Docker Hub API and Docker Hub WebUI doesn't paginate. It's hard to see all available stable images.

**Starting August 22th 2018, Ubuntu images are no longer supported. Only openSUSE and CentOS images will be shipped.**

Here is an example list of available stable Ceph images

```
ceph/daemon:v3.0.5-stable-3.0-luminous-centos-7
ceph/daemon:v3.0.5-stable-3.0-luminous-centos-7-x86_64
ceph/daemon:v3.0.5-stable-3.0-luminous-centos-7-aarch64
ceph/daemon:v3.0.3-stable-3.0-luminous-centos-7-x86_64
ceph/daemon:v3.0.2-stable-3.0-luminous-centos-7-x86_64
ceph/daemon:v3.0.1-stable-3.0-luminous-centos-7-x86_64
ceph/daemon:tag-stable-3.0-luminous-centos-7
```

Development images
------------------
It is possible to build a container running the latest development release (master). It also includes the latest development packages from the nfs-ganesha project.

This is only available on CentOS with the following command :
`make FLAVORS="master,centos,7" build`

Alternatively, you can build a container image based on `wip-*` branch:

`make FLAVORS="wip-nautilus-superb,centos,7" build`

To build your branch on Centos 7 on the `wip-nautilus-superb` branch. But please make sure the
branch name contains the release name from which the branch is created.

It's also possible to use the Ceph development builds instead of the stable one (except for master).
The ceph packages will be pulled from shaman/chacra repositories.
The Ceph development images are using the `latest-<release>-devel` tag where release is the ceph
release name (ie: luminous, mimic, nautilus)

`make CEPH_DEVEL=true FLAVORS="nautilus,centos,7" build`

This will generate the following container images:

```
ceph/daemon:latest-nautilus-devel
ceph/daemon-base:latest-nautilus-devel
```

Core Components
---------------

- [`ceph/daemon-base`](src/daemon-base/): Base container image containing Ceph core components.
- [`ceph/daemon`](src/daemon/): All-in-one container containing all Ceph daemons.

See README files in subdirectories for instructions on using containers.


Building ceph-container
-----------------------
`make` is used for ceph-container builds. See `make help` for all make options.

### Specifying flavors for make
The `make` tooling allows the environment variable `FLAVORS` to be optionally set by the user to
define which flavors to operate on. Flavor specifications follow a strict format that declares what
Ceph version to build and what container image to use as the base for the build. See `make help` for
a full description.

### Building a single flavor
Once the flavor is selected, specify its name in the `FLAVORS` environment variable and call the
`build` target:
```
make FLAVORS=luminous,centos,7 build
```

### Building multiple flavors
Multiple flavors are specified by separating each flavor by a space and surrounding the entire
specification in quotes and built the same as a single flavor:
```
make FLAVORS="luminous,centos,7 mimic,opensuse,42.3"  build
```

Flavors can be built in parallel easily with the `build.parallel` target:
```
make FLAVORS="<flavor> <other flavor> <...>" build.parallel
```

### Building with a specific version of Ceph
Some distributions can select a specific version of Ceph to install.
You just have to append the required version to the ceph release code name.

The required version will be saved in `CEPH_POINT_RELEASE` variable (including the version separator).
The version separator is usually a dash ('-') or an equal sign ('=').
`CEPH_POINT_RELEASE` remains empty if no point release is given.

Note that `CEPH_VERSION` variable still feature the ceph code name, **luminous** in this example.

```
make FLAVORS=luminous-12.2.2,centos,7 build
```

## Presentations

<p><a href="https://docs.google.com/presentation/d/e/2PACX-1vQsN2ywxSibTSH-p-0PpNWpKTSfSSLx3gApetKzmuLiMwKm0Sk9mg-Swnae-m5tKkHwCGULDfFOJsvJ/pub?start=false&loop=false&delayms=3000"> Restructuring ceph-container </a></p>
