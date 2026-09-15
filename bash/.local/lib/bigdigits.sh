#!/usr/bin/env bash
###################################################################
# Library Name : bigdigits
# Description : Draw digits in block characters, scaled to the terminal
# Args : N/A
# Author : Barnabás Vass
###################################################################
#
# Shared by bigclock and bigtimer: the font, the colour names, the terminal size
# and the renderer. It is sourced as ../lib/bigdigits.sh relative to the script
# that wants it, which is the same path whether that script runs from the repo or
# from ~/.local/bin.

# Five rows of three pixels per character. Anything not in here is drawn blank.
declare -A GLYPH=(
    [0]='111 101 101 101 111' [1]='010 010 010 010 010'
    [2]='111 001 111 100 111' [3]='111 001 111 001 111'
    [4]='101 101 111 001 001' [5]='111 100 111 001 111'
    [6]='111 100 111 101 111' [7]='111 001 001 001 001'
    [8]='111 101 111 101 111' [9]='111 101 111 001 111'
    [':']='000 010 000 010 000'
)
declare -A COLOUR=(
    [red]=1 [green]=2 [yellow]=3 [blue]=4 [magenta]=5 [cyan]=6 [white]=7
)

# The width in font pixels of a string of characters: 3 each with a 1 pixel gap.
# Args: string
glyph_pixels() {
    printf '%s\n' "$((${#1} * 4 - 1))"
}

# Print the escape that switches to a colour given by name or by number, and
# nothing at all for an empty colour. Returns 1 when it is neither.
# Args: colour name, or a number from 0 to 255
resolve_colour() {
    local want=$1
    [[ -z $want ]] && return 0
    if [[ -n ${COLOUR[$want]:-} ]]; then
        printf '\033[38;5;%sm' "${COLOUR[$want]}"
        return 0
    fi
    [[ $want =~ ^[0-9]+$ ]] && ((want <= 255)) || return 1
    printf '\033[38;5;%sm' "$want"
}

# Turn a fraction into a percentage, so a proportion can be given either way:
# 0.8 and 80 both mean four fifths. Bash has no floating point, so the first two
# digits of the fraction are the percentage.
# Args: a percentage or a fraction
percentage() {
    local value=$1 whole frac
    case $value in
        *.*)
            whole=${value%%.*}
            frac=${value#*.}0
            frac=${frac:0:2}
            if [[ ${whole:-0} =~ ^[0-9]+$ && $frac =~ ^[0-9]+$ ]]; then
                printf '%s\n' "$((${whole:-0} * 100 + 10#$frac))"
            else
                printf '%s\n' "$value" # not a number: for the caller to reject
            fi
            ;;
        *) printf '%s\n' "$value" ;;
    esac
}

term_cols=80
term_lines=24

# Ask the terminal how big it is, into term_cols and term_lines. COLUMNS and
# LINES are not exported to a script, so this is the only way; call it once and
# again on SIGWINCH rather than every frame.
read_terminal_size() {
    local size=''
    # An exported COLUMNS and LINES wins, which is how a size can be forced.
    if [[ -n ${COLUMNS:-} && -n ${LINES:-} ]]; then
        term_cols=$COLUMNS
        term_lines=$LINES
    elif size=$(stty size 2>/dev/null </dev/tty); then
        term_lines=${size%% *}
        term_cols=${size##* }
    else
        term_lines=$(tput lines 2>/dev/null) || term_lines=24
        term_cols=$(tput cols 2>/dev/null) || term_cols=80
    fi
    [[ $term_lines =~ ^[0-9]+$ ]] || term_lines=24
    [[ $term_cols =~ ^[0-9]+$ ]] || term_cols=80
}

# Build the rows of one line of characters into BLOCK_ROWS, at the given scale:
# every font pixel becomes w columns and h rows.
# Args: string, horizontal scale, vertical scale, character to draw with
BLOCK_ROWS=()
build_block() {
    local text=$1 w=$2 h=$3 block=$4
    local i n r row pixels char on off
    local -a bits

    BLOCK_ROWS=()
    printf -v off '%*s' "$w" ''
    on=${off// /$block}

    for ((r = 0; r < 5; r++)); do
        row=''
        for ((i = 0; i < ${#text}; i++)); do
            char=${text:i:1}
            read -r -a bits <<<"${GLYPH[$char]:-000 000 000 000 000}"
            pixels=${bits[r]}
            for ((n = 0; n < 3; n++)); do
                [[ ${pixels:n:1} == 1 ]] && row+=$on || row+=$off
            done
            ((i < ${#text} - 1)) && row+=$off
        done
        for ((n = 0; n < h; n++)); do BLOCK_ROWS+=("$row"); done
    done
}
