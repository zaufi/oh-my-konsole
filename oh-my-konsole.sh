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
[[ -f /etc/conf.d/oh-my-konsole ]] && . /etc/conf.d/oh-my-konsole
# 1. user overrides
[[ -f ${HOME}/.config/oh-my-konsole.conf ]] && . ${HOME}/.config/oh-my-konsole.conf

#
# Change current color scheme of running `konsole` session
#
function _omk_set_konsole_color_scheme()
{
    local -r scheme="$1"
    /usr/bin/konsoleprofile colorscheme=$scheme
}

function docker()
{
    if [[ "$1" = run || "$1" = attach ]]; then
        _omk_set_konsole_color_scheme ${OMK_DOCKER_SCHEME:-OMKDockerShell}
    fi
    /usr/bin/docker "$@"
    if [[ "$1" = run || "$1" = attach ]]; then
        _omk_set_konsole_color_scheme ${OMK_DEFAULT_SCHEME:-OMKDefault}
    fi
}

function ssh()
{
    _omk_set_konsole_color_scheme ${OMK_SSH_SCHEME:-OMKSSHShell}
    /usr/bin/ssh "$@"
    _omk_set_konsole_color_scheme ${OMK_DEFAULT_SCHEME:-OMKDefault}
}

function su()
{
    _omk_set_konsole_color_scheme ${OMK_ROOT_SCHEME:-OMKRootShell}
    /bin/su "$@"
    _omk_set_konsole_color_scheme ${OMK_DEFAULT_SCHEME:-OMKDefault}
}

function sudo()
{
    _omk_set_konsole_color_scheme ${OMK_ROOT_SCHEME:-OMKRootShell}
    /usr/bin/sudo "$@"
    _omk_set_konsole_color_scheme ${OMK_DEFAULT_SCHEME:-OMKDefault}
}
