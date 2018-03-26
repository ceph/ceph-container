# CEPH DAEMON BASE IMAGE

FROM {{ env['BASE_IMAGE'] or False }}
MAINTAINER {{ template['maintainer'] }}

{{ template['render']['labels'] }}

ENV CEPH_VERSION {{ env['CEPH_VERSION'] }}

#======================================================
# Install ceph and dependencies, and clean up
#======================================================

{{ template.preinstall }}

# Escape char after immediately after RUN allows comment in first line
RUN \
    # Install all base ceph components, whether from packages or web downloads.
    {{ template['install']['packages'] }} && \
    {{ template['install']['from-web'] }} && \
    # Clean container, starting with record of current size
    INITIAL_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}') && \
    #
    #
    # Clean packages and common files. We don't add anything else that needs cleaning.
    {{ template.cleanup.packages }} && \
    {{ template.cleanup.common }} && \
    #
    #
    # Report size savings
    FINAL_SIZE=$(du -sm / 2>/dev/null | awk '{print $1}') && \
    REMOVED_SIZE=$((INITIAL_SIZE - FINAL_SIZE)) && \
    echo "Cleaning process removed ${REMOVED_SIZE}MB" && \
    echo "Dropped container size from ${INITIAL_SIZE}MB to ${FINAL_SIZE}MB"
