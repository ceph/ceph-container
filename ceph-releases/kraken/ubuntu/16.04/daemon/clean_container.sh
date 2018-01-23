#!/bin/bash
# Let's remove easy stuff
strip -s /usr/local/bin/{confd,forego,kubectl}
strip -s /usr/bin/{crushtool,monmaptool,osdmaptool}
rm -rf /usr/share/{doc,info,locale,man}/*
rm -rf /tmp/* /var/tmp/* /usr/bin/hyperkube /usr/bin/etcd

# Let's compress fat binaries but keep them executable
# As we don't run them often, the performance penalty isn't that big
for binary in /usr/local/bin/{confd,forego,kubectl} /usr/bin/etcdctl; do
  gzexe $binary && rm -f ${binary}~
done

# Let's remove all the pre-compiled python files, if needed they will be rebuilt
find  / -xdev -name "*.pyc" -exec rm {} \;

# Some logfiles are not empty, there is no need to keep them
find /var/log/ -type f -exec truncate -s 0 {} \;
