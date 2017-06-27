# RHCS IMAGE
# RHCS VERSION: 3

FROM rhel7:7.3-released
LABEL Maintainer="Sebastien Han 'seb@redhat.com'"

ENV container docker

ARG PACKAGES="ceph-mon ceph-osd ceph-mds ceph-radosgw rbd-mirror nfs-ganesha-rgw e2fsprogs"
RUN yum -y update && \
    yum -y install $PACKAGES && \
    rpm -q $PACKAGES && \
    yum clean all

# Editing /etc/redhat-storage-server release file
RUN echo "Red Hat Ceph Storage Server 3 (Container)" > /etc/redhat-storage-release

EXPOSE 6789 6800 6801 6802 6803 6804 6805 80 5000

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph","/etc/ganesha"]

# Add bootstrap script, ceph defaults key/values for KV store
ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* entrypoint.sh.in disabled_scenario /

# Modify the entrypoint
RUN bash "/generate_entrypoint.sh" && \
  rm -f /generate_entrypoint.sh && \
  bash -n /*.sh

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]

# Atomic specific labels
ADD install.sh /install.sh
LABEL version=3
LABEL run="/usr/bin/docker run -d --net=host --pid=host -e MON_NAME=\${MON_NAME} -e MON_IP=\${MON_IP}  -e CEPH_PUBLIC_NETWORK=\${CEPH_PUBLIC_NETWORK} -e CEPH_DAEMON=\${CEPH_DAEMON} -v /etc/ceph:/etc/ceph -v /var/lib/ceph:/var/lib/ceph \${IMAGE}"
LABEL install="/usr/bin/docker run --rm --privileged -v /:/host -e MON_IP=\${MON_IP}  -e CEPH_PUBLIC_NETWORK=\${CEPH_PUBLIC_NETWORK} -e CEPH_DAEMON=\${CEPH_DAEMON} -e MON_NAME=\${MON_NAME} -e OSD_DEVICE=\${OSD_DEVICE} -e HOST=/host -e IMAGE=\${IMAGE} --entrypoint=/install.sh \${IMAGE}"

# Build specific labels
LABEL com.redhat.component="rhceph-rhel7-docker"
LABEL name="rhceph"
LABEL description="Red Hat Ceph Storage 3"
LABEL summary="Provides the latest Red Hat Ceph Storage 3 on RHEL 7 in a fully featured and supported base image."
LABEL io.k8s.display-name="Red Hat Ceph Storage 3 on RHEL 7"
LABEL io.openshift.tags="rhceph ceph"
