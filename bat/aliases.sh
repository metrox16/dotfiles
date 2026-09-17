# Shell entries for bat. install-tools.sh keeps this file in a marked region of
# your shell startup file; an entry you already define the same way is left out,
# and one you define differently goes in commented out.

# Plain cat replacement, no pager and no decorations.
alias ccat='bat -pp'

# Render --help output with syntax highlighting: cmd --help | bh
alias bh='bat -l help'
alias b='bat -pp -l'


# Colourised man pages.
export MANPAGER="sh -c 'col -bx | bat -l man -p --theme=gruvbox-dark'"
export MANROFFOPT='-c'
