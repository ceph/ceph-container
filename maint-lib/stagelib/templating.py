# Copyright (c) 2017 SUSE LLC

import logging
import os
import sys
import yaml

import jinja2

from stagelib.filetools import (
    read_text_from_file,
    read_text_from_file_if_exists,
    save_text_to_file,
    save_text_to_file_with_backup,
)
from stagelib.merge_dicts import merge_dicts

TEMPLATE_FILE = 'template-parameters.yaml'


def is_template_param_file(file_path):
    return True if os.path.basename(file_path) == TEMPLATE_FILE else False


LOAD_YAML_ERR_TEXT = 'Could not load template parameters from file {} because {}\n\n'


def _fatal_yaml(file_path, message):
    sys.stderr.write(LOAD_YAML_ERR_TEXT.format(file_path, message))
    sys.exit(1)


# Return list of dicts where each dict is a YAML file section
def _load_yaml_file(file_path):
    file_text = read_text_from_file_if_exists(file_path)
    try:
        yaml_sections = list(yaml.load_all(file_text))
        return yaml_sections
    except yaml.YAMLError as e:
        sys.stderr.write(LOAD_YAML_ERR_TEXT.format(file_path, e))
        sys.exit(1)


def load_template_param_file(file_path):
    """
    Load a template parameter YAML file. Expect the file to have only a single YAML section, and
    that section must have only a single top-level entry titled 'template'
    """
    sections = _load_yaml_file(file_path)
    if not len(sections) == 1:
        _fatal_yaml(file_path,
                    'the number of defined YAML sections is {} and not 1'.format(len(sections)))
    entries = sections[0]
    if (not len(entries) == 1) or ('template' not in entries):
        _fatal_yaml(file_path,
                    "there should be only one entry named 'template' instead of {}".format(
                        list(entries.keys())))
    return entries


def params_to_file_text(params):
    return yaml.dump(params)


def merge_template_param_files(base_file_path, override_file_path):
    if os.path.isfile(base_file_path):
        base_params = load_template_param_file(base_file_path)
    else:
        base_params = {}
    override_params = load_template_param_file(override_file_path)
    merged_params = merge_dicts(base_params, override_params)
    save_text_to_file(params_to_file_text(merged_params), base_file_path)


PARENTHETICAL_LOGTEXT = '        {:>80}     {}'


def _render_err(file_path, error, template, data):
    import pprint
    lineno = 'N/A'
    if hasattr(error, 'lineno'):
        # If error has lineno, show it
        lineno = error.lineno
    if hasattr(error, 'filename'):
        # If error indicates a specific file, show that instead
        template = open(error.filename, 'r').read()
    # Add line numbers to our template output
    template_numbered, i = '', 0
    for line in template.splitlines():
        i += 1
        template_numbered += '{:<3} : {}\n'.format(i, line)
    sys.stderr.write("""
While rendering file {0} ...

{1}:{2} at line {3}

offending template:
{4}

offending data:
template =
{5}
\n
""".format(file_path, error.__class__.__name__, str(error), lineno, template_numbered,
           pprint.pformat(data, width=100)))
    sys.exit(1)


# def _render_loop(template_text, template_parameters, file_path):
#     i = 0
#     while True:
#         prev_template_text = template_text
#         try:
#             # In order to use use the jinja environment settings, we need to set a loader, which
#             # we will just make a basic text passthrough.
#             jinja_env = jinja2.Environment(
#                 loader=jinja2.FunctionLoader(lambda text: text),
#                 trim_blocks=True, undefined=jinja2.StrictUndefined
#             )
#             template = jinja_env.get_template(template_text)
#             template_text = template.render(template=template_parameters['template'],
#                                             env=os.environ)  # Allow getting from os environment
#         except jinja2.exceptions.UndefinedError as u:
#             _render_err(file_path, u, template_text, template_parameters['template'])
#         except jinja2.exceptions.TemplateSyntaxError as t:
#             _render_err(file_path, t, template_text, '[data is not offending]')
#         except Exception as e:
#             _render_err(file_path, e, template_text, template_parameters['template'])
#         if template_text == prev_template_text:
#             break  # Template rendering made no changes, so we're done
#         # Save intermediate files as <index>.bak so we can debug the template progression
#         save_text_to_file(prev_template_text, "{}.{}.bak".format(file_path, i))
#         i += 1
#     return template_text


