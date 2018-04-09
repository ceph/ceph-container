# CEPH DAEMON BASE IMAGE

FROM __ENV_[BASE_IMAGE]__
MAINTAINER __DOCKERFILE_MAINTAINER__

__DOCKERFILE_TRACEABILITY_LABELS__

ENV CEPH_VERSION __ENV_[CEPH_VERSION]__
ENV CEPH_POINT_RELEASE __ENV_[CEPH_POINT_RELEASE]__

#======================================================
# Install ceph and dependencies, and clean up
#======================================================

__DOCKERFILE_PREINSTALL__

# Escape char after immediately after RUN allows comment in first line
RUN \
    # Install all components for the image, whether from packages or web downloads.
    # Typical workflow: add new repos; refresh repos; install packages; package-manager clean;
    #   download and install packages from web, cleaning any files as you go.
    # Installs should support install of ganesha for luminous without installing for jewel/kraken.
    __DOCKERFILE_INSTALL__ && \
    # Clean container, starting with record of current size
    INITIAL_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}') && \
    #
    #
    # Perform any final cleanup actions like package manager cleaning, etc.
    __DOCKERFILE_POSTINSTALL_CLEANUP__ && \
    # Clean common files like /tmp, /var/lib, etc.
    __DOCKERFILE_CLEAN_COMMON__ && \
    #
    #
    # Report size savings
    FINAL_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}') && \
    REMOVED_SIZE=$((INITIAL_SIZE - FINAL_SIZE)) && \
    echo "Cleaning process removed ${REMOVED_SIZE}MB" && \
    echo "Dropped container size from ${INITIAL_SIZE}MB to ${FINAL_SIZE}MB"
