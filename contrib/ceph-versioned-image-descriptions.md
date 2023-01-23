DockerHub descriptions for ceph-vX.Y.Z images
==============================================

ceph/ceph
----------

### Short Description
Images containing all Ceph binaries.

### Full Description
Images contain all Ceph binaries as well as NFS-Ganesha and iSCSI binaries since these components
are heavily tied to Ceph's version to be compatible. Unless otherwise noted in the tag, all images
are CentOS based. New images are built within 24 hours of a new Ceph version being published to
the official Ceph package repository.

#### Image tag breakdown

**Build date** </br>
Some images are suffixed with an 8-digit build date in the form `YYYMMDD`. This indicates the date
the image was built and is used similarly to a build number for typical packages. For an image which
already exists (e.g., `v12.2.7-20181023`), a new version with a different build date will be built
when there is a base image update. For example, if the CentOS base image gets a security fix on
10 February 2080, the example image above will get a new image built with tag `v12.2.7-20800210`.

**Versions** </br>
There are a few ways to choose the Ceph version you desire:
 - Full semantic version with build date, e.g., `v12.2.9-20181026`
   - These tags are intended for use when precise control over image upgrade is desired and are
     recommended for production use.
 - Major version, e.g. `v12` (a.k.a. _Ceph Luminous_)
   - These tags are always the most recent build of the newest Ceph major release matching the tag.
 - Minor version (e.g., `v12.1`)
   - These tags are always the most recent build of the newest Ceph minor release matching the tag
     for environments where more precise control is needed than a major version but where bug fixes
     both in Ceph and in the base image are desired.

#### Image architecture
These images are manifests which will pull amd64 or arm64 images automatically based on the
architecture of the host system.

#### Image source
Images are built from the [ceph/ceph-container](https://github.com/ceph/ceph-container) project on
GitHub. These images are specially-built `base` images built with a specific Ceph version
instead of whatever version is latest.


ceph/ceph-{amd64,arm64}
------------------------

### Short Description
Images containing all Ceph binaries for a specific architecture.

### Full Description
Images are architecture-specific versions of the `ceph/ceph` images
[here](https://hub.docker.com/r/ceph/ceph/).
