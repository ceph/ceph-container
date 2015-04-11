# DOCKER-VERSION 1.0.0
# 
# Ceph monitor
#
#  USAGE NOTES:
#    - ***This WILL NOT work with the normal NAT'd Docker network***
#    - For easiest operation, run with --net=host (which executes the container
#      with the host's network interface connected).  Otherwise, you'll have to
#      do some fancy footwork to allow the monitor to bind the the real IP address
#      you specify in MONIP.
#    - Define at least the two following environment variables:
#      MONHOST - the hostname of this monitor
#      MONIP   - the (externally visible) IP address of this monitor
#    - Ceph expects monitor IPs and hostnames to be _static_, so make sure you execute
#      the docker container properly
#    - /etc/ceph is set as a volume, so you may use a common configuration directory
#      among your ceph daemons (this also keeps private keys outside of the image)
#    - ***IMPORTANT**  When _adding_ monitors to existing Ceph clusters, make
#      certain you import the following files _before_ executing this container:
#        - /etc/ceph/ceph.conf (the main ceph.conf)
#        - /etc/ceph/ceph.client.admin.keyring (the admin client keyring)
#        - /etc/ceph/monmap (the current monitor map)
#
# VERSION 0.0.2

FROM ceph/base:hammer
MAINTAINER Seán C McCord "ulexus@gmail.com"

# Add bootstrap script
ADD entrypoint.sh /entrypoint.sh

# Add volumes for ceph config and monitor data
VOLUME ["/etc/ceph","/var/lib/ceph"]

# Expose the ceph monitor port (6789, by default)
EXPOSE 6789

# Execute monitor as the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
