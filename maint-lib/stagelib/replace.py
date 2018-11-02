# Copyright (c) 2017 SUSE LLC

import logging
import os
import re
import sys

from stagelib.filetools import save_text_to_file, IOOSErrorGracefulFail

# Support __VARIABLE__ file replacement for variables matching '__<VARIABLE_NAME>__'.
# Support only variables with capital letters and underscores.
VARIABLE_FILE_PATTERN = re.compile('\_\_[A-Z\_0-9]+\_\_')

# Support global variable replacement for variables matching format
# '__ENV_[<GLOBAL_VAR_NAME>]__'. Support only globals w/ capital letters and underscores
GLOBAL_PATTERN = re.compile(r'\_\_ENV\_\[([A-Z\_0-9]+)\]\_\_')

REPLACE_LOGTEXT = "        {:<30} <- '{:<44}'  :: {}"
PARENTHETICAL_LOGTEXT = '        {:>80}     {}'


# Read text from the file
def _get_file_text(file_path):
    try:
        with open(file_path, 'r') as txtfile:
            return txtfile.read()
    except (OSError, IOError) as o:
        IOOSErrorGracefulFail(o, "Cannot read or decode {} \n".format(file_path))


# Given a variable file, read the variable file, and replace it's corresponding
# variable in the text with the contents of the file without trailing space
def _replace_file_in_text(variable_file_path, text, file_path):
    variable = os.path.basename(variable_file_path)
    with open(variable_file_path) as variable_file:
        variable_text = variable_file.read().rstrip()
        if "\n" in variable_text or len(variable_text) > 46:
            # Output 'user-defined script' if string is multiline
            logging.info(REPLACE_LOGTEXT.format(variable, '[user-defined script]', file_path))
        else:
            logging.info(REPLACE_LOGTEXT.format(variable, variable_text, file_path))
        return text.replace(variable, variable_text)


# Move existing file to <file>.bak. Save text into file.
def _save_with_backup(file_path, text):
    try:
        os.rename(file_path, '{}.bak'.format(file_path))
    except (OSError, IOError) as o:
        IOOSErrorGracefulFail(o, "Could not rename file {0} to {0}.bak".format(file_path))
    save_text_to_file(text, file_path)


# Perform __VAR__ file replacement on text. Seek __VAR__ file at dir/path
def _file_replace(template_text, file_path, variable_file_dir):
    variable_matches = re.findall(VARIABLE_FILE_PATTERN, template_text)
    if not variable_matches:
        return 0, template_text
    for var in variable_matches:
        template_text = _replace_file_in_text(os.path.join(variable_file_dir, var),
                                              template_text, file_path)
    variable_matches = re.findall(VARIABLE_FILE_PATTERN, template_text)
    return len(variable_matches), template_text


# Perform __ENV_[VAR]__ replacement on text.
def _env_var_replace(template_text, file_path):
    variable_matches = re.findall(GLOBAL_PATTERN, template_text)
    if not variable_matches:
        # logging.debug('        {:<80}  -> {}'.format('No GLOBAL_VARs', file_path))
        return 0, template_text
    for var_name in variable_matches:
        text_to_replace = '__ENV_[' + var_name + ']__'
        try:
            var_value = os.environ[var_name]
        except KeyError:
            sys.stderr.write(
                'Variable {} in {} could not be replaced, because the env var {} is unset'.format(
                    text_to_replace, file_path, var_name))
            sys.exit(1)
        logging.info(REPLACE_LOGTEXT.format(text_to_replace, var_value, file_path))
        template_text = template_text.replace(text_to_replace, var_value)
    return len(variable_matches), template_text


# Given a file path, do file and env replacements on it repeatedly until no replacements are made
# Return total number of replacements made, and rendered text
def _do_replace_on_file(file_path, replace_root_dir):
    rendered_text = _get_file_text(file_path)
    total_file_replacements, total_env_replacements = 0, 0
    while True:
        file_replacements, rendered_text = _file_replace(
            rendered_text, file_path, variable_file_dir=replace_root_dir)
        env_replacements, rendered_text = _env_var_replace(rendered_text, file_path)
        total_file_replacements += file_replacements
        total_env_replacements += env_replacements
        if file_replacements == 0 and env_replacements == 0:
            break
    if not total_file_replacements:
        logging.debug(PARENTHETICAL_LOGTEXT.format(
            '[No __VARIABLES__ to replace]', file_path))
    if not total_env_replacements:
        logging.debug(PARENTHETICAL_LOGTEXT.format(
            '[No __ENV_[VAR]__s to replace]', file_path))
    return (total_file_replacements + total_env_replacements), rendered_text


def do_variable_replace(replace_root_dir):
    """
    For all files recursively in the replace root dir, do 2 things:
     1. For each __VARIABLE__ in the File, look for a corresponding __VARIABLE__ file in the
        replace root dir, and replace the __VARIABLE__ in the File with the text from the
        corresponding __VARIABLE__ file.
     2. For each __ENV_[<ENV_VAR>]__ variable in the File, replace the variable in the File with
        the content of the environment variable ENV_VAR.
    Variables are allowed to contain nested variables of either type.
    """
    logging.info('    Replacing variables')
    for dirname, subdirs, files in os.walk(replace_root_dir, topdown=True):
        for f in files:
            # do not process the tarball
            # this prevents the following error:
            # UnicodeDecodeError: 'utf-8' codec can't decode byte 0x8b in position 1: invalid start byte
            if "Sree-" in f:
                continue
            if re.match(VARIABLE_FILE_PATTERN, f):
                logging.debug(PARENTHETICAL_LOGTEXT.format(
                    '[Skip __VARIABLE__ replace]', os.path.join(dirname, f)))
                continue
            file_path = os.path.join(dirname, f)
            total_replacements, rendered_text = _do_replace_on_file(file_path, replace_root_dir)
            if total_replacements > 0:
                # Only save if there have been changes
                _save_with_backup(file_path, rendered_text)
