`__WEB_INSTALL_<PACKAGE>__` definitions are provided here as a sensible default for all distros that
wish to install the package in question via a `wget` and manual extraction. These definitions are
placed in the `ceph-releases/ALL/daemon` dir rather than `src/daemon`, as installation of packages
defined by `src/daemon/__DAEMON_PACKAGES__` and the system package manager is the preferred method
for installation where possible.
