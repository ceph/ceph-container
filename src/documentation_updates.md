Build dependency on python3 for `replace.py`. Looking to py2.7 deprecation in 2020.


Override priority (higher overrides lower):
```
# Most specific
<specific ceph release>/<specific os distro>/<specific os release>/FILE
<specific ceph release>/<specific os distro>/FILE
<specific ceph release>/FILE
all_ceph_releases/<specific os distro>/<specific os release>/FILE
all_ceph_releases/<specific os distro>/FILE
all_ceph_releases/FILE
core/FILE
# Least specific
```

TODO: meta/blacklist file
