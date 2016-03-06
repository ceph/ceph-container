ceph-tools
==========

These are wrapper files for ceph CLI tools to make working with ceph a little
easier and allow direct usage from the host OS.

Installation
============

Copy the tools files wherever you would like them.  e.g. /opt/bin

Typically the easiest way to install these is using the docker container.  This method is especially handy under CoreOS.

To load the CLI tools using docker, run the following command on the host:
`/usr/bin/docker run --rm -v /opt/bin:/opt/bin ceph/tools`

Then use the CLI tools as you normally would.

`ceph status`
`ceph-disk prepare`
`rados lspools`

Note: If the directory where you have loaded the files is not in the path, you may need to add it or call using the full path
