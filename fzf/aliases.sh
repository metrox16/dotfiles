# Shell entries for fzf. install-tools.sh keeps this file in a marked region of
# your shell startup file; an entry you already define the same way is left out,
# and one you define differently goes in commented out.

# A window that does not take over the terminal, and the newest match on top.
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'

# Let fd walk the tree when it is there: it is quicker and skips .git and what
# .gitignore hides, which is almost always what you want in a picker.
if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
fi

# Preview the file under the cursor with bat when it is there.
if command -v bat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range :200 {}'"
fi

#* If you want to use fzf Bash history, comment out this line
# eval "$(fzf --bash)"

# Pick a file and open it: fe, or fe partial-name to start narrowed down.
fe() {
    local file
    file=$(fzf --query="${1:-}") || return 1
    [[ -n $file ]] || return 1
    "${EDITOR:-vi}" -- "$file"
}
