#!/bin/bash
DEBUG=

# Step 1
# Let's remove easy stuff
strip -s /usr/local/bin/{confd,forego}

# Compressing those very big binaries
# As we don't run them often, the peformance penalty isn't huge
for binary in /usr/bin/{etcdctl,kubectl} /usr/local/bin/{forego,confd}; do
  gzexe $binary && rm ${binary}~
done

# Let's remove all the pre-compiled python files, if needed they will be rebuilt
find  / -xdev -name "*.pyc" -exec rm {} \; # 23MB of pyc

if [ -n "$DEBUG" ]; then
  find / -xdev -type f  -exec du -c {} \; |sort -n
fi
