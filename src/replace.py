#!/usr/bin/env python3

# Perform __VARIABLE__ replacements file as first argument.
# Search the file's directory for '__VARIABLE__' files

import os
import re
import sys

if sys.version_info[0] < 3:
    print('This must be run with Python 3+')
    sys.exit(1)

if len(sys.argv) != 2:
    print('The script was not called with one argument (the working dir)')
    sys.exit(2)

template_filename = sys.argv[1]
file_path = os.path.dirname(template_filename)

print('Performing replacements on {0}'.format(template_filename))

# Only support variables with capital letters and underscores and
# surrounded by double underscores
variable_pattern = re.compile('\_\_[A-Z\_]+\_\_')

with open(template_filename, 'r') as template_file:
    template_text = template_file.read()
    variable_matches = re.findall(variable_pattern, template_text)

new_text = template_text
for variable in variable_matches:
    print('Replacing {}'.format(variable))
    variable_filename = '{}/{}'.format(file_path, variable)
    with open(variable_filename) as variable_file:
        variable_text = variable_file.read().rstrip()
        # print('with {}'.format(variable_text))
        new_text = new_text.replace(variable, variable_text)

new_filename = '{}.new'.format(template_filename)
with open(new_filename, 'w') as generated_file:
    generated_file.write(new_text)
