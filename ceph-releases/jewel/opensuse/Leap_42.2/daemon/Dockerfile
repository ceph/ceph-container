FROM ceph/base:tag-build-master-jewel-opensuse-Leap_42.2
MAINTAINER Ricardo Dias "rdias@suse.com"

ADD entrypoint.sh config.*.sh check_zombie_mons.py remove-mon.sh ceph.defaults /

# Add templates for confd
ADD ./confd/templates/* /etc/confd/templates/
ADD ./confd/conf.d/* /etc/confd/conf.d/

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph", "/etc/ganesha"]

# Execute the entrypoint
WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]

