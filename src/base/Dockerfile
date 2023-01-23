# CEPH DAEMON BASE IMAGE

FROM __ENV_[BASE_IMAGE]__

ENV I_AM_IN_A_CONTAINER 1

__DOCKERFILE_TRACEABILITY_LABELS__

ENV CEPH_VERSION __ENV_[CEPH_VERSION]__
ENV CEPH_POINT_RELEASE "__ENV_[CEPH_POINT_RELEASE]__"
ENV CEPH_DEVEL __ENV_[CEPH_DEVEL]__
ENV CEPH_REF __ENV_[CEPH_REF]__
ENV OSD_FLAVOR __ENV_[OSD_FLAVOR]__

#======================================================
# Install ceph and dependencies, and clean up
#======================================================

__DOCKERFILE_PREINSTALL__

# Escape char after immediately after RUN allows comment in first line
RUN \
    # Install all components for the image, whether from packages or web downloads.
    # Typical workflow: add new repos; refresh repos; install packages; package-manager clean;
    #   download and install packages from web, cleaning any files as you go.
    # Installs should support install of ganesha for luminous
    __DOCKERFILE_INSTALL__ && \
    # Clean container, starting with record of current size (strip / from end)
    INITIAL_SIZE="$(bash -c 'sz="$(du -sm --exclude=/proc /)" ; echo "${sz%*/}"')" && \
    #
    #
    # Perform any final cleanup actions like package manager cleaning, etc.
    __DOCKERFILE_POSTINSTALL_CLEANUP__ && \
    # Tweak some configuration files on the container system
    __DOCKERFILE_POSTINSTALL_TWEAKS__ && \
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
