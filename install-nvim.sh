#!/usr/bin/env bash
###################################################################
# Script Name : install-nvim.sh
# Description : Install Neovim, vim-plug and the tree-sitter parsers
# Args : [options]
# Author : Barnabás Vass
###################################################################
#
# Neovim is kept in a versioned directory with a "current" symlink, so several
# versions can coexist and a rollback is one symlink away. Downloading, version
# comparison, the $HOME/bin symlink and the PATH fix all come from
# lib/installer.sh, which install-tools.sh uses as well.

# Not named SCRIPT_DIR on purpose: the libraries set SCRIPT_DIR to their own
# location when sourced, which would clobber ours.
DOTFILES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
# shellcheck source=lib/installer.sh
source "$DOTFILES_DIR/lib/installer.sh" || {
    echo "Could not load installer library!" >&2
    exit 1
}

# Where releases are fetched from. Overridable so a mirror can be used on a
# network without direct GitHub access, and so the download paths can be tested
# against a local server.
RELEASES_URL=${RELEASES_URL:-https://github.com/neovim/neovim/releases}
readonly NVIM_REPO="neovim/neovim"
readonly PLUG_URL="https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
readonly TS_CLI_REPO="tree-sitter/tree-sitter"
TS_CLI_RELEASES=${TS_CLI_RELEASES:-https://github.com/$TS_CLI_REPO/releases}

# nvim-treesitter's main branch does not compile parsers itself, it calls the
# tree-sitter CLI to do it, so the CLI is as much a prerequisite as the C
# compiler and gets installed here rather than being expected on the machine.
MIN_TS_CLI_VERSION=${MIN_TS_CLI_VERSION:-0.25.0}

# An already installed Neovim at least this new is left alone; anything older
# is replaced with the latest release. 0.11 is the floor because the config
# uses the nvim-treesitter main branch, which needs it.
MIN_NVIM_VERSION=${MIN_NVIM_VERSION:-0.11.0}

install_root=${NVIM_INSTALL_ROOT:-$HOME/.local/opt/nvim}
INSTALL_BIN_DIR=${NVIM_BIN_DIR:-$HOME/.local/bin}
method=auto
force=0
skip_nvim=0
skip_parsers=0
manage_path=1
nvim_cmd=''

usage() {
    cat <<EOF
Usage: ${0##*/} [options]

An existing Neovim of $MIN_NVIM_VERSION or newer is left alone (override with
MIN_NVIM_VERSION in the environment or at the top of this script). Anything
older, or nothing at all, means the latest Neovim gets installed.

Several Neovim versions on PATH are handled: all of them are compared, the
newest one wins, and $INSTALL_BIN_DIR is put ahead on PATH in your shell
startup file so that version is the one that actually runs.

Steps:
  1. Neovim      via Homebrew if present, otherwise the prebuilt release from
                 the Neovim repository -> $install_root/<version>
  2. PATH        $INSTALL_BIN_DIR/nvim points at the winner, $INSTALL_BIN_DIR first
  3. vim-plug    the plugin manager init.vim expects
  4. plugins     :PlugInstall for everything in the config
  5. parsers     the tree-sitter CLI, then the parsers the config asks for.
                 nvim-treesitter builds parsers by calling that CLI, which
                 compiles C, so a compiler has to be there too.

What the parsers need is checked before any work starts. When something is
missing you are asked whether to install it and retry, skip the parsers and get
on with the rest, or abort. A non-interactive run skips them and says so, and
--skip-parsers does not ask at all.

Re-running is safe.

Options:
  -m, --method M      Where Neovim comes from: auto (default), brew or release
  -f, --force         Install even when the current Neovim is new enough
      --prefix DIR    Where the release method keeps versions
                      (default: $install_root; ignored by the brew method)
      --skip-nvim     Only do the vim-plug, plugin and parser steps
      --skip-parsers  Do not install tree-sitter parsers
      --no-path-setup Do not touch any shell startup file
  -h, --help          Show this help

This never touches a system-wide Neovim, and it is unrelated to any Neovim
source checkout you may keep elsewhere.
EOF
}

while (($# > 0)); do
    case $1 in
        -m | --method)
            method=$2
            shift
            ;;
        -f | --force) force=1 ;;
        --prefix)
            install_root=$2
            shift
            ;;
        --skip-nvim) skip_nvim=1 ;;
        --skip-parsers) skip_parsers=1 ;;
        --no-path-setup) manage_path=0 ;;
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

