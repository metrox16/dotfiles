#!/usr/bin/env bash
###################################################################
# Library Name : Nerd Icons
# Description : Common nerd-font icon codes used in Shell
# Args : N/A
# Author : Barnabás Vass
###################################################################

#! FOR NERD ICONS TO WORK YOU WILL NEED A NERD FONT IN YOUR TERMINAL!

# Some available icons
# https://www.nerdfonts.com/cheat-sheet

declare -A n_icons=(
    [GIT]='\ue702'
    [GIT_FOLDER]='\ue5fb'
    [YAML]='\ue8eb'
    [FOLDER]='\uf07b'
    [FOLDER_HOLLOW]='\uea83'
    [FOLDER_HIDDEN]='\U000F179E'
    [FILE]='\uf15b'
    [FILE_HOLLOW]='\uea7b'
    [FILE_HIDDEN]='\U000F0613'
    [XML]='\U000F05C0'
    [CONFIG]='\ue615'
    [KUBERNETES]='\ue81d'
    [DOCKER]='\ue7b0'
    [SEARCH]='\uea6d'
    [CLOUD]='\uf0c2'
    [CLOUD_HOLLOW]='\uebaa'
    [C]='\U000F0671'
    [CPP]='\U000F0672'
    [CPP_ICON]='\ue7a3'
    [PYTHON]='\uec39'
    [RUBY]='\ueb48'
    [GO]='\U000F07D3'
    [SERVER]='\uf233'
    [SERVER_HOLLOW]='\ueb50'
    [PROCESS]='\ueba2'
    [HTML]='\ue60e'
    [BASH]='\ue760'
    [BASH_SHE]='\U000F1183'
    [TERMINAL]='\ue795'
    [TERMINAL_HOLLOW]='\uea85'
    [TERMINAL_CURSOR]='\uf120'
    [LINUX]='\ue712'
    [LINUX_HOLLOW]='\uf17c'
    [APPLE]='\ue711'
    [APPLE_COMMAND]='\U000F0633'
    [APPLE_OPTION]='\U000F0635'
    [JINJA]='\ue66f'
    [CUCUMBER]='\ue7b7'
    [AWS]='\ue7ad'
    [DATABASE]='\uf1c0'
    [DATABASE_HOLLOW]='\uf472'
    [DATABASE_BASIC]='\ueace'
    [AZURE]='\ue754'
    [AZURE_HOLLOW]='\uebd8'
    [DEV]='\ueef4'
    [DEV_FLAT]='\U000F0D6E'
    [INFO]='\U000F02FC'
    [INFO_LETTER]='\uf129'
    [INFO_HOLLOW]='\uf449'
    [PHONE]='\U000F03F2'
    [MOBILE]='\uf42c'
    [RADIO]='\ueb34'
    [SINE]='\U000F095B'
    [HAND_L]='\U000F0E46'
    [HAND_L_HOLLOW]='\U000F182C'
    [HAND_R]='\U000F0E47'
    [HAND_R_HOLLOW]='\U000F182D'
    [OK]='\uf058'
    [WARN]='\uf071'
    [WARN_HOLLOW]='\uea6c'
    [ERROR]='\uea87'
    [BUG]='\ueaaf'
    [SCRIPT]='\U000F0BC1'
    [SCRIPT_HOLLOW]='\U000F0477'
    [MARKDOWN]='\U000F00BA'
    [ROUTER]='\U000F11E2'
    [ROUTER_N]='\U000F1087'
    [SWITCH_N]='\U000F04E4'
    [POWER_SWITCH]='\U000F0425'
    [SLEEP]='\U000F0904'
    [GOOGLE]='\ue7f0'
    [GOOGLE_DINOSAUR]='\U000F1362'
    [R]='\ue881'
    [SSH]='\U000F08C0'
    [TOOLS]='\U000F1064'
    [TOOLBOX]='\U000F09AC'
    [TOOLBOX_HOLLOW]='\U000F09AD'
    [COGS]='\U000F08D6'
    [JIRA]='\U000F0303'
    [ANSIBLE]='\U000F109A'
    [API]='\U000F109B'
    [DNS]='\U000F01D6'
    [SCHOOL]='\U000F0474'
    [TRANSLATE]='\U000F05CA'
    [FINGERPRINT]='\U000F0237'
    [PRESENTATION]='\U000F0428'
    [LAN]='\U000F0317'
    [CONSOLE]='\uf489'
    [REPLY]='\U000F045A'
    [CROP]='\U000F019E'
    [BACKSAPCE]='\U000F006E'
    [RADIOACTIVE]='\U000F043C'
    [ZIP]='\U000F06EB'
    [FLASH]='\uf0e7'
    [REWIND]='\U000F045F'
    [NPM]='\ue71e'
    [SWIFT]='\ue755'
    [JAVA]='\ue738'
    [JAVASCRIPT]='\ue781'
    [MONITOR]='\U000F0379'
    [SYNC]='\uf46a'
    [CPU]='\uf4bc'
    [LOCK]='\uf456'
    [UNLOCK]='\uf52a'
    [PASTE]='\uf429'
    [KEY]='\uf43d'
    [DOWNLOAD]='\uf409'
    [ALERT]='\uf421'
    [PASSKEY]='\uf4fc'
    [JSON]='\U000F0626'
    [VIM]='\ue62b'
    [VIM_LETTER]='\ue7c5'
    [NVIM]='\ue6ae'
    [UML]='\uebba'
    [USER]='\uf007'
    [USER_HOLLOW]='\uf2c0'
    [USER_ROUND]='\uf2bd'
    [USER_GROUP]='\uedca'
    # Non-Nerd Font UTF8 characters:
    [ARROW_U]='\U2191'
    [ARROW_D]='\U2193'
    [ARROW_L]='\U2190'
    [ARROW_R]='\U2192'
    [ARROW_HOLLOW_U]='\U21E7'
    [ARROW_HOLLOW_D]='\U21E9'
    [ARROW_HOLLOW_L]='\U21E6'
    [ARROW_HOLLOW_R]='\U21E8'
    [COPYRIGHT]='\U00A9'
    [TRADEMAEK]='\U2122'
)

