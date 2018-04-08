#!/bin/bash
#
# Copyright 2018, Alex Turbov <i.zaufi@gmail.com>
#

_help_string=$(cat <<__EOF__
Usage: $0 OPTION
where an OPTION is one of
    -s,--system     system-wide install
    -u,--user       install to user's HOME
__EOF__
)

# Execute getopt
ARGS=$(getopt -o "hsu" -l "help,system,user" -n "install.sh" -- "$@")

# Check args
if [ $? -ne 0 ]; then
    echo "*** Error: Invalid agrument"
    exit 1
fi

eval set -- "$ARGS"

# Now go through all the options
while true; do
    case "$1" in
        -h|--help)
            echo "$_help_string"
            shift
            exit 0
            ;;
        -s|--system)
            # TODO Use XDG_DATA_DIRS?
            _dst_data_dir="/usr/share/konsole"
            _dst_sysconf_dir="/etc"
            shift
            ;;
        -u|--user)
            _dst_data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/konsole"
            _dst_sysconf_dir="${XDG_DATA_HOME:-${HOME}/.local/etc}"
            shift
            ;;
        --)
            shift
            break
            ;;
    esac
done

if [ -z "${_dst_data_dir}" ]; then
    echo "*** Error: Can't detect a destination path"
    exit 1
fi

# Show underlaid commands
set -x

# TODO Check shopt

ls profile/* scheme/* | while read f; do
    install -m 0644 -D ${f} "${DESTDIR}${_dst_data_dir}/$(basename ${f})"
done

install -m 0644 -D conf.d/oh-my-konsole "${DESTDIR}${_dst_sysconf_dir}/conf.d/oh-my-konsole"
install -m 0644 -D oh-my-konsole.sh "${DESTDIR}${_dst_sysconf_dir}/profile.d/oh-my-konsole.sh"

set +x
