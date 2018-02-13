# CEPH DAEMON IMAGE

FROM ceph/daemon-base:luminous-opensuse-42.3-amd64
MAINTAINER Blaine Gardner "blaine.gardner@suse.com"

ENV CEPH_VERSION luminous

#======================================================
# Add ceph-container script files
#======================================================

# Add bootstrap script, ceph defaults key/values for KV store
# This will also add any new *.sh scripts added by overrides
ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* entrypoint.sh.in disabled_scenario /

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
ARG PACKAGES="nfs-ganesha-ceph nfs-ganesha-rgw \
              etcd device-mapper e2fsprogs kubernetes-client s3cmd \
              confd forego"

# Escape char after immediately after RUN allows comment in first line
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
    # Clean container
    bash /clean_container_common.sh && rm /clean_container_common.sh && \
    bash /clean_ceph.sh && rm /clean_ceph.sh


#======================================================
# Add remaining ceph-container files
#======================================================

# Add s3cfg file
ADD s3cfg /root/.s3cfg

# Modify the entrypoint
RUN bash "/generate_entrypoint.sh" && \
  rm -f /generate_entrypoint.sh && \
  bash -n /*.sh

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph", "/etc/ganesha"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
