# Shell entries for fd. install-tools.sh keeps this file in a marked region of
# your shell startup file; an entry you already define the same way is left out,
# and one you define differently goes in commented out.

# Search everything: hidden files too, and what .gitignore would hide.
alias fd='fd -HI'

# By extension: fde py http
alias fde='fd -e'

