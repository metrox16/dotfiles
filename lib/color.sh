#!/usr/bin/env bash
###################################################################
# Library Name : color
# Description : Common colour codes used in Shell
# Args : N/A
# Author : Barnabás Vass
###################################################################

COLORED_STRING="Lorem Ipsum"

# Define colours and print functions
declare -A colors=( # 8bit colours [256]
    [NC]='\033[0m'        # No colour | reset
    [GREY]='\033[0;30m'   # Normal
    [S_GREY]='\033[0;90m' # Saturated [S]
    [B_GREY]='\033[1;30m' # Bold      [B]
    [I_GREY]='\033[3;30m' # Italic    [I]
    [RED]='\033[0;31m'
    [S_RED]='\033[0;91m'
    [B_RED]='\033[1;31m'
    [I_RED]='\033[3;31m'
    [GREEN]='\033[0;32m'
    [S_GREEN]='\033[0;92m'
    [B_GREEN]='\033[1;32m'
    [I_GREEN]='\033[3;32m'
    [YELLOW]='\033[0;33m'
    [S_YELLOW]='\033[0;93m'
    [B_YELLOW]='\033[1;33m'
    [I_YELLOW]='\033[3;33m'
    [BLUE]='\033[0;34m'
    [S_BLUE]='\033[0;94m'
    [B_BLUE]='\033[1;34m'
    [I_BLUE]='\033[3;34m'
    [PURPLE]='\033[0;35m'
    [S_PURPLE]='\033[0;95m'
    [B_PURPLE]='\033[1;35m'
    [I_PURPLE]='\033[3;35m'
    [CYAN]='\033[0;36m'
    [S_CYAN]='\033[0;96m'
    [B_CYAN]='\033[1;36m'
    [I_CYAN]='\033[3;36m'
    [WHITE]='\033[0;37m'
    [S_WHITE]='\033[0;97m'
    [B_WHITE]='\033[1;37m'
    [I_WHITE]='\033[3;37m'
)

declare -A true_colors=(
    [P_WHITE]='\e[38;2;255;255;255m'
    [P_BLACK]='\e[38;2;0;0;0m'
    [P_RED]='\e[38;2;255;0;0m'
    [P_GREEN]='\e[38;2;0;255;0m'
    [P_BLUE]='\e[38;2;0;0;255m'
)

# Print an RGB color code
# Usage example: echo -e "Hi this is $(rgb_color 155 23 57)COLOR\033[0m"
# ATTR: 1=bold 3=italic 4=underline (default none/0)
# Needs truecolor terminal to work
rgb_color() {
    [[ $# -ge 3 ]] || return 1
    [[ "$COLORTERM" == "truecolor" ]] || return 2
    local r=$1
    local g=$2
    local b=$3
    local attr=${4:-0}
    local c
    for c in "$r" "$g" "$b"; do
        [[ $c =~ ^[0-9]+$ ]] && ((c <= 255)) || return 3
    done
    printf '\e[%d;38;2;%d;%d;%dm' "$attr" "$r" "$g" "$b"
}

if ! (return 2>/dev/null); then # code, you don't want to call if the file is sourced
    # only run code, if called directly. e.g. testing the library
    get_sorted_keys() {
        base_colors=()
        for k in "${!colors[@]}"; do
            [[ $k =~ '_' || $k == 'NC' ]] || base_colors+=("$k")
        done
        mapfile -t base_colors < <(printf '%s\n' "${base_colors[@]}" | sort)
        prefix=("S" "B" "I")
        sorted=()
        for base in "${base_colors[@]}"; do
            sorted+=("$base") # Start with base
            for pref in "${prefix[@]}"; do
                re_col="^${pref}_${base}$"
                for i in "${!colors[@]}"; do
                    if [[ "$i" =~ $re_col ]]; then
                        sorted+=("${BASH_REMATCH[0]}")
                    fi
                done
            done
        done
        printf "%s\n" "${sorted[@]}"
    }

    get_max_len() { # For padding
        local max=0
        local i
        for i in "${!colors[@]}"; do
            len="${#i}"
            ((max = len > max ? len : max))
        done
        echo $max
    }

    MAX_LEN=$(get_max_len)
    ((MAX_LEN += 2))

    mapfile -t SORTED_KEYS < <(get_sorted_keys)
    # Check if all colors are found
    COLOR_COUNT="${#colors[@]}"
    ((COLOR_COUNT -= 1))
    [[ "${#SORTED_KEYS[@]}" -eq "$COLOR_COUNT" ]] || {
        echo "Missing color!" >&2
        exit 1
    }

    echo -e "Availible colours: {colors}\n[S]aturated, [B]old, [I]talic"
    for i in "${SORTED_KEYS[@]}"; do
        if [[ $i == 'NC' ]]; then continue; fi # Skip no colour
        printf "%-*s %b%s%b\n" "$MAX_LEN" "$i:" "${colors[$i]}" "${COLORED_STRING}" "${colors[NC]}"
    done
    if [[ $COLORTERM == 'truecolor' ]]; then
        echo -e "\nTrue colour available: {true_colors}"
        for i in "${!true_colors[@]}"; do
            printf "%-*s %b%s%b\n" "$MAX_LEN" "$i:" "${true_colors[$i]}" "${COLORED_STRING}" "${colors[NC]}"
        done
    fi
fi
