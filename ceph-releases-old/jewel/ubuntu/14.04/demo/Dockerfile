# DOCKER-VERSION 1.0.0
#
# Ceph Demo AIO
#
# VERSION 0.0.1

FROM ceph/base:tag-build-master-jewel-ubuntu-14.04
MAINTAINER Sébastien Han "seb@redhat.com"

# Install s3cmd to support creation of buckets
RUN ["apt-get", "update", "-y"]
RUN ["apt-get", "install", "-y", "python-dateutil", "python-magic"]

# Ubuntu 14.04's s3cmd is old and doesn't support altnerative endpoints
RUN ["wget", "http://mirrors.kernel.org/ubuntu/pool/universe/s/s3cmd/s3cmd_1.6.1-1_all.deb"]
RUN ["dpkg", "-i", "s3cmd_1.6.1-1_all.deb"]

# Add bootstrap script
ADD entrypoint.sh /entrypoint.sh
ADD s3cfg /root/.s3cfg

# Add volumes for Ceph config and data
VOLUME ["/etc/ceph","/var/lib/ceph"]

# Expose the Ceph ports
EXPOSE 6789 6800 6801 6802 6803 6804 6805 80 5000

# Execute the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
