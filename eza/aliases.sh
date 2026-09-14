# Shell entries for eza. install-tools.sh copies the entries that are not
# already defined into your shell startup file; it never overwrites an alias
# you already have.

# Long listing of everything, grouped, sorted by name.
alias l='eza -laahg --icons=auto -s.name'

# Same but sorted by modification time.
alias ltr='eza -lah --icons=auto -stime'
