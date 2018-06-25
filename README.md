ceph-container
==============

![Ceph Daemon Stars](https://img.shields.io/docker/stars/ceph/daemon.svg)
![Ceph Daemon Pulls](https://img.shields.io/docker/pulls/ceph/daemon.svg)

Build Ceph into container images with upstream support for the latest few Ceph releases on
Ubuntu-based containers. ceph-container also supports builds for multiple distributions but does not
support the containers non-Ubuntu released images.


Find available container image tags
-----------------------------------

All tags can be found on the Docker Hub.
For the daemon-base tags [visit](https://hub.docker.com/r/ceph/daemon-base/tags/).
For the daemon tags [visit](https://hub.docker.com/r/ceph/daemon/tags/).

Alternatively, you can run the following command (install jq first):

```
$ curl -s https://registry.hub.docker.com/v2/repositories/ceph/daemon/tags/ | jq '."results"[] .name'
```

Be careful, by default the Docker API returns the first page with its 10 elements.
To improve your `curl` you can pass the `https://registry.hub.docker.com/v2/repositories/ceph/daemon/tags/?page=2`

Stable images
-------------
Since everyone doesn't use Docker Hub API and Docker Hub WebUI doesn't paginate. It's hard to see all available stable images.

Here is a list of available stable Ceph images

```
ceph/daemon:v3.0.5-stable-3.0-luminous-centos-7
ceph/daemon:v3.0.5-stable-3.0-jewel-centos-7-x86_64
ceph/daemon:v3.0.5-stable-3.0-kraken-centos-7-x86_64
ceph/daemon:v3.0.5-stable-3.0-kraken-ubuntu-16.04-x86_64
ceph/daemon:v3.0.5-stable-3.0-jewel-ubuntu-16.04-x86_64
ceph/daemon:v3.0.5-stable-3.0-jewel-ubuntu-14.04-x86_64
ceph/daemon:v3.0.5-stable-3.0-luminous-centos-7-x86_64
ceph/daemon:v3.0.5-stable-3.0-luminous-ubuntu-16.04-x86_64
ceph/daemon:v3.0.5-stable-3.0-luminous-centos-7-aarch64
ceph/daemon:v3.0.3-stable-3.0-kraken-ubuntu-16.04-x86_64
ceph/daemon:v3.0.3-stable-3.0-jewel-centos-7-x86_64
ceph/daemon:v3.0.3-stable-3.0-jewel-ubuntu-16.04-x86_64
ceph/daemon:v3.0.3-stable-3.0-jewel-ubuntu-14.04-x86_64
ceph/daemon:v3.0.3-stable-3.0-luminous-centos-7-x86_64
ceph/daemon:v3.0.3-stable-3.0-luminous-ubuntu-16.04-x86_64
ceph/daemon:v3.0.3-stable-3.0-kraken-centos-7-x86_64
ceph/daemon:v3.0.2-stable-3.0-jewel-ubuntu-14.04-x86_64
ceph/daemon:v3.0.2-stable-3.0-kraken-centos-7-x86_64
ceph/daemon:v3.0.2-stable-3.0-jewel-ubuntu-16.04-x86_64
ceph/daemon:v3.0.2-stable-3.0-kraken-ubuntu-16.04-x86_64
ceph/daemon:v3.0.2-stable-3.0-luminous-centos-7-x86_64
ceph/daemon:v3.0.2-stable-3.0-luminous-ubuntu-16.04-x86_64
ceph/daemon:v3.0.2-stable-3.0-jewel-centos-7-x86_64
ceph/daemon:v3.0.1-stable-3.0-jewel-ubuntu-16.04-x86_64
ceph/daemon:v3.0.1-stable-3.0-kraken-centos-7-x86_64
ceph/daemon:v3.0.1-stable-3.0-jewel-ubuntu-14.04-x86_64
ceph/daemon:v3.0.1-stable-3.0-kraken-ubuntu-16.04-x86_64
ceph/daemon:v3.0.1-stable-3.0-luminous-centos-7-x86_64
ceph/daemon:v3.0.1-stable-3.0-luminous-ubuntu-16.04-x86_64
ceph/daemon:v3.0.1-stable-3.0-jewel-centos-7-x86_64
ceph/daemon:tag-stable-3.0-luminous-ubuntu-16.04
ceph/daemon:tag-stable-3.0-luminous-centos-7
ceph/daemon:tag-stable-3.0-jewel-centos-7
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
make FLAVORS="luminous,centos,7 kraken,ubuntu,16.04"  build
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
