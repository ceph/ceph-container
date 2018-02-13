# CEPH DAEMON BASE IMAGE

FROM opensuse:42.3
MAINTAINER Blaine Gardner "blaine.gardner@suse.com"

ENV CEPH_VERSION luminous

#======================================================
# Install ceph and dependencies, and clean up
#======================================================
# OS version string for repos
ARG OS_VERSION='openSUSE_Leap_42.3'

# Ceph source repository
ARG CEPH_REPO="http://download.opensuse.org/repositories/filesystems:/ceph:/${CEPH_VERSION}/${OS_VERSION}/"
# The Cloud:Tools repo has 's3cmd' (used by the demo only)
ARG CLOUD_REPO="http://download.opensuse.org/repositories/Cloud:/Tools/${OS_VERSION}/"
# Other build dependencies (confd, forego)
ARG BUILD_DEPS_REPO="http://download.opensuse.org/repositories/filesystems:/ceph/${OS_VERSION}/"
ARG PACKAGES="ceph ceph-radosgw rbd-mirror kmod"

# Escape char after immediately after RUN allows comment in first line
ADD clean_container_common.sh /
RUN ( \
    ( ZYPPER="zypper --non-interactive" && \
      $ZYPPER addrepo $CEPH_REPO ceph-luminous && \
      $ZYPPER addrepo $CLOUD_REPO cloud-tools && \
      $ZYPPER addrepo $BUILD_DEPS_REPO build-deps && \
      $ZYPPER --gpg-auto-import-keys refresh && \
      $ZYPPER update && \
      $ZYPPER install $PACKAGES && \
      $ZYPPER info $PACKAGES && \
      # Remove added repos to save space
      $ZYPPER removerepo ceph-luminous && \
      $ZYPPER removerepo cloud-tools && \
      $ZYPPER removerepo build-deps && \
      $ZYPPER clean --all ) || \
      ( retval=$? && cat /var/log/zypper.log && exit $retval ) ) && \
    bash -c ' \
      function ifstrip () { if compgen -g "$1"; then strip -s "$1"; fi } && \
      ifstrip /usr/lib/ceph/erasure-code/* && \
      ifstrip /usr/lib/rados-classes/* && \
      ifstrip /usr/lib/python2.7/dist-packages/{rados,rbd,rgw}.*.so' && \
    # Clean container
    bash /clean_container_common.sh && rm /clean_container_common.sh
