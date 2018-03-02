# Copyright (c) 2017 SUSE LLC

import logging
import os
import sys

try:
    CEPH_VERSION = os.environ['CEPH_VERSION']
    OS_NAME = os.environ['OS_NAME']
    OS_VERSION = os.environ['OS_VERSION']
    BASEOS_REG = os.environ['BASEOS_REG']
    BASEOS_REPO = os.environ['BASEOS_REPO']
    BASEOS_TAG = os.environ['BASEOS_TAG']
    ARCH = os.environ['ARCH']
    # Some tooling requires an amd64 string in the url whenever the ARCH is x86_64
    # GENERIC_ARCH will then represent that alternative name of this ARCH
    GENERIC_ARCH = ARCH
    if ARCH == "x86_64":
        GENERIC_ARCH = "amd64"
    os.environ['GENERIC_ARCH'] = GENERIC_ARCH
    IMAGES_TO_BUILD = os.environ['IMAGES_TO_BUILD'].split(' ')
    STAGING_DIR = os.environ['STAGING_DIR']
except KeyError as k:
    unset_var = k.args[0]
    errtext = """
Expected environment variable '{}' to be set.
Required environment variables:
 - CEPH_VERSION - Ceph named version being built (e.g., luminous, mimic)
 - ARCH - Architecture of binaries being built (e.g., amd64, arm32, arm64)
 - OS_NAME - OS name as used by the ceph-container project (e.g., ubuntu, opensuse)
 - OS_VERSION - OS version as used by the ceph-container project (e.g., 16.04, 42.3 respectively)
 - BASEOS_REG - Registry for the container base image (e.g., _ (default reg), arm32v7, arm64v8)
                There is a relation between binaries built (ARCH) and this value
 - BASEOS_REPO - Repository for the container base image (e.g., ubuntu, opensuse, alpine)
 - BASEOS_TAG - Tagged version of the BASEOS_REPO container (e.g., 16.04, 42.3, 3.6 respectively)
 - IMAGES_TO_BUILD - Container images to be built (usually should be 'dockerfile daemon')
 - STAGING_DIR - Dir into which files will be staged
                 This dir will be overwritten if it already exists

"""
    sys.stderr.write(errtext.format(unset_var))
    sys.exit(1)

logger = logging.getLogger(__name__)


def printGlobal(varname):
    """Print the name and value of a global variable to stdout and to the log"""
    varvalstr = '  {:<16}: {}'.format(varname, globals()[varname])
    print(varvalstr)
    logger.info(varvalstr)
