import logging
import os

CEPH_VERSION = os.environ['CEPH_VERSION']
BASEOS_NAME = os.environ['BASEOS_NAME']
BASEOS_TAG = os.environ['BASEOS_TAG']
BASEOS_REG = os.environ['BASEOS_REG']
ARCH = os.environ['ARCH']
IMAGES_TO_BUILD = os.environ['IMAGES_TO_BUILD'].split(' ')
STAGING_DIR = os.environ['STAGING_DIR']
BASE_IMAGE = os.environ['BASE_IMAGE']

logger = logging.getLogger(__name__)


def printGlobal(var):
    varname = [name for name in globals() if globals()[name] is var][0]
    varvalstr = '  {:<16}: {}'.format(varname, var)
    print(varvalstr)
    logger.info(varvalstr)
