# RHCS IMAGE
# RHCS VERSION: 2

FROM  rhel7:7.3-released
MAINTAINER Ken Dreyer "kdreyer@redhat.com"

ENV container docker

ARG PACKAGES="ceph-mon ceph-osd ceph-mds ceph-radosgw rbd-mirror nfs-ganesha-rgw"
RUN yum -y update && \
    yum -y install $PACKAGES && \
    rpm -q $PACKAGES && \
    yum clean all

# Editing /etc/redhat-storage-server release file
RUN echo "Red Hat Ceph Storage Server 2.3 (Container)" > /etc/redhat-storage-release

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph","/etc/ganesha"]

# Add bootstrap script, ceph defaults key/values for KV store
ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* /

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]

# Atomic specific labels
ADD install.sh /install.sh
LABEL version=2.3
LABEL run="/usr/bin/docker run -d --net=host --pid=host -e MON_NAME=\${MON_NAME} -e MON_IP=\${MON_IP}  -e CEPH_PUBLIC_NETWORK=\${CEPH_PUBLIC_NETWORK} -e CEPH_DAEMON=\${CEPH_DAEMON} -v /etc/ceph:/etc/ceph -v /var/lib/ceph:/var/lib/ceph \${IMAGE}"
LABEL install="/usr/bin/docker run --rm --privileged -v /:/host -e MON_IP=\${MON_IP}  -e CEPH_PUBLIC_NETWORK=\${CEPH_PUBLIC_NETWORK} -e CEPH_DAEMON=\${CEPH_DAEMON} -e MON_NAME=\${MON_NAME} -e OSD_DEVICE=\${OSD_DEVICE} -e HOST=/host -e IMAGE=\${IMAGE} --entrypoint=/install.sh \${IMAGE}"

# build specific labels
LABEL com.redhat.component="rhceph-rhel7-docker"
LABEL name="rhceph"
LABEL description="Red Hat Ceph Storage 2"
