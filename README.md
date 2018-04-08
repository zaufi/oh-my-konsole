What is this
============

The main purpose of this package is to bring some fun to
KDE `konsole` ;-) It'll change the color scheme depending
on a running command. E.g. when you are `root` or running
SSH command or Docker container (that is what available
"out of the box").

The following color schemes are available:

- `OMKGreenOnBlack` which is almost the same as the `GreenOnBlack`
  shipped w/ `konsole`, except 0.85 transparency of background;
- `OMKDefault` is a symbolic link to `OMKGreenOnBlack`;
- `OMKRootShell`, `OMKDockerShell` and `OMKSSHShell` color
  schemes used when `su`/`sudo ...`, `docker run ...` and
  `ssh ...` command runs correspondingly. They differ from
  the default scheme only by the background color: dark red,
  yellow and blue.


How to install
==============

Run the `install.sh` provided. Install to the user's `$HOME`:

    $ ./install.sh -u

or to the system:

    $ ./install.sh -s


Configuration
=============

There is a trivial config file provided, so you can override
desired color schemes for any command.
