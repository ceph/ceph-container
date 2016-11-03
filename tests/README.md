Functional image tests
======================

These tests are driven with Python using `py.test`. Install the requirements
in a virtualenv (preferable) and run `py.test` in the current directory.

**note**: By default `py.test` collects all/any tests present from the current
directory recursively. Ensure that no other libraries/virtualenvs are present
in that path, otherwise pass the path to `ceph-docker/tests` directly as an
argument


Avoiding `sudo` for running tests
---------------------------------
To be able to run tests without `sudo` (or not root) ensure that:

* the current user can sudo without a password prompt
* Add the current user to the docker group:

   sudo gpasswd -a ${USER} docker

* Restart the docker service: `sudo systemctl restart docker`
* Activate the group change by logout+login or by: `newgrp docker`
