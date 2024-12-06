`Containerfile` has moved
-------------------------

This `ceph-container` GitHub repository is deprecated and read-only. **The Ceph developers have moved all development to the `Containerfile` in the primary `ceph` GitHub repository:**

* `main`: https://github.com/ceph/ceph/blob/main/container/Containerfile

Older releases:

* `squid`: https://github.com/ceph/ceph/blob/squid/container/Containerfile
* `reef`: https://github.com/ceph/ceph/blob/reef/container/Containerfile
* `quincy`: https://github.com/ceph/ceph/blob/quincy/container/Containerfile

Please make future contributions to these locations.


History
-------

This repository originally held the first experiments of putting Ceph into container images. Later on, this repository held a variety of operating systems and versions in file snippets with a templating system. We have simplified this to a single flat `Containerfile`, one per Ceph release.
