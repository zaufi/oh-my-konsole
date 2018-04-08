#!/bin/bash
#
# OhMyKonsole helper bash functions
#
# TODO Get original binary paths and avoid hardcode
#

# Do nothing for non `konsole` sessions
[[ -z $KONSOLE_DBUS_SESSION ]] && return

# Try get config if available
[[ -f /etc/conf.d/oh-my-konsole ]] && . /etc/conf.d/oh-my-konsole

#
# Change current color scheme of running `konsole` session
#
function _omk_set_konsole_color_scheme()
{
    local -r scheme=$1
    [ -n "${KONSOLE_DBUS_SESSION}" ] && /usr/bin/konsoleprofile colorscheme=$scheme
}

function docker()
{
    if [[ $1 = run ]]; then
        _omk_set_konsole_color_scheme ${OMK_DOCKER_SCHEME:-OMKDockerShell}
    fi
    /usr/bin/docker $@
    if [[ $1 = run ]]; then
        _omk_set_konsole_color_scheme ${OMK_DEFAULT_SCHEME:-OMKDefault}
    fi
}

function ssh()
{
    _omk_set_konsole_color_scheme ${OMK_SSH_SCHEME:-OMKSSHShell}
    /usr/bin/ssh $*
    _omk_set_konsole_color_scheme ${OMK_DEFAULT_SCHEME:-OMKDefault}
}

function su()
{
    _omk_set_konsole_color_scheme ${OMK_ROOT_SCHEME:-OMKRootShell}
    /bin/su $*
    _omk_set_konsole_color_scheme ${OMK_DEFAULT_SCHEME:-OMKDefault}
}

function sudo()
{
    _omk_set_konsole_color_scheme ${OMK_ROOT_SCHEME:-OMKRootShell}
    /usr/bin/sudo $*
    _omk_set_konsole_color_scheme ${OMK_DEFAULT_SCHEME:-OMKDefault}
}
