# Shell entries that belong to no particular tool. install.sh keeps this file in
# a marked region of your shell startup file: aliases, exports, functions and
# plain statements alike. An entry you already define the same way is left out,
# and one you define differently goes in commented out, so yours keeps winning.
#
# Only bash builtins and standard utilities are used here, so these work on a
# machine where none of the other tools are installed yet.

# Aliases
if ls --color=auto /dev/null &>/dev/null; then
  alias ls='ls -p --color=auto'
else
  alias ls='ls -p -G'
fi
alias ll='ls -lah'
alias reload='exec bash -l'
alias res='reload'
alias viba='vi ~/.bashrc'
alias vissh='vi ~/.ssh/config'
alias scp='scp -o IPQoS=throughput -o Compression=no'
alias hudate='date "+%Y-%m-%d %H:%M:%S"'
alias logdif="git log --oneline | fzf --preview 'git show {1}'"



# Exports
export EDITOR=nvim
export KUBE_EDITOR=nvim
export HISTTIMEFORMAT='%F %T '
export COLORTERM=truecolor
export TIME_STYLE=long-iso # Use ISO common format
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced
# Less colours
export LESS_TERMCAP_mb=$(
  tput bold
  tput setaf 1
)
export LESS_TERMCAP_md=$(
  tput bold
  tput setaf 1
)
export LESS_TERMCAP_me=$(tput sgr0)
export LESS_TERMCAP_se=$(tput sgr0)
export LESS_TERMCAP_so=$(
  tput bold
  tput setaf 3
  tput setab 4
)
export LESS_TERMCAP_ue=$(tput sgr0)
export LESS_TERMCAP_us=$(tput rev)
export LESS_TERMCAP_mr=$(tput dim)
export LESS_TERMCAP_ZN=$(tput ssubm)
export LESS_TERMCAP_ZV=$(tput rsubm)
export LESS_TERMCAP_ZO=$(tput ssupm)
export LESS_TERMCAP_ZW=$(tput rsupm)




# Functions
nc='\033[0m'
_info() {
  local blue='\033[1;34m'
  printf "[%bINFO%b]  %b\n" "$blue" "$nc" "$1"
}
_ok() {
  local green='\033[0;32m'
  printf "[%bOK%b]    %b\n" "$green" "$nc" "$1"
}
_err() {
  local red='\033[1;31m'
  printf "[%bERROR%b] %b\n" "$red" "$nc" "$1"
}
# print a colorized diff
colordiff() {
  local red=$(tput setaf 1 2>/dev/null)
  local green=$(tput setaf 2 2>/dev/null)
  local cyan=$(tput setaf 6 2>/dev/null)
  local reset=$(tput sgr0 2>/dev/null)

  diff -u "$@" | awk "
    /^\-/ {
        printf(\"%s\", \"$red\");
    }
    /^\+/ {
        printf(\"%s\", \"$green\");
    }
    /^@/ {
        printf(\"%s\", \"$cyan\");
    }

    {
        print \$0 \"$reset\";
    }"

  return "${PIPESTATUS[0]}"
}

# Print all 256 colors
colors() {
  local i
  for i in {0..255}; do
    printf "\x1b[38;5;${i}mcolor %d\n" "$i"
  done
  tput sgr0
}

# print a rainbow if truecolor is available to the terminal
truecolor-rainbow() {
  local i r g b
  for ((i = 0; i < 77; i++)); do
    r=$((255 - (i * 255 / 76)))
    g=$((i * 510 / 76))
    b=$((i * 255 / 76))
    ((g > 255)) && g=$((510 - g))
    printf '\033[48;2;%d;%d;%dm ' "$r" "$g" "$b"
  done
  tput sgr0
  echo
}

# Copy stdin to the *local* (macOS) clipboard using the OSC 52 escape sequence.
# Works over plain SSH: iTerm2 intercepts the sequence and sets the Mac
# clipboard. Requires iTerm2 Settings -> General -> Selection ->
# "Applications in terminal may access clipboard".
copy() {
  local data
  data=$(base64 -w0)

  if [[ -n $TMUX ]]; then
    # wrap in a tmux passthrough so the sequence reaches the terminal
    # shellcheck disable=SC1003  # the trailing \\ is the ST terminator, not an escaped quote
    printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$data" >/dev/tty
  else
    printf '\033]52;c;%s\a' "$data" >/dev/tty
  fi
}

bind 'set enable-bracketed-paste off'




# Shell options
#shopt -s histappend
#shopt -s checkwinsize
shopt -s cdspell                    # Automatically correcy typo in cd command
shopt -s autocd 2>/dev/null || true # Automaticall cd into dir without cd command | eg. "/etc/



