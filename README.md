# BashMaster

BashMaster is a small, Bash 5.2+ plugin host. The base provides startup
bootstrapping, plugin lifecycle management, root-scoped configuration, terminal
helpers, and auditing; user-visible features live in plugins.

## Install

```bash
./install.sh
```

By default, files are installed under `~/.bashmaster` and one marked,
interactive-only source block is appended to `~/.bashrc`. Use
`./install.sh --install-dir /absolute/path` to choose another root,
`--no-bashrc` to leave `.bashrc` untouched, or `--yes` for unattended setup.
Existing configuration files are preserved on reinstall.
With `--no-bashrc`, invoke the CLI by its full path, for example
`~/.bashmaster/bin/bashmaster list`.

Restart an interactive Bash terminal, then explicitly trust and enable any
plugin you want to run:

```bash
bashmaster list
bashmaster trust splash
bashmaster enable splash
bashmaster reload
```

Both bundled plugins are installed but untrusted and disabled by default.
`bashmaster uninstall` removes the current installation and its marked
`.bashrc` block; `./uninstall.sh --backup` also saves `config/` beside the
installation root before removing it.

## Commands

`bashmaster list | install | trust | enable | disable | remove | reload |
doctor` manage plugins and check installation integrity. `install` accepts a
bundled plugin name or a plugin directory containing `plugin.conf` and
`plugin.sh`; `remove NAME --keep-trust` retains its trust record. Plugin
commands are exposed as `bashmaster COMMAND`, only when declared in the
manifest of an enabled, trusted plugin.

The optional `splash` plugin displays a startup banner and supports
`bashmaster splash`. The `quickbar` plugin supports `bashmaster quickbar`.
Its starter entries are deliberately benign, but pressing Enter runs the
configured command in the current shell with the user's permissions. Review
custom entries before trusting/enabling the plugin.

## Files and security

All installed code, plugins, configuration, cache, and logs live below
`BASHMASTER_ROOT` (default `~/.bashmaster`). The only home-directory change is
the marked `.bashrc` block and its timestamped backup. Non-interactive or
non-TTY shells do not load plugins or print startup output.

Trusting a plugin authorizes sourcing its shell code as the current user.
Manifests are parsed as data, never sourced. Plugin commands and hooks are
available only when declared in a valid manifest. Plugin data belongs under
`config/<plugin>/`; plugins should use the `bm_<plugin>_<action>` namespace.
See [docs/plugin-api.md](docs/plugin-api.md).

Run the self-contained checks with:

```bash
bash tests/run.sh
```
