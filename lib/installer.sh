#!/usr/bin/env bash
###################################################################
# Library Name : installer
# Description : Shared helpers for the install scripts: downloading,
#               version comparison, GitHub release assets, $HOME/bin
#               symlinks and PATH priority
# Args : N/A
# Author : Barnabás Vass
###################################################################
#
# Callers set INSTALL_BIN_DIR (where the symlinks go) and INSTALL_ROOT (where
# versioned payloads are kept) before using these, or take the defaults below.
# Everything works without root.
#
# Portability note: find, grep and tar are used instead of fd, rg and friends
# on purpose. These functions bootstrap machines where the nicer tools are not
# installed yet, which is the whole point of the install scripts.

LIB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
# shellcheck source=logger.sh
source "$LIB_DIR/logger.sh" || {
    echo "Could not load logger library!" >&2
    exit 1
}

: "${INSTALL_BIN_DIR:=$HOME/.local/bin}"
: "${INSTALL_ROOT:=$HOME/Apps}"

# Download a URL to a file, using whichever fetcher exists.
# Args: url, output path
# Returns: 0 on success, 44 if the server says the file does not exist,
#          1 on any other failure (no fetcher, network, server error)
fetch() {
    local url=$1 out=$2 code output
    if command -v curl >/dev/null 2>&1; then
        # --retry covers the transient cases (timeouts, 429, 5xx). No --fail,
        # so the status code is reported instead of a generic exit code.
        code=$(curl -sSL --retry 3 --retry-delay 2 --max-time 600 \
            -w '%{http_code}' -o "$out" "$url" 2>/dev/null)
        case $code in
            200) return 0 ;;
            403 | 404) return 44 ;;
            *)
                print_status ERR "HTTP ${code:-no response} for $url" >&2
                return 1
                ;;
        esac
    elif command -v wget >/dev/null 2>&1; then
        output=$(wget -S -O "$out" "$url" 2>&1) && return 0
        [[ $output =~ [[:space:]]40[34][[:space:]] ]] && return 44
        print_status ERR "Download failed for $url" >&2
        return 1
    else
        print_status ERR "Neither curl nor wget is available" >&2
        return 1
    fi
}

# Print a URL's body on stdout.
# Args: url
fetch_stdout() {
    local url=$1
    if command -v curl >/dev/null 2>&1; then
        curl -sSL --retry 3 --retry-delay 2 --max-time 60 "$url" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O - "$url" 2>/dev/null
    else
        return 1
    fi
}

