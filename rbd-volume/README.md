# `rbd-volume` - *NON-FUNCTIONAL*

This Docker container will mount the requested `RBD` image to a volume.  You can then
use link to that volume from other containers with the `--volumes-from` Docker `run` option.

## Environment variables:
   * `RBD_IMAGE`: name of the image (defaults to `image0`)
   * `RBD_POOL`: name of the pool in which the image resides (defaults to `rbd`)
   * `RBD_OPTS`: rbd map options (defaults to `rw`)
   * `RBD_FS`: filesystem of the RBD image (defaults to `xfs`)
      * NOTE:  this container does NOT create the filesystem
   * `RBD_TARGET`: the target mountpoint inside the container (defaults to `/mnt/rbd`)

## Features
   * May mount to different targets (allowing multiple instances)
   * Go-based maintenance daemon
      * Keeps container running
      * Unmounts on exit signal
   * May mount to host filesystem mountpoint (`-v /host/path/mountpoint:/mnt/rbd`)

## Example usage

   * `docker run --name myData -e RBD_IMAGE=myData -e RBD_POOL=myPool ceph/rbd-volume`
   * `docker run --volumes-from myData myOrg/myApp`
