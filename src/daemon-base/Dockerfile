# CEPH DAEMON BASE IMAGE

FROM MAKEFILE_REPLACE_WITH_BASE_IMAGE
MAINTAINER __DOCKERFILE_MAINTAINER__

ENV CEPH_VERSION STAGE_REPLACE_WITH_CEPH_VERSION

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
    #
    #
    # Report size savings
    FINAL_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}') && \
    REMOVED_SIZE=$((INITIAL_SIZE - FINAL_SIZE)) && \
    echo "Cleaning process removed ${REMOVED_SIZE}MB" && \
    echo "Dropped container size from ${INITIAL_SIZE}MB to ${FINAL_SIZE}MB"