# Print the version a program reports, e.g. 0.26.1 for "bat 0.26.1".
# The whole output is scanned rather than just the first line, because some
# tools (eza) print their name first and the version further down.
# Args: path to a binary
tool_version() {
    local bin=$1 out
    [[ -x $bin ]] || return 1
    # No pipe into head or grep here: that would report the filter's exit
    # status, so a binary that cannot even run would look fine.
    out=$("$bin" --version 2>/dev/null) || return 1
    [[ $out =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}

# Compare two dotted versions without relying on sort -V, which is not
# portable. A pre-release suffix such as -dev-1234 is ignored, so a 0.13
# nightly counts as 0.13.
# Args: version A, version B
# Returns: 0 if A >= B
version_ge() {
    local a=${1%%-*} b=${2%%-*} i
    local -a pa pb
    IFS=. read -r -a pa <<<"$a"
    IFS=. read -r -a pb <<<"$b"
    for i in 0 1 2; do
        local x=${pa[i]:-0} y=${pb[i]:-0}
        x=${x//[!0-9]/}
        y=${y//[!0-9]/}
        ((${x:-0} > ${y:-0})) && return 0
        ((${x:-0} < ${y:-0})) && return 1
    done
    return 0
}

# Returns 0 when A is strictly newer than B.
# Args: version A, version B
version_gt() {
    version_ge "$1" "$2" && ! version_ge "$2" "$1"
}

# Print the path to a usable brew, looking beyond PATH so a brew that is
# installed but not yet exported is still found.
find_brew() {
    local candidate
    candidate=$(command -v brew 2>/dev/null)
    if [[ -x $candidate ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    for candidate in "$HOME/Apps/brew/bin/brew" \
        /home/linuxbrew/.linuxbrew/bin/brew \
        "$HOME/.linuxbrew/bin/brew" \
        /opt/homebrew/bin/brew \
        /usr/local/bin/brew; do
        if [[ -x $candidate ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# Print every copy of a command this machine has, one per line, without
# duplicates. type -aP lists every match along PATH, not just the first, which
# is what makes several installed versions visible. The managed link is
# included because it may not be on PATH yet.
# Args: command name
find_all_binaries() {
    local name=$1 candidate
    local -a seen=()
    {
        printf '%s\n' "$INSTALL_BIN_DIR/$name"
        type -aP "$name" 2>/dev/null
    } | while IFS= read -r candidate; do
        [[ -n $candidate ]] || continue
        [[ -x $candidate ]] || continue
        [[ " ${seen[*]} " == *" $candidate "* ]] && continue
        seen+=("$candidate")
        printf '%s\n' "$candidate"
    done
}

# Print "<version> <path>" for the newest installed copy of a command.
# Several versions on PATH are normal and the first one found is not
# necessarily the newest, so all of them are compared. On equal versions the
# earlier candidate keeps the spot, and find_all_binaries lists the managed
# location first, so repeated runs settle on the same binary.
# Args: command name
newest_binary() {
    local name=$1 candidate version best='' best_version=''
    while IFS= read -r candidate; do
        version=$(tool_version "$candidate") || continue
        # stderr: this function's stdout is captured by its callers.
        print_status DEBUG "Found $name $version at $candidate" >&2
        if [[ -z $best_version ]] || version_gt "$version" "$best_version"; then
            best=$candidate
            best_version=$version
        fi
    done < <(find_all_binaries "$name")

    [[ -n $best ]] || return 1
    printf '%s %s\n' "$best_version" "$best"
}

# Make $INSTALL_BIN_DIR/<name> point at a binary.
# Args: absolute path to a working binary, command name
link_bin() {
    local target=$1 name=$2
    if ! tool_version "$target" >/dev/null; then
        print_status ERR "Refusing to link $target, it does not run" >&2
        return 1
    fi
    if [[ $target == "$INSTALL_BIN_DIR/$name" ]]; then
        return 0 # already the managed binary, linking it to itself would break it
    fi
    mkdir -p "$INSTALL_BIN_DIR" || return 1
    ln -sfn -- "$target" "$INSTALL_BIN_DIR/$name" || return 1
    print_status DONE "$INSTALL_BIN_DIR/$name -> $target"
}

# Print the shell startup files that could hold our lines, most likely first.
# Bash only. The first entry is the platform default: .bashrc on Linux and
# .bash_profile on macOS, the file a shell of that platform reads. The rest are
# fallbacks for when the default cannot be written, in preference order.
# .bashrc.user comes before .bash_profile on Linux on purpose: a managed
# .bashrc that is read only normally sources it, whereas .bash_profile is only
# read by login shells, so aliases put there would be missing from an ordinary
# terminal.
rc_candidates() {
    if [[ $(uname -s) == Darwin ]]; then
        printf '%s\n' "$HOME/.bash_profile" "$HOME/.bashrc.user" "$HOME/.bashrc"
    else
        printf '%s\n' "$HOME/.bashrc" "$HOME/.bashrc.user" "$HOME/.bash_profile"
    fi
    # A bash login shell falls back to .profile when there is no .bash_profile.
    printf '%s\n' "$HOME/.profile"
}

# Print the startup file to write to, in this order:
#   1. what the caller configured, via --rc-file or DOTFILES_RC_FILE
#   2. a candidate that already carries our lines, so nothing is duplicated
#   3. the platform default, when it is writable
#   4. whatever the user answers when asked
# The prompt exists because a managed .bashrc is often read only, in which case
# personal lines belong somewhere else such as ~/.bashrc.user.
# Args: a string that marks our lines, for step 2
resolve_rc_file() {
    local marker=${1:-} candidate answer fallback='' primary=''

    if [[ -n ${DOTFILES_RC_FILE:-} ]]; then
        if rc_file_usable "$DOTFILES_RC_FILE"; then
            printf '%s\n' "$DOTFILES_RC_FILE"
            return 0
        fi
        print_status ERR "Configured rc file is not writable: $DOTFILES_RC_FILE" >&2
        return 1
    fi

    if [[ -n $marker ]]; then
        while IFS= read -r candidate; do
            if [[ -f $candidate ]] && grep -qF "$marker" "$candidate" 2>/dev/null &&
                rc_file_usable "$candidate"; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done < <(rc_candidates)
    fi

    primary=$(rc_candidates | head -1)
    if rc_file_usable "$primary"; then
        printf '%s\n' "$primary"
        return 0
    fi

    # The usual case for a read only primary: a managed file plus a personal one.
    while IFS= read -r candidate; do
        [[ $candidate == "$primary" ]] && continue
        if rc_file_usable "$candidate" && [[ -f $candidate ]]; then
            fallback=$candidate
            break
        fi
    done < <(rc_candidates)

    print_status WARN "${primary/#$HOME/~} is not writable" >&2
    if [[ -t 0 ]]; then
        read -r -p "Which file should the shell entries go into? [${fallback/#$HOME/~}] " answer
        [[ -n $answer ]] || answer=$fallback
        answer=${answer/#\~/$HOME}
        if [[ -n $answer ]] && rc_file_usable "$answer"; then
            printf '%s\n' "$answer"
            return 0
        fi
        print_status ERR "Cannot write to ${answer:-nothing}" >&2
        return 1
    fi

    # Not interactive, so the question cannot be asked.
    if [[ -n $fallback ]]; then
        print_status WARN "Using ${fallback/#$HOME/~} instead; set DOTFILES_RC_FILE to choose" >&2
        printf '%s\n' "$fallback"
        return 0
    fi
    print_status ERR "No writable shell startup file found; set DOTFILES_RC_FILE" >&2
    return 1
}

# Returns 0 when a file can be appended to, existing or not.
# Args: path
rc_file_usable() {
    local path=$1
    [[ -n $path ]] || return 1
    if [[ -e $path ]]; then
        [[ -f $path && -w $path ]]
    else
        [[ -d ${path%/*} && -w ${path%/*} ]]
    fi
}

# Returns 0 when an alias of this name is already defined, either in the user's
# interactive shell or written in one of the startup files.
# Args: alias name
alias_defined() {
    local name=$1 candidate
    bash -ic "alias $name" >/dev/null 2>&1 && return 0
    while IFS= read -r candidate; do
        [[ -f $candidate ]] || continue
        grep -Eq "^[[:space:]]*alias[[:space:]]+$name=" "$candidate" 2>/dev/null && return 0
    done < <(rc_candidates)
    return 1
}

# Returns 0 when a variable is already exported in one of the startup files.
# Args: variable name
export_defined() {
    local name=$1 candidate
    while IFS= read -r candidate; do
        [[ -f $candidate ]] || continue
        grep -Eq "^[[:space:]]*export[[:space:]]+$name=" "$candidate" 2>/dev/null && return 0
    done < <(rc_candidates)
    return 1
}

# Append the entries of a shell snippet to a startup file, skipping the aliases
# and exports that are already defined so nothing of the user's is overwritten.
# Comments stay attached to the entry that follows them.
# Args: snippet path, startup file, label for the generated comment
install_shell_entries() {
    local snippet=$1 rc=$2 label=$3 line name added=0
    local -a pending=() keep=()

    while IFS= read -r line || [[ -n $line ]]; do
        case $line in
            '' | '#'*)
                pending+=("$line")
                continue
                ;;
        esac

        name=''
        if [[ $line =~ ^[[:space:]]*alias[[:space:]]+([A-Za-z0-9_-]+)= ]]; then
            name=${BASH_REMATCH[1]}
            if alias_defined "$name"; then
                print_status OK "alias $name is already defined, leaving it alone"
                pending=()
                continue
            fi
        elif [[ $line =~ ^[[:space:]]*export[[:space:]]+([A-Za-z0-9_]+)= ]]; then
            name=${BASH_REMATCH[1]}
            if export_defined "$name"; then
                print_status OK "$name is already exported, leaving it alone"
                pending=()
                continue
            fi
        fi

        keep+=("${pending[@]}" "$line")
        pending=()
        added=$((added + 1))
        [[ -n $name ]] && print_status DONE "Adding $name to ${rc/#$HOME/~}"
    done <"$snippet"

    if ((added == 0)); then
        print_status OK "Nothing new to add to ${rc/#$HOME/~} from ${snippet##*/}"
        return 0
    fi

    if ! {
        printf '\n# dotfiles: %s\n' "$label"
        printf '%s\n' "${keep[@]}"
    } >>"$rc"; then
        print_status ERR "Could not write to ${rc/#$HOME/~}" >&2
        return 1
    fi
    print_status DONE "Wrote $added new entries to ${rc/#$HOME/~}"
    return 0
}

# Decide whether a path inside a package should be linked into $HOME. The
# markers themselves never are, and a package may list further repo-side files
# in .nolink, one glob per line, so helper scripts such as aliases.sh can live
# next to the dotfiles they belong to.
# Args: package directory, path relative to it
should_link() {
    local pkg_dir=$1 rel=$2 pattern
    case $rel in
        .nolink | .nopackage) return 1 ;;
    esac
    [[ -f $pkg_dir/.nolink ]] || return 0
    while IFS= read -r pattern; do
        pattern=${pattern%%#*}
        pattern=${pattern// /}
        [[ -n $pattern ]] || continue
        # shellcheck disable=SC2053
        [[ $rel == $pattern || ${rel##*/} == $pattern ]] && return 1
    done <"$pkg_dir/.nolink"
    return 0
}

# Symlink a config file into place, keeping any previous real file as <name>.old
# as requested, rather than a timestamped copy.
# Args: source path, target path
link_config_file() {
    local src=$1 target=$2 rel=${2/#$HOME/~}

    if [[ -L $target ]] && [[ $(readlink "$target") == "$src" ]]; then
        print_status OK "$rel already linked"
        return 0
    fi
    mkdir -p "${target%/*}" || return 1
    if [[ -e $target ]] || [[ -L $target ]]; then
        if ! mv -f -- "$target" "$target.old"; then
            print_status ERR "Cannot move $rel aside" >&2
            return 1
        fi
        print_status WARN "Existing $rel saved as ${rel}.old"
    fi
    if ! ln -s -- "$src" "$target"; then
        print_status ERR "Cannot link $rel" >&2
        return 1
    fi
    print_status DONE "$rel -> $src"
}

# Put $INSTALL_BIN_DIR ahead of everything else on PATH, in this process and in
# future shells. Installing a newer tool is not enough when an older one sits
# earlier on PATH, which is the usual case for a system package in /usr/bin.
# One PATH entry covers every tool, so a single marked line is written.
# Args: command name to report on (optional)
ensure_path_priority() {
    local name=${1:-} first rc
    local marker="# dotfiles: keep $INSTALL_BIN_DIR ahead of older tools on PATH"

    if [[ -n $name ]]; then
        first=$(type -aP "$name" 2>/dev/null | head -1)
        if [[ $first == "$INSTALL_BIN_DIR/$name" ]]; then
            print_status OK "PATH already prefers $INSTALL_BIN_DIR/$name"
            return 0
        fi
        print_status WARN "PATH prefers ${first:-nothing} over $INSTALL_BIN_DIR/$name"
    fi

    rc=$(resolve_rc_file "$marker") || return 1

    if [[ -f $rc ]] && grep -qF "$marker" "$rc" 2>/dev/null; then
        print_status OK "${rc/#$HOME/~} already carries the PATH fix"
    elif {
        printf '\n%s\n' "$marker"
        # $PATH must stay literal: it is expanded when the rc file runs.
        # shellcheck disable=SC2016
        printf 'export PATH="%s:$PATH"\n' "$INSTALL_BIN_DIR"
    } >>"$rc"; then
        print_status DONE "Added the PATH fix to ${rc/#$HOME/~}"
    else
        print_status ERR "Could not update ${rc/#$HOME/~}" >&2
        return 1
    fi

    # Fix this process too, so later steps already use the new binaries.
    case ":$PATH:" in
        *":$INSTALL_BIN_DIR:"*) ;;
        *) export PATH="$INSTALL_BIN_DIR:$PATH" ;;
    esac
    hash -r 2>/dev/null
    print_status INFO "Open a new shell, or source your rc file, for this to apply to the current one"
}

# Print the tag the latest release points at, without the rate limited API:
# the releases/latest page redirects to releases/tag/<tag>.
# Args: owner/repo
github_latest_tag() {
    local repo=$1 headers=''
    local url="https://github.com/$repo/releases/latest"
    if command -v curl >/dev/null 2>&1; then
        headers=$(curl -sSI --max-time 20 "$url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        headers=$(wget -q -S --max-redirect 0 -O /dev/null "$url" 2>&1)
    fi
    [[ $headers =~ releases/tag/([^[:space:]]+) ]] && printf '%s\n' "${BASH_REMATCH[1]}"
}

# Print the asset file names of a release, one per line. The expanded_assets
# page is used rather than the REST API, which is rate limited for
# unauthenticated callers and fails on shared outbound addresses.
# Args: owner/repo, tag
github_asset_names() {
    local repo=$1 tag=$2 body line
    body=$(fetch_stdout "https://github.com/$repo/releases/expanded_assets/$tag") || return 1
    # One href per line, then keep the file name of each download link.
    printf '%s\n' "$body" | tr '>' '\n' |
        while IFS= read -r line; do
            [[ $line =~ href=\"[^\"]*/download/[^\"/]*/([^\"/]+)\" ]] &&
                printf '%s\n' "${BASH_REMATCH[1]}"
        done
}

# Print the asset that best fits this machine, chosen from names on stdin.
# Release assets of the Rust tools are named <tool>-<version>-<arch>-<os>.<ext>,
# so the platform triple is matched instead of hardcoding names per project.
pick_asset() {
    local os arch arch_token name score best='' best_score=-1
    os=$(uname -s)
    arch=$(uname -m)

    case $arch in
        x86_64 | amd64) arch_token=x86_64 ;;
        aarch64 | arm64) arch_token=aarch64 ;;
        *) arch_token=$arch ;;
    esac

    while IFS= read -r name; do
        [[ -n $name ]] || continue
        # Wrong platform, checksums, packages and installers.
        [[ $name == *windows* || $name == *.msi || $name == *.exe* ]] && continue
        [[ $name == *.sha256 || $name == *.asc || $name == *.sig ]] && continue
        [[ $name == *.deb || $name == *.rpm ]] && continue
        [[ $name == *"$arch_token"* ]] || continue
        case $os in
            Linux) [[ $name == *linux* ]] || continue ;;
            Darwin) [[ $name == *darwin* || $name == *macos* ]] || continue ;;
            *) continue ;;
        esac

        score=0
        # musl builds do not care how old the system C library is.
        [[ $name == *musl* ]] && score=$((score + 4))
        [[ $name == *.tar.gz || $name == *.tgz ]] && score=$((score + 2))
        [[ $name == *.tar.xz ]] && score=$((score + 1))
        # Reduced builds are a fallback, not a default.
        [[ $name == *no_libgit* ]] && score=$((score - 3))
        [[ $name == *.zip ]] && score=$((score - 1))

        if ((score > best_score)); then
            best=$name
            best_score=$score
        fi
    done

    [[ -n $best ]] || return 1
    printf '%s\n' "$best"
}

# Unpack an archive into a directory, whatever the format.
# Args: archive path, destination directory
extract_archive() {
    local archive=$1 dest=$2
    mkdir -p "$dest" || return 1
    case $archive in
        *.tar.gz | *.tgz) tar xzf "$archive" -C "$dest" ;;
        *.tar.xz) tar xJf "$archive" -C "$dest" ;;
        *.tar.bz2) tar xjf "$archive" -C "$dest" ;;
        *.tar) tar xf "$archive" -C "$dest" ;;
        *.zip)
            if command -v unzip >/dev/null 2>&1; then
                unzip -q -o "$archive" -d "$dest"
            else
                print_status ERR "unzip is needed for $archive" >&2
                return 1
            fi
            ;;
        *)
            print_status ERR "Unknown archive format: $archive" >&2
            return 1
            ;;
    esac
}

# Print the path of an executable inside an unpacked archive. Some projects put
# the binary in a versioned subdirectory, others at the top level, so it is
# searched for rather than assumed.
# Args: directory, binary name
find_binary_in() {
    local dir=$1 name=$2 found
    found=$(find "$dir" -type f -name "$name" -perm -u+x -print 2>/dev/null | head -1)
    [[ -n $found ]] || return 1
    printf '%s\n' "$found"
}
