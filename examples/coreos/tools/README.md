ceph-tools
==========

These are wrapper files for ceph cli tools to make working with ceph a little
easier and directly from the host OS.

Installation
============

Copy the tools files wherever you would like them.  e.g. /opt/bin

Another way to install these is with docker.  This is especially handy under CoreOS.

`/usr/bin/docker run --rm -v /opt/bin:/opt/bin ceph/tools

Then use them you normally would.

`ceph status`
`ceph-disk prepare`
`rados lspools`