@jinja2.contextfilter
def _jinja_filter_interpret(context, value):
    template = context['template']  # noqa: F841
    try:
        evaled = eval(value)
        print('evaled {}: {}'.format(type(evaled), evaled))
        return evaled
    except Exception:
        return value


def _attempt_deserialization(value):
    print('attempt deserialize: {}'.format(value))
    if not isinstance(value, str):
        return value  # we can only deserialize strings
    try:
        if ((value.startswith('{') and value.endswith('}')) or
                (value.startswith('[') and value.endswith(']'))):
            # We hope it's a dict
            deserialized = eval(value)
            if isinstance(deserialized, dict) or isinstance(deserialized, list):
                return deserialized
    except Exception:
        pass  # If we fail, we assume it's because the value can't be deserialized
    return value


@jinja2.contextfunction
def _jinja2_recursive_render(context, value=''):
    # YAML only gives a few basic Python types, which we can render recursively: str, list, dict
    if isinstance(value, str) and ('{{' in value or '{%' in value or '{#' in value):
        # Is a string that is a sub-template
        env_template = context.environment.from_string(value)
        rendered = _attempt_deserialization(env_template.render(context))
        return rendered
    if isinstance(value, dict):
        # If we find a dict, recursively render each value in the dict
        for k, v in value.items():
            value[k] = _jinja2_recursive_render(context, v)
        return value
    if isinstance(value, list):
        # If we find a list, recursively render each list item
        newlist = []
        for i in value:
            newlist.append(_jinja2_recursive_render(context, i))
        return newlist
    return value


@jinja2.contextfilter
def _jinja2_filter_render(context, value):
    print('attempt render {}'.format(value))
    return _jinja2_recursive_render(context, value)


def _jinja2_build_env(template_dir):
    jinja_env = jinja2.Environment(loader=jinja2.FileSystemLoader(searchpath=template_dir),
                                   trim_blocks=True, lstrip_blocks=True,
                                   undefined=jinja2.StrictUndefined,
                                   finalize=_jinja2_recursive_render)
    jinja_env.filters['render'] = _jinja2_filter_render
    return jinja_env


def _render(template_dir, template_file, template_parameters):
    jinja_env = _jinja2_build_env(template_dir)
    file_path = os.path.join(template_dir, template_file)
    template_text = read_text_from_file(file_path)  # for debugging failures
    try:
        template = jinja_env.get_template(template_file)
        rendered_text = template.render(template=template_parameters, env=os.environ)
        return rendered_text
    except jinja2.exceptions.TemplateSyntaxError as t:
        _render_err(file_path, t, template_text, '[data is not offending]')
    except Exception as e:
        # Our error function is badass, so we can catch all Exceptions for good debug output
        _render_err(file_path, e, template_text, template_parameters)


def render_image_build_files(root_dir):
    """
    Render files used for building images in the root directory. This is not recursive.
    There must be one template parameter file, and it must be in the root directory.
    """
    # If want to build anything other than just one Dockerfile later, a loop and regex to match
    # build files might be good. Loop can be done recursively like below.
    # for dirname, subdirs, files in os.walk(root_dir, topdown=True):
    #    for f in files:
    #         file_path = os.path.join(dirname, f)
    #         if not re.match(file_path, image_build_regex):
    #             continue  # do not render file
    template_parameters = load_template_param_file(os.path.join(root_dir, TEMPLATE_FILE))
    rendered_template = _render(template_dir=root_dir, template_file='Dockerfile',
                                template_parameters=template_parameters['template'])
    file_path = os.path.join(root_dir, 'Dockerfile')
    save_text_to_file_with_backup(rendered_template, file_path,
                                  backup_path='{}.0.bak'.format(file_path))
