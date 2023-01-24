FROM __ENV_[DAEMON_BASE_IMAGE]__

ENV I_AM_IN_A_CONTAINER 1

__DOCKERFILE_TRACEABILITY_LABELS__
ENV CEPH_VERSION __ENV_[CEPH_VERSION]__
ENV CEPH_POINT_RELEASE "__ENV_[CEPH_POINT_RELEASE]__"
ENV CEPH_DEVEL __ENV_[CEPH_DEVEL]__
ENV CEPH_REF __ENV_[CEPH_REF]__
ENV OSD_FLAVOR __ENV_[OSD_FLAVOR]__

ADD demo.sh /opt/ceph-container/bin/demo
ADD s3cfg /root/.s3cfg
# Copy sree web interface for cn
# We use COPY instead of ADD for tarball so that it does not get extracted automatically at build time
COPY Sree-0.2.tar.gz /opt/ceph-container/tmp/sree.tar.gz

RUN \
__DOCKERFILE_INSTALL__ && \
__DOCKERFILE_POSTINSTALL_CLEANUP__

WORKDIR /
ENTRYPOINT ["/opt/ceph-container/bin/demo"]
