#!/usr/bin/env bash
###################################################################
# Script Name : install-lazy.sh
# Description : Install the LazyVim based Neovim config (nvim-lazy package)
# Args : [options]
# Author : Barnabás Vass
###################################################################
#
# The nvim package and the nvim-lazy package both want ~/.config/nvim, so this
# script moves an existing config to ~/.config/nvim.bak before putting the
# LazyVim one in place. Going back is one mv away, and nothing under
# ~/.local/share/nvim is touched: the vim-plug plugins of the old config stay
# where they are, next to lazy.nvim's own directory.
#
# Linking the files is install.sh's job and is delegated to it, so both scripts
# put files in $HOME the same way and --copy works here too.

# Not named SCRIPT_DIR on purpose: the libraries set SCRIPT_DIR to their own
# location when sourced, which would clobber ours.
DOTFILES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
# shellcheck source=lib/installer.sh
source "$DOTFILES_DIR/lib/installer.sh" || {
    echo "Could not load installer library!" >&2
    exit 1
}

readonly PACKAGE=nvim-lazy
readonly PKG_DIR=$DOTFILES_DIR/$PACKAGE
readonly CONFIG_DIR=$HOME/.config/nvim
readonly BACKUP_DIR=$HOME/.config/nvim.bak
readonly LAZY_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy

# LazyVim wants 0.9, and the nvim-treesitter main branch this config uses wants
# 0.11, so 0.11 is the floor. install-nvim.sh installs a newer one when needed.
MIN_NVIM_VERSION=${MIN_NVIM_VERSION:-0.11.0}

dry_run=0
force=0
copy=0
skip_plugins=0
skip_parsers=0
nvim_cmd=''

usage() {
    cat <<EOF
Usage: ${0##*/} [options]

Installs the LazyVim configuration from the $PACKAGE package into
~/.config/nvim, then lets lazy.nvim download the plugins and nvim-treesitter
build the parsers the config asks for.

An existing ~/.config/nvim is saved as ~/.config/nvim.bak first, so the old
config comes back with:

  rm -rf ~/.config/nvim && mv ~/.config/nvim.bak ~/.config/nvim

Its plugins are not touched, they stay under ~/.local/share/nvim. A second run
finds its own config already in place and leaves the backup alone, so rerunning
is safe. An older backup is kept as ~/.config/nvim.bak.old; --force drops it.

Steps:
  1. nvim       an existing $MIN_NVIM_VERSION or newer is required
                (run ./install-nvim.sh first when it is missing or too old)
  2. backup     ~/.config/nvim -> ~/.config/nvim.bak
  3. files      the $PACKAGE package linked into ~/.config/nvim
  4. plugins    :Lazy! sync, which bootstraps lazy.nvim on the first run
  5. parsers    the tree-sitter parsers the config lists

Options:
  -n, --dry-run        Show what would happen, change nothing
  -f, --force          Replace an existing ~/.config/nvim.bak, and pass
                       --force on to install.sh
  -c, --copy           Copy the config files instead of symlinking them
      --skip-plugins   Do not run lazy.nvim (implies --skip-parsers)
      --skip-parsers   Do not build tree-sitter parsers
  -h, --help           Show this help
EOF
}

while (($# > 0)); do
    case $1 in
        -n | --dry-run) dry_run=1 ;;
        -f | --force) force=1 ;;
        -c | --copy) copy=1 ;;
        --skip-plugins) skip_plugins=1 ;;
        --skip-parsers) skip_parsers=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            print_status ERR "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

((skip_plugins)) && skip_parsers=1

# Path with $HOME shortened, for readable output.
# Args: path
pretty() {
    printf '%s\n' "${1/#$HOME/\~}"
}

