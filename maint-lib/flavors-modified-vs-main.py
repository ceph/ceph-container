#!/usr/bin/env python3
# Copyright (c) 2017 SUSE LLC

import os
import re
import subprocess
import sys


def _fatal(message):
    sys.stderr.write(message)
    sys.exit(1)


def _run_cmd(cmd_array):
    return subprocess.check_output(cmd_array).decode("utf-8")


# Stage the flavor and return the staging dir
def _stage_flavor(flavor):
    stage_output = _run_cmd(['make', 'FLAVORS=' + flavor, 'stage'])
    staging_dir_pattern = re.compile(r'^\s*STAGING_DIR\s*:\s+(.*)$', re.MULTILINE)
    match = staging_dir_pattern.search(stage_output)
    if not match or not match[1] or match[1] == '':
        _fatal("Could not find staging dir for:\n{}".format(stage_output))
    return match[1]


def _filediff_intersects_sources(filediff, sources):
    for f in filediff.splitlines():
        file_pattern = re.compile(r'^.*\s+<-\s+' + f + '$', re.MULTILINE)
        match = file_pattern.search(sources)
        if match:
            return True
    return False


# By default, compare to origin/main, but allow VS_BRANCH env var to be set to change this
VS_BRANCH = 'origin/main'
if 'VS_BRANCH' in os.environ and not os.environ['VS_BRANCH'] == '':
    VS_BRANCH = os.environ['VS_BRANCH']
VS_BRANCH_SPLIT = VS_BRANCH.split('/')

# Get list of files different from VS_BRANCH
try:
    _ = _run_cmd(['git', 'fetch'] + VS_BRANCH_SPLIT + ['--quiet'])
except subprocess.CalledProcessError:
    _fatal("Could not fetch {}! Check that the branch exists!".format(VS_BRANCH_SPLIT.join(' ')))

try:
    filediff = _run_cmd(['git', 'diff', '--name-only', VS_BRANCH])
except subprocess.CalledProcessError:
    _fatal("Could not get file diff against branch '{}'!".format(VS_BRANCH))

# Files that haven't been committed don't show up in git diff, so also list those
modified_files_with_status = _run_cmd(['git', 'status', '--short'])
modified_files = ""
for line in modified_files_with_status.splitlines():
    # Strip Status (2 chars and a space) from each status line
    modified_files += line[3:] + '\n'

# Combine uncommitted files with our filediff list. There may be duplicates, but it won't matter.
filediff += modified_files

for flavor in str(os.environ['ALL_BUILDABLE_FLAVORS']).split():
    staging_dir = _stage_flavor(flavor)
    with open(os.path.join(staging_dir, 'files-sources'), 'r') as sources_file:
        sources = sources_file.read()
        if _filediff_intersects_sources(filediff, sources):
            print(flavor)
            continue  # continue with next flavor
