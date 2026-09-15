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

# These libraries use associative arrays, which macOS's stock /bin/bash is too
# old for. The feature itself is probed rather than a version number compared,
# so what is tested is what is actually needed. The subshell keeps the throwaway
# variable, and the error message of an old bash, out of the way.
if ! (declare -A _probe=()) 2>/dev/null; then
    echo "This bash has no associative arrays, so it is too old to run this." >&2
    echo "Use bash 4 or newer; on macOS, install a current bash and rerun." >&2
    exit 1
fi

LIB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
# shellcheck source=logger.sh
source "$LIB_DIR/logger.sh" || {
    echo "Could not load logger library!" >&2
    exit 1
}

# Everything lives under ~/.local: the executables on PATH in bin, the unpacked
# release trees in opt. A downloaded release is not a bare binary (Neovim ships
# lib and share/nvim/runtime, the Rust tools ship man pages and completions), so
# the payload needs a directory of its own and cannot sit in a bin directory.
: "${INSTALL_BIN_DIR:=$HOME/.local/bin}"
: "${INSTALL_ROOT:=$HOME/.local/opt}"

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

# Print the path to a usable brew, or nothing when this machine has none.
# Only brew's own mechanisms are consulted, so no install location is baked in:
# the command on PATH, and HOMEBREW_PREFIX, which "brew shellenv" exports. A
# brew that is installed but reachable through neither is not used; the install
# scripts then fall back to the project's own release, which is the same thing
# they do on a machine without brew. Set DOTFILES_BREW to point at an
# unexported brew explicitly.
find_brew() {
    local candidate

    if [[ -n ${DOTFILES_BREW:-} ]]; then
        if [[ -x $DOTFILES_BREW ]]; then
            printf '%s\n' "$DOTFILES_BREW"
            return 0
        fi
        print_status WARN "DOTFILES_BREW is not an executable: $DOTFILES_BREW" >&2
    fi

    candidate=$(command -v brew 2>/dev/null)
    if [[ -x $candidate ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [[ -n ${HOMEBREW_PREFIX:-} ]] && [[ -x $HOMEBREW_PREFIX/bin/brew ]]; then
        printf '%s\n' "$HOMEBREW_PREFIX/bin/brew"
        return 0
    fi

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

# Set TRIMMED to a string without its leading and trailing whitespace. A global
# rather than stdout, because a command substitution forks a process and this
# runs for every line of every startup file.
TRIMMED=''
trim() {
    local s=$1
    s=${s#"${s%%[![:space:]]*}"}
    TRIMMED=${s%"${s##*[![:space:]]}"}
}

# The kinds of entry a shell startup file is made of, matched by name so an entry
# of ours can be compared with one of yours: an alias, a variable exported or
# not, a function, and failing that a plain statement such as an eval or a shopt,
# which is named after the command it runs. A bare NAME=value counts as the same
# variable as "export NAME=value": being exported is not what tells two
# definitions of $HISTSIZE apart.
ENTRY_RE_ALIAS='^[[:space:]]*alias[[:space:]]+([^[:space:]=]+)='
ENTRY_RE_FUNC='^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*\(\)'
ENTRY_RE_EXPORT='^[[:space:]]*(export|declare|typeset)[[:space:]]+(-[A-Za-z]+[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)='
ENTRY_RE_VAR='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)='

# Set ENTRY_KEY to "alias l", "var HISTSIZE", "function mkcd" or "statement shopt
# histappend" for a line that defines something, and to nothing for anything
# else. ENTRY_BLOCK says whether the entry carries on over the following lines,
# which a function does.
#
# The cheap glob tests come first on purpose: this runs for every line of every
# startup file, and a regex on each of them is what made it slow.
# Args: a trimmed line, whether a nameless statement counts (default yes)
ENTRY_KEY=''
ENTRY_BLOCK=0
classify_entry() {
    local line=$1 allow_statement=${2:-1}
    ENTRY_KEY=''
    ENTRY_BLOCK=0

    case $line in
        alias[[:space:]]*)
            [[ $line =~ $ENTRY_RE_ALIAS ]] &&
                # Everything up to the '=' is the name: '..' is a good alias name.
                ENTRY_KEY="alias ${BASH_REMATCH[1]}"
            return 0
            ;;
        *'()'*)
            if [[ $line =~ $ENTRY_RE_FUNC ]]; then
                ENTRY_KEY="function ${BASH_REMATCH[2]}"
                ENTRY_BLOCK=1
                return 0
            fi
            ;;
    esac

    if [[ $line == *=* ]]; then
        case $line in
            export[[:space:]]* | declare[[:space:]]* | typeset[[:space:]]*)
                if [[ $line =~ $ENTRY_RE_EXPORT ]]; then
                    ENTRY_KEY="var ${BASH_REMATCH[3]}"
                    return 0
                fi
                ;;
        esac
        if [[ $line =~ $ENTRY_RE_VAR ]]; then
            ENTRY_KEY="var ${BASH_REMATCH[1]}"
            return 0
        fi
    fi

    # A statement that defines nothing by name: an eval, a shopt, a source, a
    # set. Its identity is the command with the arguments that are not option
    # flags, so "shopt -s histappend" and "shopt -u histappend" are two versions
    # of one entry rather than two unrelated lines, and so is an eval of the same
    # command with different flags.
    ((allow_statement)) || return 0
    local token noglob=0
    local -a parts=() words=()
    local IFS=$' \t'
    [[ -o noglob ]] || noglob=1
    set -f
    # Word splitting on purpose, with globbing off for it.
    # shellcheck disable=SC2206
    parts=(${line//[\"\'\`;]/})
    ((noglob)) && set +f
    for token in "${parts[@]}"; do
        token=${token//\$(/}
        token=${token//[()]/}
        [[ -z $token || $token == -* ]] && continue
        words+=("$token")
    done
    ((${#words[@]} > 0)) && ENTRY_KEY="statement ${words[*]}"
    return 0
}

# Returns 0 when a line closes the function being collected: where its braces
# balance out, or on a closing brace in the first column. Neither test alone is
# enough - an awk script full of braces defeats the second, a body closed with
# indentation defeats the first. Quotes are not parsed, so a lone brace inside a
# string can throw the balance off, which is what the first-column test is for.
# Args: raw line, trimmed line
BRACE_DEPTH=0
ends_function() {
    local opens=${2//[^\{]/} closes=${2//[^\}]/}
    BRACE_DEPTH=$((BRACE_DEPTH + ${#opens} - ${#closes}))
    [[ $1 == '}' ]] && return 0
    ((BRACE_DEPTH <= 0))
}

# Keep a snippet in a marked region of a shell startup file. What the snippet
# holds does not matter - aliases, exports, functions, shopt lines, anything -
# because it is copied verbatim between the markers. Rerunning is a text
# comparison: a region that already matches is left alone, and a snippet that has
# changed replaces its region rather than being appended a second time.
#
# Where you already define an entry outside the region:
#   the same definition, word for word  ours is left out, yours is already it
#   a different definition              ours goes in commented out, so yours
#                                       stays in charge and ours is there to
#                                       compare and uncomment
#
# An entry of ours starts in the first column and anything indented is its body,
# which is what lets a function, an if/for/while/case block or a line left open on
# a parenthesis be treated as the single entry it is.
# Args: snippet path, startup file, label used in the markers
install_shell_entries() {
    local snippet=$1 rc=$2 label=$3
    local begin="# >>> dotfiles: $label >>>"
    local end="# <<< dotfiles: $label <<<"
    local line candidate content current='' wanted='' tmp verb key block_end
    local i j n first in_region=0 have_region=0 in_ours=0 entries=0 same=0 clash=0
    local -a before=() after=() region=() want=() yours=() lines=() block=() pending=() rc_lines=()
    local -A defined=() stmt_cmds=()

    # The file as it stands, split around the region this manages. mapfile rather
    # than a read loop: it is a builtin reading the whole file at once, which on a
    # long startup file is the difference between milliseconds and tens of them.
    if [[ -f $rc ]]; then
        mapfile -t rc_lines <"$rc"
        for line in "${rc_lines[@]}"; do
            if [[ $line == "$begin" ]]; then
                in_region=1
                have_region=1
                continue
            fi
            if ((in_region)); then
                if [[ $line == "$end" ]]; then
                    in_region=0
                else
                    region+=("$line")
                fi
            elif ((have_region)); then
                after+=("$line")
            else
                before+=("$line")
            fi
        done
    fi

    # Half a region means the file was edited by hand into a state where
    # rewriting it would throw lines away, so nothing is touched.
    if ((in_region)); then
        print_status ERR "${rc/#$HOME/~} opens the $label region but never closes it; fix it by hand" >&2
        return 1
    fi

    # The snippet first: which commands its nameless statements use decides what
    # is worth taking apart when indexing your files below, which saves doing that
    # for hundreds of lines that could never match one of ours.
    mapfile -t lines <"$snippet"
    for line in "${lines[@]}"; do
        [[ -z ${line//[[:space:]]/} || $line == '#'* || $line == [[:space:]]* ]] && continue
        classify_entry "$line"
        [[ $ENTRY_KEY == 'statement '* ]] && stmt_cmds[${line%%[[:space:]]*}]=1
    done

    # Everything the startup files define, our own regions aside: they hold what
    # we wrote last time, which is not yours to keep.
    yours=("${before[@]}" "${after[@]}")
    while IFS= read -r candidate; do
        [[ $candidate == "$rc" ]] && continue
        [[ -f $candidate && -r $candidate ]] || continue
        mapfile -t -O "${#yours[@]}" yours <"$candidate"
    done < <(rc_candidates)

    n=${#yours[@]}
    for ((i = 0; i < n; i++)); do
        line=${yours[i]}
        # A region of ours in another file, from another package or an earlier
        # run, is not yours either. The markers are written at column 0, so they
        # need no trimming.
        case $line in
            '# >>> dotfiles: '*)
                in_ours=1
                continue
                ;;
            '# <<< dotfiles: '*)
                in_ours=0
                continue
                ;;
        esac
        ((in_ours)) && continue

        trim "$line"
        [[ -z $TRIMMED || $TRIMMED == '#'* ]] && continue
        # A line that defines nothing, of which a startup file is mostly made, is
        # dropped here rather than in the classifier: skipping the call is what
        # keeps this quick on a long configuration.
        case $TRIMMED in
            *=* | *'()'* | alias[[:space:]]* | export[[:space:]]* | declare[[:space:]]* | typeset[[:space:]]*) ;;
            *) [[ -n ${stmt_cmds[${TRIMMED%%[[:space:]]*}]:-} ]] || continue ;;
        esac
        classify_entry "$TRIMMED" "${stmt_cmds[${TRIMMED%%[[:space:]]*}]:-0}"
        [[ -n $ENTRY_KEY ]] || continue
        key=$ENTRY_KEY
        first=$TRIMMED
        content=$first
        if ((ENTRY_BLOCK)); then
            # A function is one definition, body and all, and the body is not
            # searched for definitions of its own: an alias set inside a function
            # is not an alias you have.
            BRACE_DEPTH=0
            if ! ends_function "${yours[i]}" "$first"; then
                while ((i + 1 < n)); do
                    i=$((i + 1))
                    trim "${yours[i]}"
                    content+=$'\n'$TRIMMED
                    ends_function "${yours[i]}" "$TRIMMED" && break
                done
            fi
        else
            # A control structure, or a line left open on a parenthesis, is
            # recorded whole too, so one of ours can be compared against all of
            # it. It is only read ahead, not consumed: what it sets inside still
            # counts as something you have.
            block_end=''
            case $first in
                *'(') block_end=')' ;;
                if | if[[:space:]]*) block_end='fi' ;;
                for[[:space:]]* | while[[:space:]]* | until[[:space:]]*) block_end='done' ;;
                case[[:space:]]*) block_end='esac' ;;
            esac
            [[ -n $block_end && $first == *"$block_end" ]] && block_end=''
            if [[ -n $block_end ]]; then
                for ((j = i + 1; j < n; j++)); do
                    trim "${yours[j]}"
                    content+=$'\n'$TRIMMED
                    [[ $TRIMMED == "$block_end" || $TRIMMED == "$block_end;"* ]] && break
                done
            fi
        fi
        # A name can be defined more than once, so every definition is kept and
        # matched as a whole record between the separators. A block counts as its
        # first line as well, in case ours is only that line.
        defined[$key]+=$'\x01'$content$'\x01'
        [[ $content == "$first" ]] || defined[$key]+=$'\x01'$first$'\x01'
    done

    n=${#lines[@]}
    for ((i = 0; i < n; i++)); do
        line=${lines[i]}
        # A comment or a blank line belongs to the entry that follows it, and goes
        # away with it when that entry turns out to be yours already.
        if [[ -z ${line//[[:space:]]/} || $line == '#'* ]]; then
            pending+=("$line")
            continue
        fi
        # An entry of ours starts in the first column, so anything indented is the
        # body of one and is copied across untouched.
        if [[ $line == [[:space:]]* ]]; then
            want+=("${pending[@]}" "$line")
            pending=()
            continue
        fi

        classify_entry "$line"
        key=$ENTRY_KEY
        block=("$line")
        trim "$line"
        content=$TRIMMED

        # How an entry that spans lines ends. Ours are kept or dropped whole: a
        # split one leaves an orphaned body behind, and dropping a 'fi' or a ')'
        # of ours because you happen to have one too would leave your startup
        # file unable to parse.
        block_end=''
        if ((ENTRY_BLOCK)); then
            block_end='}'
        elif [[ $TRIMMED == *'(' ]]; then
            # A line left open on a parenthesis: a command substitution spread
            # over several lines, as LESS_TERMCAP_mb=$( ... ) is written.
            block_end=')'
        else
            case $TRIMMED in
                if | if[[:space:]]*) block_end='fi' ;;
                for[[:space:]]* | while[[:space:]]* | until[[:space:]]*) block_end='done' ;;
                case[[:space:]]*) block_end='esac' ;;
            esac
            # Written on one line, so it is complete already.
            [[ -n $block_end && $TRIMMED == *"$block_end" ]] && block_end=''
        fi

        # The line that closes an entry of ours is in the first column and its
        # body is indented, so a nested 'fi' or '}' does not end it early.
        if [[ $block_end == '}' ]]; then
            BRACE_DEPTH=0
            # A function written on one line is complete already.
            ends_function "$line" "$TRIMMED" && block_end=''
        fi
        while [[ -n $block_end ]] && ((i + 1 < n)); do
            i=$((i + 1))
            block+=("${lines[i]}")
            trim "${lines[i]}"
            content+=$'\n'$TRIMMED
            if [[ $block_end == '}' ]]; then
                ends_function "${lines[i]}" "$TRIMMED" && break
            else
                [[ ${lines[i]} == "$block_end" || ${lines[i]} == "$block_end;"* ]] && break
            fi
        done

        if [[ -n $key && -n ${defined[$key]:-} ]]; then
            if [[ ${defined[$key]} == *$'\x01'"$content"$'\x01'* ]]; then
                same=$((same + 1))
                pending=()
                continue
            fi
            clash=$((clash + 1))
            want+=("${pending[@]}" "# your own $key differs, so ours is left here commented out:")
            pending=()
            for candidate in "${block[@]}"; do
                want+=("#${candidate:+ }$candidate")
            done
            continue
        fi

        want+=("${pending[@]}" "${block[@]}")
        pending=()
        entries=$((entries + 1))
    done

    # A first entry that turned out to be yours takes its comment with it and can
    # leave the region starting on a blank line.
    while ((${#want[@]} > 0)) && [[ -z ${want[0]//[[:space:]]/} ]]; do
        want=("${want[@]:1}")
    done

    # Nothing of the snippet is left to install, so no region of leftover
    # comments is created either.
    if ((entries == 0 && clash == 0 && !have_region)); then
        print_status OK "${snippet##*/}: all $same entries are already yours, nothing to add"
        return 0
    fi

    ((${#region[@]} > 0)) && printf -v current '%s\n' "${region[@]}"
    ((${#want[@]} > 0)) && printf -v wanted '%s\n' "${want[@]}"

    if ((have_region)) && [[ $current == "$wanted" ]]; then
        print_status OK "${rc/#$HOME/~} already carries the $label region"
        return 0
    fi

    # Written next to the file and then copied over it, rather than moved into
    # place: that keeps the inode, so a startup file that is a symlink stays one.
    tmp=$rc.dotfiles-new
    if ! {
        if ((${#before[@]} > 0)); then
            printf '%s\n' "${before[@]}"
            # A blank line before the marker, unless there is one already.
            [[ -n ${before[${#before[@]}-1]} ]] && printf '\n'
        fi
        printf '%s\n' "$begin"
        printf '%s' "$wanted"
        printf '%s\n' "$end"
        if ((${#after[@]} > 0)); then printf '%s\n' "${after[@]}"; fi
    } >"$tmp"; then
        print_status ERR "Could not write ${tmp/#$HOME/~}" >&2
        return 1
    fi
    if ! cat -- "$tmp" >"$rc"; then
        print_status ERR "Could not write ${rc/#$HOME/~}, the new version is at ${tmp/#$HOME/~}" >&2
        return 1
    fi
    rm -f -- "$tmp"

    ((have_region)) && verb=Updated || verb=Added
    print_status DONE "$verb the $label region in ${rc/#$HOME/~}: $entries entries, $same already yours, $clash commented out where yours differs"
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

# Put $INSTALL_BIN_DIR on this process's PATH, so the steps that follow, and the
# programs they start, find what was just installed. Future shells are a
# separate matter, handled by ensure_path_priority.
prepend_install_bin_dir() {
    case ":$PATH:" in
        *":$INSTALL_BIN_DIR:"*) ;;
        *) export PATH="$INSTALL_BIN_DIR:$PATH" ;;
    esac
    hash -r 2>/dev/null
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
    prepend_install_bin_dir
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
    local os arch token name score matched best='' best_score=-1
    local -a arch_tokens
    os=$(uname -s)
    arch=$(uname -m)

    # Both spellings of the architecture are accepted, because the naming
    # follows the language rather than the platform: the Rust tools use the LLVM
    # triple (x86_64, aarch64), Go projects the GOARCH name (amd64, arm64).
    case $arch in
        x86_64 | amd64) arch_tokens=(x86_64 amd64) ;;
        aarch64 | arm64) arch_tokens=(aarch64 arm64) ;;
        *) arch_tokens=("$arch") ;;
    esac

    while IFS= read -r name; do
        [[ -n $name ]] || continue
        # Wrong platform, checksums, packages and installers.
        [[ $name == *windows* || $name == *.msi || $name == *.exe* ]] && continue
        [[ $name == *.sha256 || $name == *.asc || $name == *.sig ]] && continue
        [[ $name == *.deb || $name == *.rpm ]] && continue
        matched=0
        for token in "${arch_tokens[@]}"; do
            if [[ $name == *"$token"* ]]; then
                matched=1
                break
            fi
        done
        ((matched)) || continue
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

# Returns 0 when a file name is one of the archives extract_archive unpacks.
# A release asset that is not an archive is the bare binary itself, which is how
# Go projects ship, so the caller can tell the two apart before unpacking.
# Args: file name
is_archive_name() {
    case $1 in
        *.tar.gz | *.tgz | *.tar.xz | *.tar.bz2 | *.tar | *.gz | *.zip) return 0 ;;
    esac
    return 1
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
        *.gz)
            # A bare .gz is one compressed file rather than an archive, which is
            # how some projects ship a single binary. tar cannot unpack it, and
            # the result keeps the name without the suffix. Executability is the
            # caller's business, since a .gz need not hold a program.
            local out=${archive##*/}
            out=$dest/${out%.gz}
            if command -v gzip >/dev/null 2>&1; then
                gzip -dc -- "$archive" >"$out"
            elif command -v gunzip >/dev/null 2>&1; then
                gunzip -c -- "$archive" >"$out"
            else
                print_status ERR "gzip is needed for $archive" >&2
                return 1
            fi
            ;;
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
# searched for rather than assumed. A name with the platform appended counts too,
# which is how gdu ships: gdu_linux_amd64.
# Args: directory, binary name
find_binary_in() {
    local dir=$1 name=$2 found
    found=$(find "$dir" -type f -name "$name" -perm -u+x -print 2>/dev/null | head -1)
    [[ -n $found ]] ||
        found=$(find "$dir" -type f -name "${name}[_-]*" -perm -u+x -print 2>/dev/null | head -1)
    [[ -n $found ]] || return 1
    printf '%s\n' "$found"
}
