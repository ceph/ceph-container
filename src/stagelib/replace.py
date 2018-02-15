#!/usr/bin/env python3

import logging
import os
import re

from stagelib.envglobals import *  # noqa: F403, F401

# Support __VARIABLE__ file replacement for variables matching '__<VARIABLE_NAME>__'.
# Support only variables with capital letters and underscores.
VARIABLE_FILE_PATTERN = re.compile('\_\_[A-Z\_]+\_\_')

# Support global variable replacement for variables matching format
# 'STAGE_REPLACE_WITH_<GLOBAL_VAR_NAME>'. Support only globals w/ capital letters and underscores
GLOBAL_PATTERN = re.compile('STAGE_REPLACE_WITH_[A-Z\_]+')

logger = logging.getLogger(__name__)


# Read text from the file
def _get_file_text(file_path):
    with open(file_path, 'r') as txtfile:
        return txtfile.read()


# Given a variable file, read the variable file, and replace it's corresponding
# variable in the text with the contents of the file without trailing space
def _replace_file_in_text(variable_file_path, text, file_path):
    variable = os.path.basename(variable_file_path)
    with open(variable_file_path) as variable_file:
        variable_text = variable_file.read().rstrip()
        if "\n" in variable_text:
            # Output 'user-defined script' if string is multiline
            logging.info('\t{:<80}  :: {:<38} <- {}'.format(file_path, variable, '[user-defined script]'))
        else:
            logging.info('\t{:<80}  :: {:<38} <- {}'.format(file_path, variable, variable_text))
        return text.replace(variable, variable_text)


# Move existing file to <file>.bak. Save text into file.
def _save_with_backup(file_path, text):
    os.rename(file_path, '{}.bak'.format(file_path))
    with open(file_path, 'w') as new_file:
        new_file.write(text)


# Perform
def _file_replace(template_text, file_path, variable_file_dir):
    variable_matches = re.findall(VARIABLE_FILE_PATTERN, template_text)
    if not variable_matches:
        logging.debug('\t{:<80}     [No __VARIABLES__]'.format(file_path))
        return template_text
    # Allow variable files to have their own variables in them
    # by reprocessing until there are no more matches
    while variable_matches:
        for var in variable_matches:
            template_text = _replace_file_in_text(os.path.join(variable_file_dir, var),
                                                  template_text, file_path)
        variable_matches = re.findall(VARIABLE_FILE_PATTERN, template_text)
    return template_text


def _replace_global_in_text(global_var_match, text):
    global_var_name = global_var_match[len('STAGE_REPLACE_WITH_'):]  # strip STAGE_REPLACE_WITH_
    global_value = globals()[global_var_name]
    return text.replace(global_var_match, global_value)


def _global_replace(template_text, file_path):
    variable_matches = re.findall(GLOBAL_PATTERN, template_text)
    if not variable_matches:
        # logging.debug('\t{:<80}  -> {}'.format('No GLOBAL_VARs', file_path))
        logging.debug('\t{:<80}     [No STAGE_REPLACE_WITH_VARs]'.format(file_path))
        return template_text
    for var in variable_matches:
        var_name = var[len('STAGE_REPLACE_WITH_'):]  # strip STAGE_REPLACE_WITH_
        logging.info('\t{:<80}  :: {:<38} <- {}'.format(file_path, var_name, globals()[var_name]))
        template_text = _replace_global_in_text(var, template_text)
    return template_text


def do_variable_replace(replace_root_dir):
    """
    For all files recursively in the replace root dir, do 2 things:
     1. For each __VARIABLE__ in the file, look for a corresponding __VARIABLE__ file in the
        replace root dir, and replace the __VARIABLE__ in the file with the text from the
        corresponding __VARIABLE__ file.
     2. For each STAGE_REPLACE_WITH_<GLOBAL_VAR> variable in the file, replace the variable with
        the content of GLOBAL_VAR.
    __VARIABLE__ files are allowed to contain additional variables. Each file is processed multiple
    times until there are no more __VARIABLES__ to be replaced. GLOBAL_VARs are not allowed to
    contain additional variables. They are only processed once.
    """
    logger.info('    Replacing variables')
    for dirname, subdirs, files in os.walk(replace_root_dir, topdown=True):
        for f in files:
            if re.match(VARIABLE_FILE_PATTERN, f):
                logging.debug('\t{:<80}     [Skip __VARIABLE__ replace]'.format(os.path.join(dirname, f)))
                continue
            file_path = os.path.join(dirname, f)
            template_text = _get_file_text(file_path)
            text = _file_replace(template_text, file_path, variable_file_dir=replace_root_dir)
            text = _global_replace(text, file_path)
            if not text == template_text:
                # Only save if there have been changes
                _save_with_backup(os.path.join(dirname, f), text)
