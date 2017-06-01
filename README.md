# docker-ceph

Ceph-related Docker files.

## Core Components:

- [`ceph/base`](ceph-releases/jewel/ubuntu/14.04/base/): Ceph base container image. This is nothing but a fresh install of the latest Ceph + Ganesha on Ubuntu LTS (14.04)
- [`ceph/daemon`](ceph-releases/jewel/ubuntu/14.04/daemon/): All-in-one container for all core daemons.

See README files in subdirectories for instructions on using containers.

## Demo

- [`ceph/demo`](ceph-releases/jewel/ubuntu/14.04/demo/): Demonstration cluster for testing and learning. This container runs all the major ceph and ganesha components installed, bootstrapped, and executed for you to play with. (not intended for use in building a production cluster)

# How to contribute?!

The following assumes that you already forked the repository, added the correct remote and are familiar with git commands.

## Prepare your development environment

Simply execute `./generate-dev-env.sh CEPH_RELEASE DISTRO DISTRO_VERSION`. For example if you run `./generate-dev-env.sh jewel ubuntu 16.04` the script will:

- hardlink the files from `ceph-releases/jewel/ubuntu/16.04/{base,daemon,demo}` in `./base`, `./daemon` and `./demo`.
- create a file in `{base,daemon,demo}/SOURCE_TREE` which will remind you the version you are working on.

From this, you can start modifying your code and building your images locally.

## My code is ready, what's next?

Contributions must go in the 'ceph-releases' tree, in the appropriate Ceph version, distribution and distribution version. So once you are done, we can just run:

- `cp -av base $(cat base/SOURCE_TREE)`
- `cp -av daemon $(cat base/SOURCE_TREE)`
- `cp -av demo $(cat base/SOURCE_TREE)`

We identified 2 types of contributions:

### Distro specific contributions

The code only changes the `base` image content of a specific distro, nothing to replicate or change for the other images..

### New functionality contributions

If you look at the ceph-releases directory you will notice that for each release the daemon image's content is symlinked to the Ubuntu daemon 14.04. Even if we support multi-distro, Ubuntu 14.04 remains the default. It would nice if you could get familiar with this approach. This basically means that if you are testing on CentOS then you should update the Ubuntu image instead. All the changes in the entrypoints _should not_ diverse from one distro to another, so this should be safe :). We are currently **only** bringing new functionality in the `jewel` release.

# CI

We use Travis to run several tests on each pull request:

- we build both `base` and `daemon` images
- we run all the ceph processes in a container based on the images we just built
- we execute a validation script at the end to make sure Ceph is healthy

For each PR, we try to detect which Ceph release is being impacted. Since we can only produce a single CI build with Travis, ideally this change will only be on a single release and distro. If we have multiple ceph release and distro, we can only test one, since we have to build `base` and `daemon`. By default, we just pick up the first line that comes from the changes.

You can check the files in `travis-builds` to learn more about the entire process.

If you don't want to run a build for a particular commit, because all you are changing is the README for example, add `[ci skip]` to the git commit message. Commits that have `[ci skip]` anywhere in the commit messages are ignored by Travis CI.

We are also transitioning to have builds in Jenkins, this is still a work in
progress and will start taking precedence once it is solid enough. Be sure to
check the links and updates provided on pull requests.

# Images workflow

Once your contribution is done and merged in master. Either @Ulexus or @leseb will execute `ceph-docker-workflow.sh`, this will basically compare the content of each tag/branch to master. If any difference is found it will push the appropriate changes in each individual branches. Ultimately new pushed tags will trigger a Docker build on the Docker Hub.

# Video demonstration

## Manually

A recorded video on how to deploy your Ceph cluster entirely in Docker containers is available here:

[![Demo Running Ceph in Docker containers](http://img.youtube.com/vi/FUSTjTBA8f8/0.jpg)](http://youtu.be/FUSTjTBA8f8 "Demo Running Ceph in Docker containers")

## With Ansible

[![Demo Running Ceph in Docker containers with Ansible](http://img.youtube.com/vi/DQYZU1VsqXc/0.jpg)](http://youtu.be/DQYZU1VsqXc "Demo Running Ceph in Docker containers with Ansible")
