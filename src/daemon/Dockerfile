# CEPH DAEMON IMAGE

FROM __ENV_[DAEMON_BASE_IMAGE]__

__DOCKERFILE_TRACEABILITY_LABELS__

#======================================================
# Install ceph and dependencies, and clean up
#======================================================
__DOCKERFILE_PREINSTALL__

# Escape char after immediately after RUN allows comment in first line
RUN \
    # Install all components for the image, whether from packages or web downloads.
    # Typical workflow: add new repos; refresh repos; install packages; package-manager clean;
    #   download and install packages from web, cleaning any files as you go.
    __DOCKERFILE_INSTALL__ && \
    # Clean container, starting with record of current size (strip / from end)
    INITIAL_SIZE="$(bash -c 'sz="$(du -sm --exclude=/proc /)" ; echo "${sz%*/}"')" && \
    #
    #
    # Perform any final cleanup actions like package manager cleaning, etc.
    __DOCKERFILE_POSTINSTALL_CLEANUP__ && \
    # Clean daemon-specific files
    __DOCKERFILE_CLEAN_DAEMON__ && \
    # Clean common files like /tmp, /var/lib, etc.
    __DOCKERFILE_CLEAN_COMMON__ && \
    #
    #
    # Report size savings (strip / from end)
    FINAL_SIZE="$(bash -c 'sz="$(du -sm --exclude=/proc /)" ; echo "${sz%*/}"')" && \
    REMOVED_SIZE=$((INITIAL_SIZE - FINAL_SIZE)) && \
    echo "Cleaning process removed ${REMOVED_SIZE}MB" && \
    echo "Dropped container size from ${INITIAL_SIZE}MB to ${FINAL_SIZE}MB" && \
    #
    # Verify that the packages installed haven't been accidentally cleaned
    __DOCKERFILE_VERIFY_PACKAGES__ && echo 'Packages verified successfully'

#======================================================
# Add ceph-container files
#======================================================

# Add s3cfg file
ADD s3cfg /root/.s3cfg

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# Add bootstrap script, ceph defaults key/values for KV store
ADD *.sh check_zombie_mons.py ./osd_scenarios/* entrypoint.sh.in disabled_scenario /opt/ceph-container/bin/
ADD ceph.defaults /opt/ceph-container/etc/
# ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* entrypoint.sh.in disabled_scenario /

# Copye sree web interface for cn
# We use COPY instead of ADD for tarball so that it does not get extracted automatically at build time
COPY Sree-0.2.tar.gz /opt/ceph-container/tmp/sree.tar.gz

# Modify the entrypoint
RUN bash "/opt/ceph-container/bin/generate_entrypoint.sh" && \
  rm -f /opt/ceph-container/bin/generate_entrypoint.sh && \
  bash -n /opt/ceph-container/bin/*.sh

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/opt/ceph-container/bin/entrypoint.sh"]
