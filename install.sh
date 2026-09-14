#!/usr/bin/env bash
###################################################################
# Script Name : install.sh
# Description : Symlink dotfile packages from this repo into $HOME
# Args : [options] [package ...]
# Author : Barnabás Vass
###################################################################
#
# Layout is GNU stow compatible: each top-level directory is a "package" whose
# contents mirror $HOME, so <package>/<path> is linked to ~/<path>. A directory
# holding a .nopackage marker file is support code, not a package, and is
# skipped (see lib/).

# Not named SCRIPT_DIR on purpose: lib/logger.sh sets SCRIPT_DIR to its own
# location when sourced, which would clobber ours.
DOTFILES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
# shellcheck source=lib/installer.sh
source "$DOTFILES_DIR/lib/installer.sh" || {
    echo "Could not load installer library!" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: ${0##*/} [options] [package ...]

Symlinks the files of each package into \$HOME. With no package given, every
package in the repo is installed.

Options:
  -n, --dry-run   Show what would happen, change nothing
  -f, --force     Replace existing files without keeping a backup
  -l, --list      List available packages and exit
  -h, --help      Show this help

Examples:
  ${0##*/}                 # install everything
  ${0##*/} nvim            # install just the nvim package
  ${0##*/} -n nvim         # preview
  ${0##*/} nvim -n         # same, flags may come after packages
EOF
}

list_packages() {
    local dir
    for dir in "$DOTFILES_DIR"/*/; do
        dir=${dir%/}
        [[ -d $dir ]] || continue
        [[ -e $dir/.nopackage ]] && continue
        printf '%s\n' "${dir##*/}"
    done
}

dry_run=0
force=0
packages=()

while (($# > 0)); do
    case $1 in
        -n | --dry-run) dry_run=1 ;;
        -f | --force) force=1 ;;
        -l | --list)
            list_packages
            exit 0
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            print_status ERR "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *) packages+=("$1") ;;
    esac
    shift
done

if ((${#packages[@]} == 0)); then
    while IFS= read -r pkg; do
        packages+=("$pkg")
    done < <(list_packages)
fi

if ((${#packages[@]} == 0)); then
    print_status ERR "No packages found in $DOTFILES_DIR" >&2
    exit 1
fi

failed=0
linked=0

# Symlink every file of one package into $HOME.
# Args: package name, absolute package directory
link_package() {
    local pkg=$1 pkg_dir=$2 src rel target target_dir

    while IFS= read -r src; do
        rel=${src#"$pkg_dir"/}
        should_link "$pkg_dir" "$rel" || continue
        target=$HOME/$rel
        target_dir=${target%/*}

        if [[ -L $target ]] && [[ $(readlink "$target") == "$src" ]]; then
            print_status OK "$pkg: $rel already linked"
            continue
        fi

        if ((dry_run)); then
            print_status INFO "$pkg: would link $rel -> $src"
            continue
        fi

        if [[ ! -d $target_dir ]] && ! mkdir -p "$target_dir"; then
            print_status ERR "$pkg: cannot create $target_dir" >&2
            failed=1
            continue
        fi

        # --force throws the old file away, otherwise link_config_file keeps it
        # as <name>.old.
        ((force)) && [[ -e $target || -L $target ]] && rm -rf -- "$target"

        if link_config_file "$src" "$target"; then
            linked=$((linked + 1))
        else
            failed=1
        fi
    done < <(find "$pkg_dir" -type f -o -type l)
}

for pkg in "${packages[@]}"; do
    pkg_dir=$DOTFILES_DIR/$pkg
    if [[ ! -d $pkg_dir ]]; then
        print_status ERR "No such package: $pkg" >&2
        failed=1
        continue
    fi
    link_package "$pkg" "$pkg_dir"
done

if ((dry_run)); then
    print_status INFO "Dry run - nothing was changed."
elif ((failed)); then
    print_status ERR "Finished with errors ($linked file(s) linked)." >&2
else
    print_status DONE "Installed ${#packages[@]} package(s), $linked file(s) linked."
fi

exit "$failed"
