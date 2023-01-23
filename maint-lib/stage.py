#!/usr/bin/env python3
# Copyright (c) 2017 SUSE LLC

import os
import logging
import shutil
import sys
import time

from collections import OrderedDict

from stagelib.envglobals import (verifyRequiredEnvVars, verifyRequiredEnvVar, getEnvVar,
                                 exportGitInfoEnvVars, exportGoArchEnvVar, exportBaseImageEnvVar)
from stagelib.filetools import (list_files, mkdir_if_dne, copy_files, recursive_copy_dir,
                                IOOSErrorGracefulFail, save_files_copied)
from stagelib.replace import do_variable_replace


# Set default values for tunables (primarily only interesting for testing)
CORE_FILES_DIR = "src"
CEPH_RELEASES_DIR = "ceph-releases"


STAGING_DIR = getEnvVar('STAGING_DIR')
# Start with empty staging dir so there are no previous artifacts
try:
    if os.path.isdir(STAGING_DIR):
        shutil.rmtree(STAGING_DIR)
    os.makedirs(STAGING_DIR, mode=0o755)
except (OSError, IOError) as o:
    IOOSErrorGracefulFail(
        o, 'Could not delete and recreate staging dir: {}'.format(STAGING_DIR))


LOG_FILE = os.path.join(STAGING_DIR, "stage.log")
loglevel = logging.INFO
# If DEBUG env var is set to anything (including empty string) except '0', log debug text
if 'DEBUG' in os.environ and not os.environ['DEBUG'] == '0':
    loglevel = logging.DEBUG
logging.basicConfig(filename=LOG_FILE, level=loglevel, format='%(levelname)5s:  %(message)s')

# Build dependency on python3 for `replace.py`. Looking to py2.7 deprecation in 2020.
if sys.version_info[0] < 3:
    print('This must be run with Python 3+')
    sys.exit(1)


def main(CORE_FILES_DIR, CEPH_RELEASES_DIR):
    logging.info('\n\n\n')  # Make it easier to determine where new runs start
    logging.info('Start time: {}'.format(time.ctime()))

    print('')
    verifyRequiredEnvVars()
    print('')

    # Treat BASE_IMAGE as required var
    print('Computed:')
    logging.info('Computed:')
    exportBaseImageEnvVar()
    verifyRequiredEnvVar('BASE_IMAGE')
    print('')

    exportGitInfoEnvVars()
    logging.info('GIT_REPO:   {}'.format(getEnvVar('GIT_REPO')))
    logging.info('GIT_BRANCH: {}'.format(getEnvVar('GIT_BRANCH')))
    logging.info('GIT_COMMIT: {}'.format(getEnvVar('GIT_COMMIT')))
    logging.info('GIT_CLEAN:  {}'.format(getEnvVar('GIT_CLEAN')))

    exportGoArchEnvVar()
    logging.info('GO_ARCH: {}'.format(getEnvVar('GO_ARCH')))

    CEPH_VERSION = getEnvVar('CEPH_VERSION')
    CEPH_DEVEL = getEnvVar('CEPH_DEVEL')
    DISTRO = getEnvVar('DISTRO')
    DISTRO_VERSION = getEnvVar('DISTRO_VERSION')
    IMAGES_TO_BUILD = getEnvVar('IMAGES_TO_BUILD').split(' ')
    # STAGING_DIR is gotten globally

    # Search from least specfic to most specific
    path_search_order = [
        "{}".format(CORE_FILES_DIR),
        os.path.join(CEPH_RELEASES_DIR, 'ALL'),
        os.path.join(CEPH_RELEASES_DIR, 'ALL', DISTRO),
        os.path.join(CEPH_RELEASES_DIR, 'ALL', DISTRO, DISTRO_VERSION),
        os.path.join(CEPH_RELEASES_DIR, CEPH_VERSION),
        os.path.join(CEPH_RELEASES_DIR, CEPH_VERSION, DISTRO),
        os.path.join(CEPH_RELEASES_DIR, CEPH_VERSION, DISTRO, DISTRO_VERSION),
    ]
    logging.debug('Path search order: {}'.format(path_search_order))

    files_copied = OrderedDict()
    # e.g., IMAGES_TO_BUILD = ['base']
    for image in IMAGES_TO_BUILD:
        logging.info('')
        logging.info('{}/'.format(image))
        logging.info('    Copying files (preceding * indicates file has been modified)')
        for src_path in path_search_order:
            if not os.path.isdir(src_path):
                continue
            src_files = list_files(src_path)
            staging_path = os.path.join(STAGING_DIR, image)
            mkdir_if_dne(staging_path, mode=0o755)
            # Copy files in each path first, then copy contents of <image> dir
            copy_files(src_files, src_path, staging_path, files_copied)
            recursive_copy_dir(src_path=os.path.join(src_path, image), dst_path=staging_path,
                               files_copied=files_copied)
        # Do variable replacements on all files in <staging>/<image>
        do_variable_replace(replace_root_dir=os.path.join(STAGING_DIR, image))

    # Save a file named files-sources to the staging dir
    save_files_copied(files_copied, os.path.join(STAGING_DIR, 'files-sources'),
                      strip_prefix=os.path.join(STAGING_DIR, ''))
    copy_files(['find-src'], 'maint-lib/stagelib', STAGING_DIR)


if __name__ == "__main__":
    main(CORE_FILES_DIR, CEPH_RELEASES_DIR)
