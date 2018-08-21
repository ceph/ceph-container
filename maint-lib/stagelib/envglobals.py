# Copyright (c) 2017 SUSE LLC

import logging
import os
import sys

from collections import OrderedDict

import stagelib.git as git

ALIGNED_NEWLINE = '\n' + ' ' * 21  # align second line to column
# Ordered dict with format
# <var name>: <description>
# Add new required variables simply by adding a new tuple to this setup
# Allow lines to extend beyond 99 char limit by 6 chars to support output formatting to 100 cols
REQUIRED_ENV_VARS = OrderedDict([
    ('CEPH_VERSION',       'Ceph named version part of the ceph-releases source path' +  # noqa: E241,E501
                            ALIGNED_NEWLINE + '(e.g., luminous, mimic)'),  # noqa: E241
    ('CEPH_POINT_RELEASE', 'Points to specific version of Ceph (e.g -12.2.0) or empty'),  # noqa: E241,E501
    ('DISTRO',             'Distro part of the ceph-releases source path (e.g., opensuse, centos)'),  # noqa: E241,E501
    ('DISTRO_VERSION',     'Distro version part of the ceph-releases source path' +  # noqa: E241,E501
                            ALIGNED_NEWLINE + '(e.g. in quotes, opensuse/"42.3", centos/"7")'),
    ('HOST_ARCH',          'Architecture of binaries being built (e.g., amd64, arm32, arm64)'),  # noqa: E241,E501
    ('BASEOS_REGISTRY',    'Registry for the container base image (e.g., _ (x86_64), arm64v8 (aarch64))' +  # noqa: E241,E501
                            ALIGNED_NEWLINE + 'There is a relation between HOST_ARCH and this value'),  # noqa: E241,E501
    ('BASEOS_REPO',        'Repository for the container base image (e.g., centos, opensuse)'),  # noqa: E241,E501
    ('BASEOS_TAG',         'Tagged version of BASEOS_REPO container (e.g., 7, 42.3 respectively)'),  # noqa: E241,E501
    ('IMAGES_TO_BUILD',    'Container images to be built (usually should be "dockerfile daemon")'),  # noqa: E241,E501
    ('STAGING_DIR',        'Dir into which files will be staged' + ALIGNED_NEWLINE +  # noqa: E241
                           'This dir will be overwritten if it already exists'),  # noqa: E241
    ('RELEASE',            'Release string for the build'),  # noqa: E241
    ('DAEMON_BASE_IMAGE',  'Tag given to the daemon-base image and used as base for the daemon image'),  # noqa: E241,E501
    ('DAEMON_IMAGE',       'Tag given to the daemon image'),  # noqa: E241
])
_REQUIRED_VAR_TEXT = """
Required environment variables:
"""
for env_var, description_text in REQUIRED_ENV_VARS.items():
    _REQUIRED_VAR_TEXT += "  {:<18} {}\n".format(env_var, description_text)
_NOT_SET_TEXT = """
ERROR: Expected environment variable '{}' to be set."""


def verifyRequiredEnvVar(varname):
    """
    Verify that an environment variable is set. Return the value of the variable if it exists.
    As these variables are required and excellent for viewing during program run, print them to
    stdout and to the log.
    """
    if varname not in os.environ:
        sys.stderr.write(_NOT_SET_TEXT.format(varname))
        sys.stderr.write(_REQUIRED_VAR_TEXT.format(varname))
        sys.exit(1)
    varval = os.environ[varname]
    varvalstr = '  {:<18}: {}'.format(varname, varval)
    print(varvalstr)
    logging.info(varvalstr)
    return varval


def verifyRequiredEnvVars():
    """Verify that all required environment variables are set. Error and exit if one is not set."""
    for var in REQUIRED_ENV_VARS:
        verifyRequiredEnvVar(var)


def getEnvVar(varname):
    """Get the value of an environment variable. Error and exit if it is not set."""
    if varname not in os.environ:
        sys.stderr.write(_NOT_SET_TEXT.format(varname))
        sys.exit(1)
    return os.environ[varname]


def exportBaseImageEnvVar():
    BASE_IMAGE = "{}:{}".format(getEnvVar('BASEOS_REPO'), getEnvVar('BASEOS_TAG'))
    if getEnvVar('BASEOS_REGISTRY'):
        BASE_IMAGE = "{}/{}".format(getEnvVar('BASEOS_REGISTRY'), BASE_IMAGE)
    os.environ['BASE_IMAGE'] = BASE_IMAGE


def exportGitInfoEnvVars():
    """
    Export git-related environment variables to the current environment so they may be used later
    for variable replacements.
    Variables set:
     - GIT_REPO - current repo
     - GIT_COMMIT - current commit hash
     - GIT_BRANCH - current branch
     - GIT_CLEAN - "False" if there are uncommitted changes in branch, "True" otherwise
    """
    # Exporting git information as variables
    GIT_REPO = git.get_repo()
    os.environ['GIT_REPO'] = GIT_REPO
    GIT_COMMIT = git.get_hash()
    os.environ['GIT_COMMIT'] = GIT_COMMIT
    GIT_BRANCH = git.get_branch()
    os.environ['GIT_BRANCH'] = GIT_BRANCH
    GIT_CLEAN = not git.branch_is_dirty()
    os.environ['GIT_CLEAN'] = "{}".format(GIT_CLEAN)


# Some Ceph architectures aren't the same string as golang architectures, so specify conversions
_CEPH_ARCH_TO_GOLANG_ARCH_CONVERSIONS = {
    'x86_64': 'amd64',
    'aarch64': 'arm64'
}


def exportGoArchEnvVar():
    """
    Export the environment variable 'GO_ARCH' with the golang architecture equivalent to the
    current Ceph arch. E.g., Ceph arch 'x86_64' equates to golang arch 'amd64'.
    """
    arch = getEnvVar('HOST_ARCH')
    if arch in _CEPH_ARCH_TO_GOLANG_ARCH_CONVERSIONS:
        os.environ['GO_ARCH'] = _CEPH_ARCH_TO_GOLANG_ARCH_CONVERSIONS[arch]
    else:
        os.environ['GO_ARCH'] = arch
