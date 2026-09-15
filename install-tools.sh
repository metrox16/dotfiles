#!/usr/bin/env bash
###################################################################
# Script Name : install-tools.sh
# Description : Install the command line tools the dotfiles rely on
# Args : [options] [tool ...]
# Author : Barnabás Vass
###################################################################
#
# One script for every tool, driven by the table below: adding a tool means
# adding a row, not writing another script. Homebrew is used when available,
# otherwise the prebuilt release from the project's GitHub repository is
# unpacked under $HOME. Nothing needs root.

# Not named SCRIPT_DIR on purpose: the libraries set SCRIPT_DIR to their own
# location when sourced, which would clobber ours.
DOTFILES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
# shellcheck source=lib/installer.sh
source "$DOTFILES_DIR/lib/installer.sh" || {
    echo "Could not load installer library!" >&2
    exit 1
}

# The tools, keyed by the command name. TOOL_MIN is the oldest version worth
# keeping: an installed tool at least this new is left alone, anything older is
# replaced with the latest release.
declare -A TOOL_REPO=(
    [bat]=sharkdp/bat
    [fd]=sharkdp/fd
    [rg]=BurntSushi/ripgrep
    [eza]=eza-community/eza
    [shfmt]=mvdan/sh
    [gdu]=dundee/gdu
    [zoxide]=ajeetdsouza/zoxide
)
declare -A TOOL_BREW=(
    [bat]=bat
    [fd]=fd
    [rg]=ripgrep
    [eza]=eza
    [shfmt]=shfmt
    [gdu]=gdu
    [zoxide]=zoxide
)
# Where brew installs a formula's binary under another name, to keep out of the
# way of something else: brew's gdu is gdu-go, because coreutils ships a gdu.
declare -A TOOL_BREW_BIN=(
    [gdu]=gdu-go
)
declare -A TOOL_MIN=(
    [bat]=0.24.0
    [fd]=9.0.0
    [rg]=14.0.0
    [eza]=0.18.0
    [shfmt]=3.7.0
    [gdu]=5.20.0
    [zoxide]=0.9.0
)
# Names people type that are not the command name.
declare -A TOOL_ALIAS=(
    [ripgrep]=rg
    [batcat]=bat
    [fdfind]=fd
    [sh]=shfmt
    [gdu-go]=gdu
)

INSTALL_ROOT=${TOOLS_INSTALL_ROOT:-$HOME/.local/opt}
INSTALL_BIN_DIR=${TOOLS_BIN_DIR:-$HOME/.local/bin}
method=auto
force=0
manage_path=1
list_only=0
dry_run=0
tools=()

usage() {
    cat <<EOF
Usage: ${0##*/} [options] [tool ...]

Installs command line tools, all of them when none is named. An installed tool
that already meets its minimum version is left alone; anything older, or
missing, is installed at its latest release. Homebrew is the preferred source
and the project's GitHub release is the fallback.

Tools: $(printf '%s ' "${!TOOL_REPO[@]}" | sort_words)
Aliases such as 'ripgrep' for 'rg' are accepted.

Several versions on PATH are handled: all are compared, the newest wins, and
$INSTALL_BIN_DIR is put ahead on PATH in your shell startup file so that
version is the one that runs.

When the repo holds a directory named after a tool, its config files are linked
into \$HOME as well (a previous real file is kept as <name>.old) and its
aliases.sh is kept in a marked region of your shell startup file, whatever it
contains: aliases, exports, functions, plain statements. An entry you already
define the same way is left out, one you define differently goes in commented
out, and a rerun rewrites the region instead of appending to it.

The startup file is chosen in this order: --rc-file or DOTFILES_RC_FILE, then a
file that already carries our lines, then ~/.bashrc on Linux and
~/.bash_profile on macOS. When that file is not writable, which is common for a
managed ~/.bashrc, you are asked where to write instead.

Options:
  -m, --method M      Where tools come from: auto (default, brew first), brew
                      or release
  -f, --force         Install even when the installed version is new enough
  -n, --dry-run       Report what would happen, change nothing
      --prefix DIR    Where versioned payloads are kept (default: $INSTALL_ROOT)
      --rc-file FILE  Shell startup file for aliases and the PATH line
      --no-path-setup Do not touch any shell startup file
  -l, --list          Show the tools with their versions and exit
  -h, --help          Show this help
EOF
}

# Print words from stdin space separated and sorted, for the help text.
sort_words() {
    local -a words
    read -r -a words
    printf '%s\n' "${words[@]}" | sort | tr '\n' ' '
}

while (($# > 0)); do
    case $1 in
        -m | --method)
            method=$2
            shift
            ;;
        -f | --force) force=1 ;;
        -n | --dry-run) dry_run=1 ;;
        --prefix)
            INSTALL_ROOT=$2
            shift
            ;;
        --no-path-setup) manage_path=0 ;;
        --rc-file)
            export DOTFILES_RC_FILE=$2
            shift
            ;;
        -l | --list) list_only=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            print_status ERR "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *) tools+=("$1") ;;
    esac
    shift
done

