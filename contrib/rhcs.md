## Log into Red Hat's registry

The RH Ceph Storage image is based on ubi8. To pull this image on your
computer, you will need a Red Hat Customer Portal account. Log in with your
username and password:

```
$ podman login registry.redhat.io
Username: **********
Password: **********
Login Succeeded!
```

You will then be able to run `podman pull registry.redhat.io/ubi8/ubi:latest`
to fetch the base image.

## Composing the Dockerfile

> **_NOTE:_**  Please ensure you're working on the `stable-6.0` branch of the ceph-container project. That corresponds to the RH Ceph Storage 5 product. The `main` branch of ceph-container does not work with RH Ceph Storage 5 today.

The `ceph-container` project uses a series of template files to create the
final `Dockerfile` that developers can build or commit to dist-git. This
command generates that downstream Red Hat UBI-based `Dockerfile`:

```
./contrib/compose-rhcs.sh
```

## Yum repositories

You will not see any Yum repositories in the resulting `Dockerfile` from `./contrib/compose-rhcs.sh`.

We use [OSBS](https://osbs.readthedocs.io/en/osbs_ocp3/) to build the images for RH storage products. OSBS dynamically injects Yum repository definition steps into our `Dockerfile` during each build. This gives us far more flexibility (for hotfixes, etc) than storing all repo files in Git.

To test a local build outside OSBS, you must mimic what OSBS does and insert some Yum repo definitions.

After the `RUN rm -f /etc/yum.repos.d/ubi.repo` step, add the following by-hand steps to your `staging/pacific-ubi8-latest-x86_64/composed/Dockerfile`:

```Dockerfile
RUN printf '[rhel-8-baseos]\n\
name = Red Hat Enterprise Linux 8 BaseOS\n\
baseurl = http://rhsm-pulp.corp.redhat.com/content/dist/rhel8/8/$basearch/baseos/os/\n\
enabled = 1\n\
gpgcheck = 1\n\
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release\n\
\n\
[rhel-8-appstream]\n\
name = Red Hat Enterprise Linux 8 AppStream\n\
baseurl = http://rhsm-pulp.corp.redhat.com/content/dist/rhel8/8/$basearch/appstream/os/\n\
enabled = 1\n\
gpgcheck = 1\n\
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release' >> /etc/yum.repos.d/rhel-8.repo

RUN printf '[rhceph-5-mon-for-rhel-8-rpms]\n\
name = rhceph-5-mon-for-rhel-8-rpms\n\
baseurl = http://rhsm-pulp.corp.redhat.com/content/dist/layered/rhel8/$basearch/rhceph-mon/5/os/\n\
enabled = 1\n\
gpgcheck = 1\n\
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release\n\
\n\
[rhceph-5-osd-for-rhel-8-rpms]\n\
name = rhceph-5-osd-for-rhel-8-rpms\n\
baseurl = http://rhsm-pulp.corp.redhat.com/content/dist/layered/rhel8/$basearch/rhceph-osd/5/os/\n\
enabled = 1\n\
gpgcheck = 1\n\
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release\n\
\n\
[rhceph-5-tools-for-rhel-8-rpms]\n\
name = rhceph-5-tools-for-rhel-8-rpms\n\
baseurl = http://rhsm-pulp.corp.redhat.com/content/dist/layered/rhel8/$basearch/rhceph-tools/5/os/\n\
enabled = 1\n\
gpgcheck = 1\n\
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release\n\
' >> /etc/yum.repos.d/rhceph-5-rhel-8.repo
```

**Note: this uses an internal Pulp server, so your computer must be on Red
Hat's network to access these repositories.**

## Running a build

```
cd staging/pacific-ubi8-latest-x86_64/composed
make build DAEMON_BASE_IMAGE=test
```
