# Dotfiles

Dotfiles config by Barnabás Vass.

## Layout

Each top-level directory is a **package**, and its contents mirror `$HOME`.
A file at `<package>/<path>` is symlinked to `~/<path>`, so the package name
never appears in the target path — it only groups related files.

This is the GNU stow layout, so `stow <package>` works too where stow is
installed. `./install.sh -l` lists what is currently in the repo.

## Usage

```sh
git clone git@github.com:metrox16/dotfiles.git
cd dotfiles
./install.sh          # 1. link configs: nvim, bat (+ eza has none)
./install-tools.sh    # 2. bat, fd, rg, eza + their aliases + the PATH line
./install-nvim.sh     # 3. Neovim, vim-plug, plugins, tree-sitter parsers


./install.sh              # install every package
./install.sh <package>    # install one package
./install.sh -n           # preview (dry run)
./install.sh -h           # help
```

A real file already in the way is kept as `<file>.old`; `-f` replaces it without
keeping anything. Re-running is safe — already correct links are reported as
`ok`.

A file in a package that belongs to the repo rather than to `$HOME`, such as
`aliases.sh`, is listed in that package's `.nolink`, one glob per line, and is
never linked.

### Installing the tools

`install-nvim.sh` sets up Neovim, the plugin manager, the plugins and the
tree-sitter parsers. `install-tools.sh` sets up the command line tools. Neither
needs root, and both want bash 4 or newer — macOS still ships 3.2 as
`/bin/bash`, so install a current bash there first.

```sh
./install-nvim.sh          # Neovim and its plugins
./install-tools.sh         # every tool
./install-tools.sh fd rg   # only some
./install-tools.sh -l      # what is installed, and the minimum versions
./install-tools.sh -n      # dry run
```

Anything already installed that meets its minimum version is left alone.
Otherwise the latest version is installed, preferring Homebrew and falling back
to the project's own prebuilt release (Linux and macOS, x86_64 and arm64).
Homebrew counts as available when `brew` is on PATH or `HOMEBREW_PREFIX` is
exported — no install location is guessed, and where brew put the binary is
asked of brew itself. Point `DOTFILES_BREW` at a brew that is neither on PATH
nor exported.
Everything stays under `~/.local`: the executables land in `~/.local/bin`, which
is the only directory put on PATH, and an unpacked release keeps its own tree in
`~/.local/opt/<tool>/<version>` with a `current` symlink, so a rollback is one
symlink away. Override either with `--prefix`, `TOOLS_INSTALL_ROOT` or
`NVIM_INSTALL_ROOT`.

Adding a tool means adding a row to the table at the top of the script: its
repository, brew formula and minimum version. Release assets are matched by
platform, so no per-project file names are hardcoded.

### Tool config and aliases

When the repo holds a directory named after a tool, `install-tools.sh` installs
that too: the config files are linked into `$HOME`, the entries of its
`aliases.sh` are added to a shell startup file, and an executable
`post-install.sh` runs afterwards (bat uses one to rebuild its theme cache).

An alias or export that is already defined is left alone, so the file never
overwrites something of yours. The startup file is chosen in this order:

1. `--rc-file FILE`, or the `DOTFILES_RC_FILE` environment variable
2. a bash startup file that already carries our lines, so nothing is duplicated
3. `~/.bashrc` on Linux, `~/.bash_profile` on macOS

When that file is not writable, which is what happens with a managed `~/.bashrc`,
you are asked where to write instead; the default offered is `~/.bashrc.user`,
since a managed `~/.bashrc` normally sources it. Non-interactive runs take that
fallback and say so.

Because several versions of a tool can sit on PATH with an old one first, both
scripts compare all of them, link the newest into `~/.local/bin` and add a PATH
line to the same startup file so that version is the one that runs. The line is
marked and only added once; `--no-path-setup` disables it.

### Shared shell code

`lib/` holds the shared code: `logger.sh` for output and `installer.sh` for
downloading, version comparison, release lookup, symlinks, shell entries and the
PATH fix. A directory holding a `.nopackage` file is support code rather than a
package, so `lib/` is never linked into `$HOME`.

### Adding a package

Create the directory, move the real files into it under their `$HOME`-relative
path, then install:

```sh
mkdir -p <package>
mv ~/<path> <package>/<path>
./install.sh <package>
```

Keep secrets and machine-specific values out of the repo. Source them from an
untracked local file instead.