case $method in
    auto | brew | release) ;;
    *)
        print_status ERR "Unknown method: $method (use auto, brew or release)" >&2
        exit 2
        ;;
esac

# Install or upgrade Neovim with Homebrew.
# Args: path to brew
install_via_brew() {
    local brew=$1 candidate target='' version
    print_status INFO "Updating brew formulae"
    "$brew" update --quiet >/dev/null 2>&1 ||
        print_status WARN "brew update failed, continuing with the current formulae"

    # The exit status of install/upgrade is not conclusive (an already current
    # formula is an "error" for some brew versions), so the resulting binary is
    # what gets checked afterwards.
    if "$brew" list --versions neovim >/dev/null 2>&1; then
        if ((force)); then
            print_status INFO "Reinstalling neovim with brew"
            "$brew" reinstall neovim >/dev/null 2>&1
        else
            print_status INFO "Upgrading neovim with brew"
            "$brew" upgrade neovim >/dev/null 2>&1
        fi
    else
        print_status INFO "Installing neovim with brew (this can take a while)"
        "$brew" install neovim >/dev/null 2>&1
    fi

    for candidate in "$("$brew" --prefix neovim 2>/dev/null)/bin/nvim" \
        "$("$brew" --prefix 2>/dev/null)/bin/nvim"; do
        if version=$(tool_version "$candidate"); then
            target=$candidate
            break
        fi
    done

    if [[ -z $target ]]; then
        print_status ERR "brew did not produce a working nvim" >&2
        return 1
    fi

    print_status DONE "Installed Neovim $version with brew"
    nvim_cmd=$target
}

# Print the release asset names that could fit this OS/architecture, best
# first. Neovim does not use the <arch>-<os> triple that pick_asset understands,
# and it renamed its assets over time, hence this explicit list.
asset_candidates() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)

    case $os in
        Linux)
            case $arch in
                x86_64 | amd64) printf '%s\n' nvim-linux-x86_64.tar.gz nvim-linux64.tar.gz ;;
                aarch64 | arm64) printf '%s\n' nvim-linux-arm64.tar.gz ;;
                *) return 1 ;;
            esac
            ;;
        Darwin)
            case $arch in
                x86_64) printf '%s\n' nvim-macos-x86_64.tar.gz nvim-macos.tar.gz ;;
                arm64) printf '%s\n' nvim-macos-arm64.tar.gz nvim-macos.tar.gz ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

# Download the latest prebuilt release and activate it.
install_via_release() {
    local tag asset tmp archive payload binary version url ok=0 download_error=0

    tag=$(github_latest_tag "$NVIM_REPO")
    if [[ -n $tag ]] && ((!force)) && [[ -x $install_root/$tag/bin/nvim ]]; then
        print_status OK "Neovim $tag is already the latest and is installed"
        activate_release "$tag"
        return $?
    fi

    tmp=$(mktemp -d) || return 1
    # shellcheck disable=SC2064
    trap "rm -rf -- '$tmp'" RETURN

    archive=$tmp/nvim.tar.gz
    while IFS= read -r asset; do
        url="$RELEASES_URL/latest/download/$asset"
        print_status INFO "Fetching $asset ${tag:+($tag)}"
        fetch "$url" "$archive"
        case $? in
            0)
                ok=1
                break
                ;;
            44) print_status WARN "$asset is not part of this release, trying the next name" ;;
            *)
                download_error=1
                break
                ;;
        esac
    done < <(asset_candidates)

    if ((!ok)); then
        if ((download_error)); then
            print_status ERR "Could not download Neovim; check connectivity and try again" >&2
        elif [[ -z $(asset_candidates) ]]; then
            print_status ERR "No prebuilt Neovim for $(uname -s)/$(uname -m)" >&2
            print_status ERR "Build from source: https://github.com/neovim/neovim/blob/master/BUILD.md" >&2
        else
            print_status ERR "The latest release has no asset for $(uname -s)/$(uname -m)" >&2
        fi
        return 1
    fi

    payload=$tmp/payload
    extract_archive "$archive" "$payload" || return 1
    if ! binary=$(find_binary_in "$payload" nvim); then
        print_status ERR "No nvim binary inside the downloaded archive" >&2
        return 1
    fi

    # A prebuilt binary can unpack fine and still not run, typically when the
    # system C library is older than the one it was built against. Find out
    # now, not after it has been made the default.
    if ! version=$(tool_version "$binary"); then
        print_status ERR "The prebuilt binary does not run on this system" >&2
        print_status ERR "Most likely the system C library is too old; use brew or build from source" >&2
        return 1
    fi

    if ! mkdir -p "$install_root"; then
        print_status ERR "Cannot create $install_root" >&2
        return 1
    fi
    rm -rf -- "${install_root:?}/${version:?}"
    # ${binary%/bin/nvim} is the unpacked tree: bin, lib, share and man.
    if ! mv -- "${binary%/bin/nvim}" "$install_root/$version"; then
        print_status ERR "Cannot move Neovim into $install_root" >&2
        return 1
    fi

    print_status DONE "Installed Neovim $version from the release archive"
    activate_release "$version"
}

