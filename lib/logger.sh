#!/usr/bin/env bash
###################################################################
# Library Name : logger
# Description : Standard logger for Bash scripts
# Args : N/A
# Author : Barnabás Vass
###################################################################

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
# shellcheck source=color.sh
source "$SCRIPT_DIR/color.sh" || {
    echo "Could not load color library!" >&2
    exit 1
}

declare -A format=(
    [OK]="[${colors[GREEN]}OK${colors[NC]}]"
    [WARN]="[${colors[S_YELLOW]}WARNING${colors[NC]}]"
    [ERR]="[${colors[B_RED]}ERROR${colors[NC]}]"
    [DEBUG]="[${colors[S_GREY]}DEBUG${colors[NC]}]"
    [INFO]="[${colors[B_BLUE]}INFO${colors[NC]}]"
    [DONE]="[${colors[B_GREEN]}DONE${colors[NC]}]"
)

print_status() {
    local status="${1?'[print_status] You need at least one argument!'}"
    status="${status^^}"
    local message="$2"
    local newline="${3:-1}" # Use newline, if not explicitly given
    if [[ $# -eq 1 ]]; then # Default to INFO if only one argument is given
        message=$1
        status="INFO"
    fi
    [[ "$status" == "INFO_WITHOUT_NEWLINE" ]] && newline=0

    local max_len=0
    local i len str
    # shellcheck disable=SC2302
    for i in "${format[@]}"; do
        printf -v str "%b" "$i"
        len="${#str}"
        ((len > max_len)) && max_len="$len"
    done

    [[ ! "${format[$status]}" ]] && status="INFO" # Default to info

    printf "%-*b %s" "$max_len" "${format[$status]}" "$message"
    ((newline)) && printf "\n"
}

print_timed_status() {
    printf "%(%Y-%m-%d %H:%M:%S)T - " -1
    print_status "$@"
}

if ! (return 2>/dev/null); then # code, you don't want to call if the file is sourced
    # only run code, if called directly. e.g. testing the library
    echo -e "Usage: ${colors[B_PURPLE]}print_status${colors[NC]} <formatting> <message> [optional: newline=1] (default=yes)"
    for i in "${!format[@]}"; do
        print_status "$i" "This is $i"
    done
    print_status "INFO_WITHOUT_NEWLINE" "This is INFO_WITHOUT_NEWLINE "
    echo "something else"
    print_status "INFO" "This is the same " "0"
    echo "something else"

    echo -e "\n================\n"
    echo -e "Usage: ${colors[B_PURPLE]}print_timed_status${colors[NC]} <formatting> <message> [optional: newline=1] (default=yes)"
    echo "(same as print_status)"
    for i in "${!format[@]}"; do
        print_timed_status "$i" "This is $i"
    done
fi
