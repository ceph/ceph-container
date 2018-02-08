# CEPH DAEMON IMAGE

FROM __DOCKERFILE_BASE_IMAGE__
MAINTAINER __DOCKERFILE_MAINTAINER__

ENV CEPH_VERSION __DOCKERFILE_CEPH_VERSION__

#======================================================
# Add ceph-container script files
#======================================================

# Add bootstrap script, ceph defaults key/values for KV store
# This will also add any new *.sh scripts added by overrides
ADD *.sh ceph.defaults check_zombie_mons.py ./osd_scenarios/* entrypoint.sh.in disabled_scenario /

#======================================================
# Install ceph and dependencies, and clean up
#======================================================
__DOCKERFILE_INSTALL_PRE__

# Escape char after immediately after RUN allows comment in first line
RUN ( \
    __DOCKERFILE_INSTALL__ ) && \
    # Clean container
    bash /clean_container.sh && rm /clean_container.sh


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
