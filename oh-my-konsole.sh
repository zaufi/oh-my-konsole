#!/bin/bash
#
# OhMyKonsole helper bash functions
#
# TODO Get original binary paths and avoid hardcode
#

# Do nothing for non `konsole` sessions
[[ -z $KONSOLE_DBUS_SESSION ]] && return

# Try get config if available
# 0. the system-wide
# shellcheck source=./conf.d/oh-my-konsole
[[ -f /etc/conf.d/oh-my-konsole ]] && . /etc/conf.d/oh-my-konsole
# 1. user overrides
# shellcheck source=/dev/null
[[ -f ${XDG_CONFIG_HOME:-${HOME}/.config}/oh-my-konsole.conf ]] && . "${XDG_CONFIG_HOME:-${HOME}/.config}"/oh-my-konsole.conf

#
# Change current color scheme of running `konsole` session
#
function _omk_set_konsole_color_scheme()
{
    local -r scheme="${1}"
    /usr/bin/konsoleprofile colorscheme="${scheme}"
}

function docker()
{
    local -r _change_color=$( \
        [[ "${1}" == run \
        || "${1}" == attach \
        || ("${1}" == container && ("${2}" == run || "${2}" == attach)) \
        ]] && echo yes || echo no \
      )
    if [[ ${_change_color} == yes ]]; then
        _omk_set_konsole_color_scheme "${OMK_DOCKER_SCHEME:-OMKDockerShell}"
    fi
    /usr/bin/docker "$@"
    if [[ ${_change_color} == yes ]]; then
        _omk_set_konsole_color_scheme "${OMK_DEFAULT_SCHEME:-OMKDefault}"
    fi
}

function ssh()
{
    _omk_set_konsole_color_scheme "${OMK_SSH_SCHEME:-OMKSSHShell}"
    /usr/bin/ssh "$@"
    _omk_set_konsole_color_scheme "${OMK_DEFAULT_SCHEME:-OMKDefault}"
}

function vagrant()
{
    local -r vagrant_bin=$(/bin/which vagrant)
    if [[ $1 == ssh ]]; then
        _omk_set_konsole_color_scheme "${OMK_SSH_SCHEME:-OMKSSHShell}"
        ${vagrant_bin} "$@"
        _omk_set_konsole_color_scheme "${OMK_DEFAULT_SCHEME:-OMKDefault}"
    else
        ${vagrant_bin} "$@"
    fi
}

function su()
{
    _omk_set_konsole_color_scheme "${OMK_ROOT_SCHEME:-OMKRootShell}"
    # shellcheck disable=SC2117
    /bin/su "$@"
    _omk_set_konsole_color_scheme "${OMK_DEFAULT_SCHEME:-OMKDefault}"
}

function sudo()
{
    _omk_set_konsole_color_scheme "${OMK_ROOT_SCHEME:-OMKRootShell}"
    /usr/bin/sudo "$@"
    _omk_set_konsole_color_scheme "${OMK_DEFAULT_SCHEME:-OMKDefault}"
}