# Find an nvim new enough for this config and remember it in nvim_cmd.
check_nvim() {
    local candidate version

    candidate=$(newest_binary nvim) && candidate=${candidate#* }
    if [[ ! -x $candidate ]]; then
        print_status ERR "No nvim found. Install one first: ./install-nvim.sh" >&2
        return 1
    fi

    version=$(tool_version "$candidate")
    if [[ -z $version ]]; then
        print_status ERR "Cannot read the version of $candidate" >&2
        return 1
    fi

    if ! version_ge "$version" "$MIN_NVIM_VERSION"; then
        print_status ERR "nvim $version is older than $MIN_NVIM_VERSION. Upgrade it: ./install-nvim.sh" >&2
        return 1
    fi

    nvim_cmd=$candidate
    print_status OK "Using nvim $version at $candidate"
}

# True when ~/.config/nvim already holds the files of this package, which is
# what makes a second run skip the backup instead of burying the real backup
# under a copy of our own config.
config_is_ours() {
    local probe=$CONFIG_DIR/lua/config/lazy.lua
    local src=$PKG_DIR/.config/nvim/lua/config/lazy.lua

    [[ -e $probe ]] || return 1
    if [[ -L $probe ]]; then
        [[ $(readlink -- "$probe") == "$src" ]]
        return
    fi
    cmp -s "$probe" "$src"
}

# Make room for a new backup: with --force the old one goes, otherwise it is
# kept one generation as nvim.bak.old.
rotate_backup() {
    local old=$BACKUP_DIR.old

    [[ -e $BACKUP_DIR || -L $BACKUP_DIR ]] || return 0

    if ((force)); then
        print_status WARN "Replacing $(pretty "$BACKUP_DIR")"
        rm -rf -- "$BACKUP_DIR"
        return
    fi

    if [[ -e $old || -L $old ]]; then
        print_status WARN "Dropping the older backup $(pretty "$old")"
        rm -rf -- "$old" || return 1
    fi

    if ! mv -- "$BACKUP_DIR" "$old"; then
        print_status ERR "Cannot move $(pretty "$BACKUP_DIR") aside" >&2
        return 1
    fi
    print_status INFO "Previous backup kept as $(pretty "$old")"
}

# Move the config that is there now out of the way.
backup_config() {
    if [[ ! -e $CONFIG_DIR && ! -L $CONFIG_DIR ]]; then
        print_status INFO "No Neovim config at $(pretty "$CONFIG_DIR") yet"
        return 0
    fi

    if config_is_ours; then
        print_status OK "$(pretty "$CONFIG_DIR") already holds this config, keeping any backup as it is"
        return 0
    fi

    if ((dry_run)); then
        print_status INFO "Would save $(pretty "$CONFIG_DIR") as $(pretty "$BACKUP_DIR")"
        return 0
    fi

    rotate_backup || return 1

    if ! mv -- "$CONFIG_DIR" "$BACKUP_DIR"; then
        print_status ERR "Cannot move $(pretty "$CONFIG_DIR") to $(pretty "$BACKUP_DIR")" >&2
        return 1
    fi
    print_status DONE "Saved your Neovim config as $(pretty "$BACKUP_DIR")"
}

# Hand the file installation to install.sh, which is what every other package
# goes through.
link_files() {
    local -a args=("$PACKAGE")

    ((dry_run)) && args+=(--dry-run)
    ((force)) && args+=(--force)
    ((copy)) && args+=(--copy)

    "$DOTFILES_DIR/install.sh" "${args[@]}"
}

# Run a headless nvim command and report on it. NVIM_APPNAME is cleared so the
# run reads ~/.config/nvim and not whatever config the current shell points at.
# Args: description, nvim arguments...
run_headless() {
    local what=$1
    shift

    print_status INFO "$what (this can take a while)"
    if NVIM_APPNAME='' "$nvim_cmd" --headless "$@" >/dev/null 2>&1; then
        print_status DONE "$what"
        return 0
    fi
    print_status ERR "$what failed; rerun by hand to see why: $nvim_cmd --headless $*" >&2
    return 1
}

# Print what a headless nvim wrote to stdout.
# Args: nvim arguments...
nvim_headless_output() {
    NVIM_APPNAME='' "$nvim_cmd" --headless "$@" 2>/dev/null
}

install_plugins() {
    run_headless "Installing plugins with lazy.nvim" '+Lazy! sync' +qa || return 1

    # A headless nvim can exit 0 having logged an error, so look for the result
    # rather than trusting the exit status.
    if [[ ! -d $LAZY_DIR/LazyVim ]]; then
        print_status ERR "LazyVim is not in $(pretty "$LAZY_DIR") after the plugin step" >&2
        return 1
    fi
    print_status OK "Plugins are in $(pretty "$LAZY_DIR")"
}

# nvim-treesitter's main branch compiles nothing itself, it calls the
# tree-sitter CLI, which compiles C. Both have to be there.
parser_prereqs_ok() {
    local missing=()

    command -v tree-sitter >/dev/null 2>&1 || missing+=("the tree-sitter CLI")
    command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 \
        || command -v clang >/dev/null 2>&1 || missing+=("a C compiler")

    ((${#missing[@]} == 0)) && return 0

    print_status WARN "Skipping the parsers, this machine has no ${missing[*]}"
    print_status INFO "./install-nvim.sh installs the tree-sitter CLI and says what to do about a compiler"
    return 1
}

# The language list lives in the config, as nvim-treesitter's ensure_installed,
# so it is read from there instead of being repeated here.
install_parsers() {
    local installed

    run_headless "Building tree-sitter parsers" \
        -c 'lua local p = require("lazy.core.config").plugins["nvim-treesitter"]; local o = require("lazy.core.plugin").values(p, "opts", false); require("nvim-treesitter").install(o.ensure_installed or {}):wait(900000)' \
        -c qa || return 1

    installed=$(nvim_headless_output \
        -c 'lua io.write(table.concat(require("nvim-treesitter").get_installed(), " "))' -c qa)
    if [[ -z $installed ]]; then
        print_status ERR "No tree-sitter parsers are installed after the parser step" >&2
        return 1
    fi
    print_status OK "Parsers installed: $installed"
}

if [[ ! -d $PKG_DIR ]]; then
    print_status ERR "No $PACKAGE package in $DOTFILES_DIR" >&2
    exit 1
fi

if [[ -n ${XDG_CONFIG_HOME:-} && $XDG_CONFIG_HOME != "$HOME/.config" ]]; then
    print_status WARN "XDG_CONFIG_HOME is $XDG_CONFIG_HOME, but the packages of this repo install into ~/.config"
fi

failed=0
parsers_skipped=0

check_nvim || exit 1
backup_config || exit 1
link_files || failed=1

if ((dry_run)); then
    print_status INFO "Dry run - the plugin and parser steps were not run either."
    exit "$failed"
fi

if ((skip_plugins)); then
    print_status INFO "Skipping the plugin step"
else
    install_plugins || failed=1
fi

if ((skip_parsers)); then
    print_status INFO "Skipping the parser step"
    parsers_skipped=1
elif ! parser_prereqs_ok; then
    parsers_skipped=1
else
    install_parsers || failed=1
fi

if ((failed)); then
    print_status ERR "Finished with errors" >&2
elif ((parsers_skipped)); then
    print_status WARN "LazyVim is ready at $(pretty "$CONFIG_DIR"), but without tree-sitter parsers"
else
    print_status DONE "LazyVim is ready: $(pretty "$CONFIG_DIR")"
fi

exit "$failed"
