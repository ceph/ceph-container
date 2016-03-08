# ceph-tools

These are wrapper files for ceph CLI tools to make working with ceph a little easier and allow direct usage from the host OS.

## Installation


Copy the tools files wherever you would like them.  e.g. /opt/bin

Typically the easiest way to install these is using the docker container.  This method is especially handy under CoreOS.

To load the CLI tools to `/opt/bin` using docker, run the following command on the host:  
`/usr/bin/docker run --rm -v /opt/bin:/opt/bin ceph/install-utils`

To install to an alternate directory on the host using docker:  
`/usr/bin/docker run --rm -v /path/for/install:/opt/bin ceph/install-utils`


Then use the CLI tools as you normally would.

`ceph status`  
`ceph-disk prepare`  
`rados lspools`  
`rbd ls`  

__Note:__ If the directory where you have loaded the files is not in PATH, you may need to add the directory or call using the full path to the wrapper (i.e. `/opt/bin/rbd ls`)