declare -A m_sym=(
    # Greek mathematical ABC
    [ALPHA]='\U1D6C2'
    [BETA]='\U1D6C3'
    [GAMMA]='\U1D6C4'
    [DELTA]='\U1D6C5'
    [EPSILON]='\U1D6C6'
    [ZETA]='\U1D6C7'
    [ETA]='\U1D6C8'
    [THETA]='\U1D6C9'
    [IOTA]='\U1D6CA'
    [KAPPA]='\U1D6CB'
    [LAMDA]='\U1D6CC'
    [MU]='\U1D6CD'
    [NU]='\U1D6CE'
    [XI]='\U1D6CF'
    [OMICRON]='\U1D6D0'
    [PI]='\U1D6D1'
    [RHO]='\U1D6D2'
    [SIGMA]='\U1D6D4'
    [TAU]='\U1D6D5'
    [UPSILON]='\U1D6D6'
    [PHI]='\U1D6D7'
    [CHI]='\U1D6D8'
    [PSI]='\U1D6D9'
    [OMEGA]='\U1D6DA'
    [SQRT]='\U221A'
    [INTEGRAL]='\U222B'
    [SUM]='\U2211'
    [MULTIPLY]='\U00D7'
    [DIVIDE]='\U00F7'
    [PLUSMINUS]='\U00B1'
    [INTERSECT]='\U2229'
    [UNION]='\U222A'
    [INFINITE]='\U221E'
    [FORALL]='\U2200'
    [EXISTS]='\U2203'
    [EXISTS_NOT]='\U2204'
    [EMPTY]='\U2205'
    [ALMOST_EQUAL]='\U2248'
    [NOT_EQUAL]='\U2260'
)

if ! (return 2>/dev/null); then # code, you don't want to call if the file is sourced
    # only run code, if called directly. e.g. testing the library
    cyan_italic='\033[3;36m'
    purple_bold='\033[1;35m'
    nc='\033[0m'
    printf "Availible icons (use array [%bn_icons%b]:\n" "$cyan_italic" "$nc"
    (
        per_line=4
        padding=8
        line=0
        while read -r i; do
            printf "%s\t%b%*s" "$i" "${n_icons[$i]}" "$padding" ""
            ((++line % per_line == 0)) && printf '\n'
        done < <(printf '%s\n' "${!n_icons[@]}" | LC_ALL=C sort)
    ) | column -td -s $'\t'
    printf "Use '%bnprint <name>%b' or '%bnrpint_nl <name>%b' to print an icon. Use '%bncode <name>%b' to print the escae code as-is.\n" "$purple_bold" "$nc" "$purple_bold" "$nc" "$purple_bold" "$nc" 
    printf "\nAvailible mathematical symbols (use array[%bm_sym%b]:\n" "$cyan_italic" "$nc"
    (
        per_line=4
        padding=8
        line=0
        while read -r i; do
            printf "%s\t%b%*s" "$i" "${m_sym[$i]}" "$padding" ""
            ((++line % per_line == 0)) && printf '\n'
        done < <(printf '%s\n' "${!m_sym[@]}" | LC_ALL=C sort)
    ) | column -td -s $'\t'
    printf "Use '%bmprint <name>%b' or '%bmrpint_nl <name>%b' to print a mathematical symbol.\n" "$purple_bold" "$nc" "$purple_bold" "$nc"
    exit 0
fi

# You can use this function to convert double unicode bytes to proper printable ones:
# '\udb81\ude26'    <- can't print
# '\U000F0626'      <- output: can print
_nfesc() {
    local hi=$((0x${1:2:4})) lo
    if ((hi >= 0xd800 && hi <= 0xdbff)); then
        lo=$((0x${1:8:4}))
        hi=$((0x10000 + (\
            hi - 0xd800) * 0x400 + (lo - 0xdc00)))
    fi
    printf '\\U%08X\n' "$hi"
}

# You can use this to print nerd fonts
nprint() {
    local key="${1^^}"
    printf "%b" "${n_icons[$key]}"
}

# You can use this to print nerd fonts with a newline
nprint_nl() {
    local key="${1^^}"
    printf "%b\n" "${n_icons[$key]}"
}

# You can use this to print the acutal value from the array, i.e. the Unicode code
ncode() {
    local key="${1^^}"
    printf '%s\n' "${n_icons[$key]}"
}

# You can use this to print mathematical symbols
mprint() {
    local key="${1^^}"
    printf "%b" "${m_sym[$key]}"
}

# You can use this to print mathematical symbols with a newline
mprint_nl() {
    local key="${1^^}"
    printf "%b\n" "${m_sym[$key]}"
}
