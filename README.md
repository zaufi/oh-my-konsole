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

`run-konsole-demo` types comments and commands from a YAML file into the focused
terminal. It requires `dotool` and `yq` v4. For example, save this as `demo.yaml`:

    - comment: "Preparing the demo"
    - command: "echo hello"
      sleep: 0.5

Run `run-konsole-demo demo.yaml` after installation, or
`bash ./run-konsole-demo.sh demo.yaml` from the repository. Focus the intended
terminal before running it. Each step waits 10 seconds afterward unless `sleep`
is specified; set `KONSOLE_DEMO_DEFAULT_SLEEP` to change that default. Use
`--help` for usage details.

Use `run-konsole-demo -t demo.yaml` to open a new Konsole or Yakuake tab before
running the steps. This option also requires `qdbus-qt6`.

[1]: https://github.com/zaufi/zaufi-overlay/blob/master/kde-misc/oh-my-konsole/oh-my-konsole-scm.ebuild
