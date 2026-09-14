# Shell entries for bat. install-tools.sh copies the entries that are not
# already defined into your shell startup file; it never overwrites an alias
# you already have.

# Plain cat replacement, no pager and no decorations.
alias ccat='bat -pp'

# Render --help output with syntax highlighting: cmd --help | bh
alias bh='bat -l help'

# Colourised man pages.
export MANPAGER="sh -c 'col -bx | bat -l man -p --theme=gruvbox-dark'"
