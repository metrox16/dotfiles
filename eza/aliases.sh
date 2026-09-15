# Shell entries for eza. install-tools.sh keeps this file in a marked region of
# your shell startup file; an entry you already define the same way is left out,
# and one you define differently goes in commented out.

# Long listing of everything, grouped, sorted by name.
alias l='eza -laahg --icons=auto -s.name'

# Same but sorted by modification time.
alias ltr='eza -lah --icons=auto -stime'
