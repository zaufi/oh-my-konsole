# What is this


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


## How to install

Run the `install.sh` provided. Install to the user's `$HOME`:

    ./install.sh -u

or to the system:

    ./install.sh -s

The demo runner is installed as `run-konsole-demo` in `/usr/bin` for system installs or
`${XDG_BIN_HOME:-$HOME/.local/bin}` for user installs. Set `BINDIR` to override either
destination. `XDG_BIN_HOME` is supported as an extension to the XDG specification.

And for the Gentoo users, there is the [ebuild][1] for this package.

## Configuration


There is a trivial config file provided, so you can override
desired color schemes for any command.

## Running demos

`run-konsole-demo` opens a new Konsole or Yakuake tab and types comments and
commands from a YAML file into it. It requires `dotool`, `yq` v4, and `qdbus-qt6`.
For example, save this as `demo.yaml`:

    - "Preparing the demo"
    - command: "echo hello"
      sleep: 0.5

String steps are shorthand for `comment` steps and use the default delay.
Use an object such as `- comment: "Preparing the demo"` to set an explicit `sleep`.

Run `run-konsole-demo demo.yaml` from a Konsole or Yakuake terminal after
installation, or `bash ./run-konsole-demo.sh demo.yaml` from the repository. Keep
the new tab focused while the demo runs. After each step the runner waits until
the typed command has finished, then sleeps for the step's `sleep`. Comments
without `sleep` wait 10 seconds; set `KONSOLE_DEMO_DEFAULT_SLEEP` to change that
default. Commands without `sleep` continue right away. Use `--help` for usage
details.

[1]: https://github.com/zaufi/zaufi-overlay/blob/master/kde-misc/oh-my-konsole/oh-my-konsole-scm.ebuild