# Point "current" at one installed release.
# Args: version directory name
activate_release() {
    local target=$1
    ln -sfn -- "$install_root/$target" "$install_root/current" || return 1
    nvim_cmd=$install_root/current/bin/nvim
}

# Install Neovim with the configured method, unless a new enough one is
# already there.
install_nvim() {
    local brew newest existing existing_version

    if newest=$(newest_binary nvim) && ((!force)); then
        existing_version=${newest%% *}
        existing=${newest#* }
        if version_ge "$existing_version" "$MIN_NVIM_VERSION"; then
            print_status OK "Newest installed Neovim is $existing_version at $existing (>= $MIN_NVIM_VERSION), skipping install"
            nvim_cmd=$existing
            return 0
        fi
        print_status INFO "Newest installed Neovim is only $existing_version (< $MIN_NVIM_VERSION), installing the latest"
    fi

    brew=$(find_brew)

    case $method in
        brew)
            if [[ -z $brew ]]; then
                print_status ERR "Method 'brew' requested but no brew was found" >&2
                return 1
            fi
            install_via_brew "$brew"
            ;;
        release) install_via_release ;;
        auto)
            if [[ -n $brew ]]; then
                print_status INFO "Using brew at $brew"
                install_via_brew "$brew" && return 0
                print_status WARN "brew did not work out, falling back to the release archive"
            else
                print_status INFO "No brew found, using the prebuilt release"
            fi
            install_via_release
            ;;
    esac
}

# Print the release asset holding the tree-sitter CLI for this OS and
# architecture. The CLI ships each build as a single gzipped binary and names
# them in its own style ("x64", not "x86_64"), so the names are listed instead
# of derived by pick_asset. The 32 bit x86 builds are deliberately not here.
ts_cli_asset() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)

    case $os in
        Linux)
            case $arch in
                x86_64 | amd64) printf '%s\n' tree-sitter-linux-x64.gz ;;
                aarch64 | arm64) printf '%s\n' tree-sitter-linux-arm64.gz ;;
                *) return 1 ;;
            esac
            ;;
        Darwin)
            case $arch in
                x86_64) printf '%s\n' tree-sitter-macos-x64.gz ;;
                arm64) printf '%s\n' tree-sitter-macos-arm64.gz ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