case $method in
    auto | brew | release) ;;
    *)
        print_status ERR "Unknown method: $method (use auto, brew or release)" >&2
        exit 2
        ;;
esac

# Resolve an alias to the command name and reject unknown tools.
# Args: name as given by the user
resolve_tool() {
    local name=$1
    [[ -n ${TOOL_ALIAS[$name]:-} ]] && name=${TOOL_ALIAS[$name]}
    [[ -n ${TOOL_REPO[$name]:-} ]] || return 1
    printf '%s\n' "$name"
}

if ((${#tools[@]} == 0)); then
    while IFS= read -r name; do
        tools+=("$name")
    done < <(printf '%s\n' "${!TOOL_REPO[@]}" | sort)
else
    resolved=()
    for name in "${tools[@]}"; do
        if entry=$(resolve_tool "$name"); then
            resolved+=("$entry")
        else
            print_status ERR "Unknown tool: $name" >&2
            exit 2
        fi
    done
    tools=("${resolved[@]}")
fi

if ((list_only)); then
    for name in "${tools[@]}"; do
        if found=$(newest_binary "$name" 2>/dev/null); then
            print_status OK "$name ${found%% *} at ${found#* } (minimum ${TOOL_MIN[$name]})"
        else
            print_status WARN "$name is not installed (minimum ${TOOL_MIN[$name]})"
        fi
    done
    exit 0
fi

# The installers below report the installed binary in this global rather than
# on stdout. Returning data on stdout from a function that also logs means the
# log lines end up in the captured value.
install_target=''

# Install one tool with brew.
# Args: command name, path to brew
install_tool_via_brew() {
    local name=$1 brew=$2 formula=${TOOL_BREW[$1]} candidate version
    install_target=''
    if "$brew" list --versions "$formula" >/dev/null 2>&1; then
        if ((force)); then
            print_status INFO "Reinstalling $formula with brew"
            "$brew" reinstall "$formula" >/dev/null 2>&1
        else
            print_status INFO "Upgrading $formula with brew"
            "$brew" upgrade "$formula" >/dev/null 2>&1
        fi
    else
        print_status INFO "Installing $formula with brew"
        "$brew" install "$formula" >/dev/null 2>&1
    fi

    # The exit status of brew is not conclusive (an already current formula is
    # an "error" for some versions), so the resulting binary is what counts. A
    # formula may install it under another name, which TOOL_BREW_BIN carries.
    local brew_bin=${TOOL_BREW_BIN[$1]:-$name} prefix
    local -a candidates=()
    for prefix in "$("$brew" --prefix "$formula" 2>/dev/null)" "$("$brew" --prefix 2>/dev/null)"; do
        [[ -n $prefix ]] || continue
        candidates+=("$prefix/bin/$brew_bin")
        [[ $brew_bin == "$name" ]] || candidates+=("$prefix/bin/$name")
    done

    for candidate in "${candidates[@]}"; do
        if version=$(tool_version "$candidate"); then
            install_target=$candidate
            break
        fi
    done

    if [[ -z $install_target ]]; then
        print_status ERR "brew did not produce a working $name" >&2
        return 1
    fi
    print_status DONE "Installed $name $version with brew"
}

# Install one tool from its GitHub release.
# Args: command name
install_tool_via_release() {
    local name=$1 repo=${TOOL_REPO[$1]} tag asset tmp archive payload binary
    local version dest
    install_target=''

    tag=$(github_latest_tag "$repo")
    if [[ -z $tag ]]; then
        print_status ERR "Could not find the latest release of $repo" >&2
        return 1
    fi

    tmp=$(mktemp -d) || return 1
    # shellcheck disable=SC2064
    trap "rm -rf -- '$tmp'" RETURN

    asset=$(github_asset_names "$repo" "$tag" | pick_asset)
    if [[ -z $asset ]]; then
        print_status ERR "$repo $tag has no asset for $(uname -s)/$(uname -m)" >&2
        return 1
    fi

    archive=$tmp/$asset
    print_status INFO "Fetching $asset"
    if ! fetch "https://github.com/$repo/releases/download/$tag/$asset" "$archive"; then
        print_status ERR "Could not download $asset" >&2
        return 1
    fi

    payload=$tmp/payload
    if is_archive_name "$asset"; then
        extract_archive "$archive" "$payload" || return 1
    else
        # Not an archive: the asset is the bare binary, named after the platform
        # rather than the command (shfmt_v3.14.1_linux_amd64). It is put into the
        # payload under the command name, and made executable since a download is
        # not, so everything below treats both kinds of release the same way.
        mkdir -p "$payload" || return 1
        mv -- "$archive" "$payload/$name" || return 1
        chmod u+x -- "$payload/$name" || return 1
    fi
    if ! binary=$(find_binary_in "$payload" "$name"); then
        print_status ERR "No $name binary inside $asset" >&2
        return 1
    fi

    # Some releases name the binary after the platform rather than the command,
    # gdu shipping gdu_linux_amd64, so it is renamed here and everything below,
    # including what ends up on PATH, is plain "$name".
    if [[ ${binary##*/} != "$name" ]]; then
        mv -- "$binary" "${binary%/*}/$name" || return 1
        binary=${binary%/*}/$name
    fi

    # Check it runs before it is put anywhere, since a prebuilt binary can
    # unpack fine and still fail on an older system C library.
    if ! version=$(tool_version "$binary"); then
        print_status ERR "The downloaded $name does not run on this system" >&2
        return 1
    fi

    # Keep the whole payload: these archives ship man pages and completions
    # next to the binary.
    dest=$INSTALL_ROOT/$name/$version
    mkdir -p "${dest%/*}" || return 1
    rm -rf -- "${dest:?}"
    if ! mv -- "${binary%/*}" "$dest"; then
        print_status ERR "Cannot move $name into $INSTALL_ROOT/$name" >&2
        return 1
    fi
    ln -sfn -- "$version" "$INSTALL_ROOT/$name/current" || return 1

    print_status DONE "Installed $name $version from $repo"
    install_target=$INSTALL_ROOT/$name/current/$name
}

# Install one tool unless a new enough one is already there, then make it the
# one PATH picks.
# Args: command name
install_tool() {
    local name=$1 newest existing existing_version brew

    if newest=$(newest_binary "$name") && ((!force)); then
        existing_version=${newest%% *}
        existing=${newest#* }
        if version_ge "$existing_version" "${TOOL_MIN[$name]}"; then
            print_status OK "$name $existing_version at $existing is new enough (>= ${TOOL_MIN[$name]})"
            ((dry_run)) && return 0
            link_bin "$existing" "$name" || return 1
            return 0
        fi
        print_status INFO "$name $existing_version is older than ${TOOL_MIN[$name]}, installing the latest"
    fi

    brew=$(find_brew)

    if ((dry_run)); then
        # Brew is the preferred source; the release archive is the fallback.
        if [[ -n $brew ]] && [[ $method != release ]]; then
            print_status INFO "$name would be installed with brew at $brew"
        else
            print_status INFO "$name would be installed from ${TOOL_REPO[$name]}"
        fi
        return 0
    fi

    install_target=''
    case $method in
        brew)
            if [[ -z $brew ]]; then
                print_status ERR "Method 'brew' requested but no brew was found" >&2
                return 1
            fi
            install_tool_via_brew "$name" "$brew" || return 1
            ;;
        release) install_tool_via_release "$name" || return 1 ;;
        auto)
            if [[ -n $brew ]]; then
                install_tool_via_brew "$name" "$brew" ||
                    print_status WARN "brew could not install $name, falling back to the release archive"
            fi
            if [[ -z $install_target ]]; then
                install_tool_via_release "$name" || return 1
            fi
            ;;
    esac

    link_bin "$install_target" "$name"
}

# Install the config files and shell entries that belong to a tool. A tool has
# them when the repo holds a package directory of the same name: its files are
# linked into $HOME the same way as any other package, aliases.sh contributes
# shell entries, and an executable post-install.sh runs at the end.
# Args: command name
install_tool_extras() {
    local name=$1
    # Separate local: $name is not yet assigned while the first one is expanded.
    local pkg=$DOTFILES_DIR/$name src rel rc snippet=''
    [[ -d $pkg ]] || return 0

    [[ -f $pkg/aliases.sh ]] && snippet=$pkg/aliases.sh

    if ((dry_run)); then
        while IFS= read -r src; do
            rel=${src#"$pkg"/}
            should_link "$pkg" "$rel" || continue
            print_status INFO "$name: would link ~/$rel"
        done < <(find "$pkg" -type f -o -type l)
        [[ -n $snippet ]] &&
            print_status INFO "$name: would keep aliases.sh in a region of your shell startup file"
        return 0
    fi

    while IFS= read -r src; do
        rel=${src#"$pkg"/}
        should_link "$pkg" "$rel" || continue
        link_config_file "$src" "$HOME/$rel" || return 1
    done < <(find "$pkg" -type f -o -type l)

    if [[ -n $snippet ]]; then
        rc=$(resolve_rc_file "dotfiles: $name shell entries") || return 1
        install_shell_entries "$snippet" "$rc" "$name shell entries" || return 1
    fi

    if [[ -x $pkg/post-install.sh ]]; then
        if "$pkg/post-install.sh" "$INSTALL_BIN_DIR/$name" "$pkg"; then
            print_status DONE "Ran the $name post-install hook"
        else
            print_status WARN "The $name post-install hook failed"
        fi
    fi
}

failed=0
for name in "${tools[@]}"; do
    install_tool "$name" || failed=1
    install_tool_extras "$name" || failed=1
done

if ((dry_run)); then
    print_status INFO "Dry run - nothing was changed."
elif ((manage_path)); then
    # One PATH entry serves every tool, so this is done once at the end.
    ensure_path_priority "${tools[0]}" || failed=1
else
    print_status INFO "Leaving PATH alone as requested"
fi

if ((failed)); then
    print_status ERR "Finished with errors" >&2
elif ((!dry_run)); then
    print_status DONE "Installed or verified: ${tools[*]}"
fi

exit "$failed"
