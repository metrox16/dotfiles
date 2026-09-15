# Dotfiles

Dotfiles config by Barnabás Vass.

**! WRITTEN BY AI !**


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
./install.sh          # 1. link configs (nvim, bat) + the common bash entries
./install-tools.sh    # 2. bat, fd, rg, eza, shfmt, gdu, zoxide, fzf + aliases + PATH
./install-nvim.sh     # 3. Neovim, vim-plug, plugins, tree-sitter parsers


./install.sh              # install every package
./install.sh <package>    # install one package
./install.sh -n           # preview (dry run)
./install.sh -c           # copy the files instead of linking them
./install.sh -h           # help
```

A real file already in the way is kept as `<file>.old`; `-f` replaces it without
keeping anything. Re-running is safe — already correct links are reported as
`ok`.

### Copies instead of links

`--copy` (`-c`) puts real files in `$HOME` rather than symlinks, so what is
installed does not need the repo and keeps working after it is deleted. It works
the same way in `install-tools.sh`, for the config files of a tool.

Nothing else in an install points at the repo — the shell entries are written
into the startup file as text, and a tool's binary is linked from
`~/.local/opt`, not from here — so `--copy` is what makes the whole install
self-contained.

The trade is that the two copies drift: editing `~/.config/bat/config` is no
longer editing the repo, and the next `--copy` run overwrites that edit with
whatever the repo holds. Switching modes works in both directions, and an
existing file that is already identical is replaced without leaving a `.old`
behind.

A file in a package that belongs to the repo rather than to `$HOME`, such as
`aliases.sh`, is listed in that package's `.nolink`, one glob per line, and is
never linked.

### Installing the tools

`install-nvim.sh` sets up Neovim, the plugin manager, the plugins and the
tree-sitter parsers. `install-tools.sh` sets up the command line tools. Neither
needs root, and both want bash 4 or newer — macOS still ships 3.2 as
`/bin/bash`, so install a current bash there first.

Parsers are the one step with prerequisites the scripts cannot always satisfy:
nvim-treesitter builds each parser by calling the `tree-sitter` CLI, which in
turn compiles C, so a compiler has to be present and the CLI is installed
alongside Neovim. Its official builds need a recent glibc, so on an older
distribution get it from brew, `cargo install tree-sitter-cli` or a distro
package.

This is checked before any work starts, and when something is missing you are
asked what to do: install it and retry, which is the answer for a machine where
you have root, skip the parsers and get the rest, or abort before anything is
touched. A non-interactive run skips them and says so, `--skip-parsers` does not
ask at all, and a run that ends without parsers says as much in its last line
rather than reporting plain success.

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
platform, so no per-project file names are hardcoded: both spellings of the
architecture are accepted (`x86_64` and `amd64`), and an asset that is a bare
binary rather than an archive, which is how Go projects such as `shfmt` publish,
is installed as it is. A binary inside an archive that carries the platform in
its name, as gdu's `gdu_linux_amd64` does, is renamed to the command. Where brew
installs a formula under another name — its `gdu` is `gdu-go`, to stay out of the
way of coreutils — that name goes in the `TOOL_BREW_BIN` row.

### Tool config and aliases

When the repo holds a directory named after a tool, `install-tools.sh` installs
that too: the config files are linked into `$HOME`, its `aliases.sh` is kept in
your shell startup file, and an executable `post-install.sh` runs afterwards
(bat uses one to rebuild its theme cache). The `bash` package holds what belongs
to no tool at all — navigation aliases, history settings, a couple of functions,
`.inputrc` for readline itself (coloured completion listings, 8-bit clean input),
and two commands under `.local/bin`: `bigclock` and `bigtimer`, which draw the
time and a countdown in block characters and share the font in
`.local/lib/bigdigits.sh`. `install.sh` installs all of that.

An `aliases.sh` is kept in a region of the startup file marked like this:

```sh
# >>> dotfiles: bash shell entries >>>
...
# <<< dotfiles: bash shell entries <<<
```

The file is copied in verbatim, so anything a startup file can hold works:
aliases, exports, functions, `shopt` and `eval` lines. Rerunning rewrites the
region instead of appending a second copy, so it is a no-op when nothing changed.

Your own configuration outside the region always wins. Each entry of ours is
matched against yours by name — the alias name, the variable name whether it is
exported or not, the function name, or, for a statement such as a `shopt`, the
command and its arguments:

- you define it exactly as we do: ours is left out, yours already is it
- you define it differently: ours goes in commented out, so it is there to read
  and uncomment but changes nothing

The startup file is chosen in this order:

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