# Install the tree-sitter CLI with brew and print the resulting binary. Progress
# goes to stderr, because stdout is the return value here.
# Args: path to brew
install_ts_cli_via_brew() {
    local brew=$1 candidate version
    if "$brew" list --versions tree-sitter >/dev/null 2>&1; then
        print_status INFO "Upgrading the tree-sitter CLI with brew" >&2
        "$brew" upgrade tree-sitter >/dev/null 2>&1
    else
        print_status INFO "Installing the tree-sitter CLI with brew" >&2
        "$brew" install tree-sitter >/dev/null 2>&1
    fi

    # As elsewhere, brew's exit status is not conclusive, so the binary decides.
    for candidate in "$("$brew" --prefix tree-sitter 2>/dev/null)/bin/tree-sitter" \
        "$("$brew" --prefix 2>/dev/null)/bin/tree-sitter"; do
        if version=$(tool_version "$candidate"); then
            print_status DONE "Installed the tree-sitter CLI $version with brew" >&2
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# Download the tree-sitter CLI release and print where it ended up. The payload
# is a lone binary, so it gets the same versioned directory and "current"
# symlink treatment as everything else, next to the Neovim versions.
install_ts_cli_via_release() {
    local asset tag tmp archive payload binary version root dest
    if ! asset=$(ts_cli_asset); then
        print_status WARN "No prebuilt tree-sitter CLI for $(uname -s)/$(uname -m)" >&2
        return 1
    fi

    tag=$(github_latest_tag "$TS_CLI_REPO")
    tmp=$(mktemp -d) || return 1
    # shellcheck disable=SC2064
    trap "rm -rf -- '$tmp'" RETURN

    archive=$tmp/$asset
    print_status INFO "Fetching $asset ${tag:+($tag)}" >&2
    if ! fetch "$TS_CLI_RELEASES/latest/download/$asset" "$archive"; then
        print_status ERR "Could not download the tree-sitter CLI" >&2
        return 1
    fi

    payload=$tmp/payload
    extract_archive "$archive" "$payload" >&2 || return 1
    binary=$payload/${asset%.gz}
    if ! chmod +x -- "$binary" 2>/dev/null; then
        print_status ERR "No tree-sitter binary inside $asset" >&2
        return 1
    fi
    if ! version=$(tool_version "$binary"); then
        local glibc=''
        # No pipe: read takes the first line of ldd's output directly.
        command -v ldd >/dev/null 2>&1 && read -r glibc < <(ldd --version 2>/dev/null)
        print_status ERR "The downloaded tree-sitter CLI does not run on this system" >&2
        print_status ERR "Its official builds need a recent glibc${glibc:+, and this system has: $glibc}" >&2
        return 1
    fi

    # ${install_root%/*} is the directory holding the per-tool trees, so
    # --prefix moves the CLI along with Neovim.
    root=${install_root%/*}/tree-sitter
    dest=$root/$version
    mkdir -p "$dest" || return 1
    if ! mv -f -- "$binary" "$dest/tree-sitter"; then
        print_status ERR "Cannot move the tree-sitter CLI into $root" >&2
        return 1
    fi
    ln -sfn -- "$version" "$root/current" || return 1

    print_status DONE "Installed the tree-sitter CLI $version from $TS_CLI_REPO" >&2
    printf '%s\n' "$root/current/tree-sitter"
}

# Make sure a tree-sitter CLI new enough for nvim-treesitter is installed, is
# the one PATH picks and is visible to the headless nvim started below.
# Returns 1 when there is none and none could be installed.
ensure_ts_cli() {
    local newest version path='' brew
    if newest=$(newest_binary tree-sitter) && ((!force)); then
        version=${newest%% *}
        if version_ge "$version" "$MIN_TS_CLI_VERSION"; then
            print_status OK "tree-sitter CLI $version at ${newest#* } is new enough (>= $MIN_TS_CLI_VERSION)"
            path=${newest#* }
        else
            print_status INFO "tree-sitter CLI is only $version (< $MIN_TS_CLI_VERSION), installing the latest"
        fi
    fi

    if [[ -z $path ]]; then
        if [[ $method != release ]]; then
            brew=$(find_brew)
            if [[ -n $brew ]]; then
                path=$(install_ts_cli_via_brew "$brew") ||
                    print_status WARN "brew did not produce a working tree-sitter CLI, trying the release"
            fi
        fi
        [[ -n $path ]] || path=$(install_ts_cli_via_release) || return 1
    fi

    link_bin "$path" tree-sitter || return 1
    # The parser step runs nvim, which looks the CLI up on PATH, so this process
    # needs the link directory even when the rc file is left alone.
    prepend_install_bin_dir
}

# Ask what to do about a prerequisite this script cannot install itself. Prints
# one of retry, skip or abort. Retry exists because a user with root can install
# the missing piece in another terminal and carry on from here; skip exists
# because a user without root still wants the rest. A run with nothing attached
# to stdin cannot be asked, so it skips and says so, which keeps CI unattended.
prereq_prompt() {
    local answer
    if [[ ! -t 0 ]]; then
        print_status WARN "Not interactive, so this step is skipped" >&2
        printf 'skip\n'
        return 0
    fi
    while :; do
        # read writes its prompt to stderr, so it stays visible even though this
        # function's stdout is what the caller reads.
        read -r -p "Install it and [r]etry, [s]kip this step, or [a]bort? [s] " answer
        case ${answer,,} in
            r | retry)
                printf 'retry\n'
                return 0
                ;;
            '' | s | skip)
                printf 'skip\n'
                return 0
                ;;
            a | abort)
                printf 'abort\n'
                return 0
                ;;
            *) print_status WARN "Answer r, s or a" >&2 ;;
        esac
    done
}

# Returns 0 when something can compile C. $CC is honoured because brew's gcc is
# installed as a versioned name (gcc-14) that no plain "gcc" points at, and the
# tree-sitter CLI compiles with $CC when it is set.
have_compiler() {
    [[ -n ${CC:-} ]] && command -v "$CC" >/dev/null 2>&1 && return 0
    command -v cc >/dev/null 2>&1 ||
        command -v gcc >/dev/null 2>&1 ||
        command -v clang >/dev/null 2>&1
}

# Try to get a compiler from brew, since a machine with brew needs no root and
# no questions. Exports CC on success, because brew installs gcc under a
# versioned name that nothing on PATH resolves to.
# Args: path to brew
brew_install_compiler() {
    local brew=$1 prefix candidate newest=''
    print_status INFO "Installing gcc with brew (this can take a while)"
    "$brew" install gcc >/dev/null 2>&1

    prefix=$("$brew" --prefix gcc 2>/dev/null)
    [[ -n $prefix ]] || return 1
    # gcc-15 sorts after gcc-9 by version, not by string, so all are compared.
    for candidate in "$prefix"/bin/gcc-[0-9]*; do
        [[ -x $candidate ]] || continue
        if [[ -z $newest ]] || version_gt "${candidate##*-}" "${newest##*-}"; then
            newest=$candidate
        fi
    done

    if [[ -z $newest ]]; then
        # Some platforms do provide a plain gcc, so this is not a failure yet.
        [[ -x $prefix/bin/gcc ]] && newest=$prefix/bin/gcc
    fi
    [[ -n $newest ]] || return 1

    export CC=$newest
    print_status DONE "Using the compiler brew installed: $CC"
}

# Check what the parser step needs before any work is done, so the question is
# asked at the start rather than after a download. Only the C compiler is
# checked here: the tree-sitter CLI is something this script installs itself, and
# is dealt with at the point it turns out to be unavailable.
# Sets skip_parsers when the answer is to skip.
check_parser_prereqs() {
    local brew tried_brew=0
    while ((!skip_parsers)); do
        have_compiler && return 0

        # brew needs neither root nor a question, so it gets first refusal.
        if ((!tried_brew)) && [[ $method != release ]]; then
            tried_brew=1
            brew=$(find_brew)
            if [[ -n $brew ]]; then
                brew_install_compiler "$brew" && continue
                print_status WARN "brew could not provide a compiler"
            fi
        fi

        print_status WARN "No C compiler found, and the tree-sitter parsers cannot be built without one"
        print_status INFO "With root: apt install build-essential, dnf install gcc, or xcode-select --install on macOS"
        case $(prereq_prompt) in
            retry) print_status INFO "Looking again" ;;
            skip)
                skip_parsers=1
                print_status INFO "Continuing without the parsers; everything else still works"
                ;;
            abort)
                print_status INFO "Stopping at your request, nothing has been changed"
                exit 2
                ;;
        esac
    done
    return 0
}

# Get a tree-sitter CLI, asking what to do when none can be had. The usual cause
# is a prebuilt binary that will not run on an older system C library.
# Returns 1 when the parsers should be skipped.
ensure_ts_cli_interactive() {
    while ! ensure_ts_cli; do
        print_status WARN "Without a tree-sitter CLI the parsers cannot be built"
        print_status INFO "Get one with brew, 'cargo install tree-sitter-cli' or a distro package"
        case $(prereq_prompt) in
            retry) print_status INFO "Looking again" ;;
            skip) return 1 ;;
            abort)
                print_status INFO "Stopping at your request"
                exit 2
                ;;
        esac
    done
    return 0
}

# Fetch vim-plug into the autoload directory init.vim expects.
install_plug() {
    local plug_path="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/autoload/plug.vim"
    if [[ -s $plug_path ]] && ((!force)); then
        print_status OK "vim-plug is already installed"
        return 0
    fi
    mkdir -p "${plug_path%/*}" || return 1
    if fetch "$PLUG_URL" "$plug_path"; then
        print_status DONE "Installed vim-plug"
    else
        print_status ERR "Could not download vim-plug" >&2
        return 1
    fi
}

# Print the nvim to drive the remaining steps with: the one just installed if
# there is one, otherwise whatever is on PATH.
resolve_nvim_cmd() {
    if [[ -x $nvim_cmd ]]; then
        printf '%s\n' "$nvim_cmd"
    else
        command -v nvim 2>/dev/null
    fi
}

# Run a headless nvim command and report on it.
# Args: description, nvim arguments...
run_headless() {
    local what=$1 nvim
    shift
    nvim=$(resolve_nvim_cmd)
    if [[ ! -x $nvim ]]; then
        print_status ERR "No usable nvim to run: $what" >&2
        return 1
    fi
    print_status INFO "$what (this can take a while)"
    if "$nvim" --headless "$@" >/dev/null 2>&1; then
        print_status DONE "$what"
    else
        print_status ERR "$what failed; rerun by hand to see why: $nvim --headless $*" >&2
        return 1
    fi
}

# Run a headless nvim command and print what it wrote to stdout.
# Args: nvim arguments...
nvim_headless_output() {
    local nvim
    nvim=$(resolve_nvim_cmd)
    [[ -x $nvim ]] || return 1
    "$nvim" --headless "$@" 2>/dev/null
}

failed=0
parsers_skipped=0

# Asked first, before anything is downloaded or linked, so a missing compiler
# does not come to light at the end of a long run.
check_parser_prereqs

if ((skip_nvim)); then
    print_status INFO "Skipping the Neovim step"
else
    install_nvim || failed=1
fi

# Whether Neovim was just installed or an existing one was good enough, the
# same two things have to hold: the managed symlink points at it, and PATH
# prefers that directory. Otherwise an older nvim earlier on PATH keeps winning.
if [[ -z $nvim_cmd ]]; then
    newest=$(newest_binary nvim) && nvim_cmd=${newest#* }
fi

if [[ -n $nvim_cmd ]]; then
    link_bin "$nvim_cmd" nvim || failed=1
    if ((manage_path)); then
        ensure_path_priority nvim || failed=1
    else
        print_status INFO "Leaving PATH alone as requested"
    fi
else
    print_status ERR "No working nvim found or installed" >&2
    failed=1
fi

install_plug || failed=1

run_headless "Installing plugins" "+PlugInstall --sync" +qa || failed=1

if ((skip_parsers)); then
    print_status INFO "Skipping the tree-sitter step"
    parsers_skipped=1
elif ! ensure_ts_cli_interactive; then
    print_status WARN "Skipping the tree-sitter parsers"
    parsers_skipped=1
else
    # The language list lives in the nvim config and is exported as
    # vim.g.ts_languages, so it is not duplicated here.
    run_headless "Installing tree-sitter parsers" \
        -c 'lua local l = vim.g.ts_languages or {}; if #l > 0 then require("nvim-treesitter").install(l):wait(900000) end' \
        -c qa || failed=1

    # A headless nvim can exit 0 having logged an error, so confirm the parsers
    # are really there instead of trusting the exit code.
    installed_parsers=$(nvim_headless_output \
        -c 'lua io.write(table.concat(require("nvim-treesitter").get_installed(), " "))' -c qa)
    if [[ -z $installed_parsers ]]; then
        print_status ERR "No tree-sitter parsers are installed after the install step" >&2
        failed=1
    else
        print_status OK "Parsers installed: $installed_parsers"
    fi
fi

if ((failed)); then
    print_status ERR "Finished with errors" >&2
elif ((parsers_skipped)); then
    print_status WARN "Neovim is ready at $(resolve_nvim_cmd), but without tree-sitter parsers"
else
    print_status DONE "Neovim is ready: $(resolve_nvim_cmd)"
fi

exit "$failed"
