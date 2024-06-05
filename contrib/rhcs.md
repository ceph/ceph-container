## Log into Red Hat's registry

The RH Ceph Storage image is based on ubi9. To pull this image on your
computer, you will need a Red Hat Customer Portal account. Log in with your
username and password:

```
$ podman login registry.redhat.io
Username: **********
Password: **********
Login Succeeded!
```

You will then be able to run `podman pull
registry.redhat.io/ubi9/ubi-minimal:latest` to fetch the base image.

## Composing the Dockerfile

The `ceph-container` project uses a series of template files to create the
final `Dockerfile` that developers can build or commit to dist-git. This
command generates that downstream Red Hat UBI-based `Dockerfile`:

```
BRANDING=redhat VERSION=7 ./contrib/compose-rhcs.sh
```

Or the IBM-branded `Dockerfile`:
```
BRANDING=ibm VERSION=7 ./contrib/compose-rhcs.sh
```

## Yum repositories

You will not see any Yum repositories in the resulting `Dockerfile` from `./contrib/compose-rhcs.sh`.

We use [OSBS](https://osbs.readthedocs.io/en/latest/) to build the images for RH storage products. OSBS dynamically injects Yum repository definition steps into our `Dockerfile` during each build. This gives us far more flexibility (for hotfixes, etc) than storing all repo files in Git.

To test a local build outside OSBS, you must mimic what OSBS does and insert some Yum repo definitions.

First, create an ODCS compose from the candidate tag:

```
odcs --redhat create-tag --sigkey none ceph-7.0-rhel-9-candidate
```

Save the resulting id and baseurl for the next step.

Next, after the `RUN rm -f /etc/yum.repos.d/ubi.repo` step, add the following by-hand steps to your `staging/main-ubi9-latest-x86_64/composed/Dockerfile`:

```Dockerfile
RUN printf '[rhel-9-baseos]\n\
name = Red Hat Enterprise Linux 9 BaseOS\n\
baseurl = https://rhsm-pulp.corp.redhat.com/content/dist/rhel9/9/$basearch/baseos/os/\n\
enabled = 1\n\
gpgcheck = 1\n\
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release\n\
\n\
[rhel-9-appstream]\n\
name = Red Hat Enterprise Linux 9 AppStream\n\
baseurl = https://rhsm-pulp.corp.redhat.com/content/dist/rhel9/9/$basearch/appstream/os/\n\
enabled = 1\n\
gpgcheck = 1\n\
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release' >> /etc/yum.repos.d/rhel-9.repo

# Note: use your ODCS compose ID here (replacing "12345678"):

RUN printf '[odcs]\n\
name = odcs\n\
baseurl = http://download-01.beak-001.prod.iad2.dc.redhat.com/odcs/prod/odcs-12345678/compose/Temporary/$basearch/os/\n\
enabled = 1\n\
gpgcheck = 0\n\
' >> /etc/yum.repos.d/odcs.repo
```

**Note: this uses an internal Pulp server, so your computer must be on Red
Hat's network to access these repositories.**

## Running a build

```
cd staging/main-ubi9-latest-x86_64/composed
make build DAEMON_BASE_IMAGE=test
```
