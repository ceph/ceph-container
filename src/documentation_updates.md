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


The staging script (written in python) outputs a `stage.log` file which writes info messages by
default. If the `DEBUG` environment variable is set to any value, debug messages will also be
printed to the log. Debug output can be explicitly disabled with `unset DEBUG` or by setting
`DEBUG=0`. Any other value of `DEBUG` will enable debug output.
