# DOCKER-VERSION 0.7.0
# 
# Ceph RBD volume ambassador
#
#  USAGE NOTES:
#    - Set the RBD_POOL environment variable on run (-e RBD_POOL=poolname)
#    - Set the RBD_IMAGE environment variable on run (-e RBD_IMAGE=imagename)
#    - /etc/ceph is set as a volume; remember to reference the source
#      when running this container (-v <source-dir>:/etc/ceph)
#
# VERSION 0.0.1

# Set default variables; override with (e.g.) "-e FSTYPE=btrfs"
ENV RBD_POOL rbd
ENV RBD_IMAGE volume
ENV FSTYPE xfs
ENV RBDOPTS rw

FROM ceph/ceph-base
MAINTAINER Seán C McCord "ulexus@gmail.com"

# Add volume for ceph config
VOLUME ["/etc/ceph"]

# Add a volume for exporting the RBD image
VOLUME ["/mnt/rbd"]

# Make certain the kernel module is loaded
CMD ["modprobe","rbd"]

# Map the rbd volume
CMD ["/usr/bin/rbd","map","$(RBD_IMAGE)","--pool","$(RBD_POOL)","-o","$(RBDOPTS)"]

# Mount 
ENTRYPOINT ["/bin/mount","-t","$(FSTYPE)","/dev/rbd/$(RBD_POOL)/$(RBD_IMAGE)","/mnt/rbd"]
