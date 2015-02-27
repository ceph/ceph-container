#!/bin/bash
set -e

# Expected environment variables:
#   RGW_NAME - (name of rados gateway server)
# Usage:
#   docker run -e RGW_NAME=myrgw ceph/radosgw

if [ ! -n "$RGW_NAME" ]; then
  echo "ERROR- RGW_NAME must be defined as the name of the rados gateway server"
  exit 1
fi

if [ ! -e /etc/ceph/ceph.conf ]; then
  echo "ERROR- /etc/ceph/ceph.conf must exist; get it from another ceph node"
   exit 2
fi

# Configure rados gateway necessary components
a2enmod rewrite > /dev/null 2>&1
a2dissite *default > /dev/null 2>&1

tee /var/www/s3gw.fcgi > /dev/null <<EOF
#!/bin/sh
exec /usr/bin/radosgw -c /etc/ceph/ceph.conf -n client.radosgw.gateway
EOF
chmod +x /var/www/s3gw.fcgi

# Make sure the directory exists
mkdir -p /var/lib/ceph/radosgw/${RGW_NAME}

# Check to see if our RGW has been initialized
if [ ! -e /var/lib/ceph/radosgw/${RGW_NAME}/keyring ]; then
  # Add RGW key to the authentication database
  if [ ! -e /etc/ceph/ceph.client.admin.keyring ]; then
    echo "Cannot authenticate to Ceph monitor without /etc/ceph/ceph.client.admin.keyring.  Retrieve this from /etc/ceph on a monitor node."
    exit 1
  fi
  ceph auth get-or-create client.radosgw.gateway osd 'allow rwx' mon 'allow rw' -o /var/lib/ceph/radosgw/${RGW_NAME}/keyring
fi

# Configure Apache
echo "ServerName $(hostname)" > /etc/apache2/httpd.conf

# Configure rados gateway vhost
tee /etc/apache2/sites-available/rgw.conf > /dev/null <<EOF
FastCgiExternalServer /var/www/s3gw.fcgi -socket /tmp/radosgw.sock
<VirtualHost *:80>
        ServerName $(hostname)
        DocumentRoot /var/www

        <IfModule mod_fastcgi.c>
                <Directory /var/www>
                        Options +ExecCGI
                        AllowOverride All
                        SetHandler fastcgi-script
                        Order allow,deny
                        Allow from all
                        AuthBasicAuthoritative Off
                </Directory>
        </IfModule>

        RewriteEngine On
        RewriteRule ^/([a-zA-Z0-9-_.]*)([/]?.*) /s3gw.fcgi?page=$1&params=$2&%{QUERY_STRING} [E=HTTP_AUTHORIZATION:%{HTTP:Authorization},L]

</VirtualHost>
EOF

# Enable the gateway configuration
a2ensite rgw.conf > /dev/null 2>&1

# Start apache and radosgw
source /etc/apache2/envvars
/startRadosgw

