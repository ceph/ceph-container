# CEPH DAEMON IMAGE
# CEPH VERSION: Luminous
# CEPH VERSION DETAIL: 12.x.x

FROM MAKEFILE_REPLACE_WITH_DAEMON_BASE_IMAGE
MAINTAINER __DOCKERFILE_MAINTAINER__

#======================================================
# Install ceph and dependencies, and clean up
#======================================================
__DOCKERFILE_PREINSTALL__

# Escape char after immediately after RUN allows comment in first line
RUN ( \
    __DOCKERFILE_INSTALL__ ) && \
    # Clean container
    INITIAL_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}') && \
    #
    #
    __DOCKERFILE_CLEAN_CONTAINER_COMMON__ && \
    # Clean distro-specific things. Each distro must define this. Can be a blank file.
    __DOCKERFILE_CLEAN_DISTRO_SPECIFIC__ && \
    # Clean daemon-specific files
    __DOCKERFILE_CLEAN_DAEMON__ && \
    # Perl isn't needed after setup. Each distro must define this. Can be a blank file.
    __DOCKERFILE_REMOVE_PERL__ && \
    #
    #
    # Report size savings
    FINAL_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}') && \
    REMOVED_SIZE=$((INITIAL_SIZE - FINAL_SIZE)) && \
    echo "Cleaning process removed ${REMOVED_SIZE}MB" && \
    echo "Dropped container size from ${INITIAL_SIZE}MB to ${FINAL_SIZE}MB"

#======================================================
# Add ceph-container files
#======================================================

# Add s3cfg file
ADD s3cfg /root/.s3cfg

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# Add bootstrap script, ceph defaults key/values for KV store
ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* entrypoint.sh.in disabled_scenario /

# Modify the entrypoint
RUN bash "/generate_entrypoint.sh" && \
  rm -f /generate_entrypoint.sh && \
  bash -n /*.sh

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph", "/etc/ganesha"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
