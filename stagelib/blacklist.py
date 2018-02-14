# Copyright (c) 2017 SUSE LLC

import logging
import os

logger = logging.getLogger(__name__)


def _parse_condition(rawcondition):
    parts = rawcondition.split('=')
    if not len(parts) == 2:
        raise Exception('Blacklist condition is not properly formatted: {}'.format(rawcondition))
    varname, varvalues = parts[0], parts[1].split(',')
    return (varname, varvalues)


def _conditions_are_met(raw_conditions):
    for rawcondition in raw_conditions:
        varname, varvalues = _parse_condition(rawcondition)
        if os.environ[varname] in varvalues:
            return True
    return False


def _list_files_recursively(inpath):
    allfiles = []
    for dirname, subdirs, files in os.walk(inpath, topdown=True):
        for f in files:
            allfiles.append(os.path.join(dirname, f))
    return allfiles


def _get_blacklisted_items(blacklist_path):
    if os.path.isfile(blacklist_path):
        return [blacklist_path]
    if os.path.isdir(blacklist_path):
        return [os.path.join(blacklist_path, '')]  # make sure dirs end in '/'
    raise Exception('Blacklist path is not a file or directory: {}'.format(blacklist_path))


def _parse_blacklist_item(line):
    splitline = line.split(' ')
    if len(splitline) < 2:
        raise Exception('Blacklist line improperly formatted:\n{}'.format(line))
    if _conditions_are_met(raw_conditions=splitline[1:]):
        logger.info('    Blacklist line matches environment: {}'.format(line))
        return _get_blacklisted_items(splitline[0])
    return []


def _parse_line(line):
    line = line.strip()
    if len(line) == 0 or line[0] == '#':
        return []  # Empty line or comment line
    return _parse_blacklist_item(line)


def get_blacklist(blacklist_filename):
    """
    Returns a list of files that are part of the current blacklist from the given file.
    Blacklist file format is expcted to be:
      <path to be blacklisted> <ENV_VARIABLE>=<value>
    If a current environment <ENV_VARIABLE> is equal to <value>, then there are files to be
    blacklisted. If the <path to be blacklisted> is a file, a list containing only that filename
    is returned. If the <path to be blacklisted> is a directory, a list of all files in the
    directory recursively is returned.
    """
    logger.info('Parsing blacklist file: {}'.format(blacklist_filename))
    blacklist = []
    with open(blacklist_filename) as blacklist_file:
        for line in blacklist_file.readlines():
            blacklist += _parse_line(line)
    return blacklist
