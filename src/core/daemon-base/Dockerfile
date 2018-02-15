# CEPH DAEMON BASE IMAGE

FROM MAKEFILE_REPLACE_WITH_BASE_IMAGE
MAINTAINER __DOCKERFILE_MAINTAINER__

ENV CEPH_VERSION STAGE_REPLACE_WITH_CEPH_VERSION

#======================================================
# Install ceph and dependencies, and clean up
#======================================================
__DOCKERFILE_INSTALL_PRE__

# Escape char after immediately after RUN allows comment in first line
ADD clean_container_common.sh /
RUN ( \
    __DOCKERFILE_INSTALL__ ) && \
    bash -c ' \
      function ifstrip () { if compgen -g "$1"; then strip -s "$1"; fi } && \
      ifstrip /usr/lib/ceph/erasure-code/* && \
      ifstrip /usr/lib/rados-classes/* && \
      ifstrip /usr/lib/python2.7/dist-packages/{rados,rbd,rgw}.*.so' && \
    # Clean container
    bash /clean_container_common.sh && rm /clean_container_common.sh
