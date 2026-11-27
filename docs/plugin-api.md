# Plugin API v1

A plugin package is a directory containing `plugin.conf` and `plugin.sh`.
The manifest is plain `key=value` data (not shell code) and must declare all
five keys:

```ini
name=example
version=1.0.0
description=An example plugin
hooks=on_load,on_unload,on_prompt
commands=hello
```

Use empty values for unused `hooks` or `commands`. Names use lowercase
letters, digits, and underscores, beginning with a letter. A plugin named
`example` exports hooks as `bm_example_on_load`,
`bm_example_on_unload`, and `bm_example_on_prompt`; each declared command
`hello` must be implemented as `bm_example_command_hello`.

The manager validates the manifest before sourcing `plugin.sh`, checks each
declared function, and invokes only declared hooks/commands. A plugin must
first be installed, then explicitly trusted, then enabled. Trusting means
authorizing its shell code to run with the current user's permissions.
`on_load` runs when loaded, `on_unload` before it is unloaded, and
`on_prompt` before each prompt while enabled.

Keep all plugin-written persistent data under
`$BASHMASTER_ROOT/config/<plugin>/`. Do not create files elsewhere, modify
user configuration, or put plugin executables on `PATH`. Register user-facing
commands only through `plugin.conf`; dispatch is through `bashmaster COMMAND`.

The quickbar is an example of a command-executing plugin: its configured
commands are trusted user input and run in the current shell when selected.
