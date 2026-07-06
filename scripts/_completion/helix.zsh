#compdef helix helix-backup helix-calendar helix-contacts helix-cookbook helix-docs helix-gallery helix-mail helix-mcp helix-memory helix-notes helix-personal helix-preset helix-research helix-sessions helix-signature helix-skills helix-tasks helix-theme helix-webhook
# Zsh tab-completion for the helix umbrella + sub-CLIs.
#
# Drop in any directory on $fpath, e.g.:
#     fpath=(/path/to/helix-ui/scripts/_completion $fpath)
#     autoload -U compinit; compinit
#
# Then `helix <tab>` completes subcommands; `helix mail <tab>`
# completes mail subcommands; `helix-mail <tab>` works the same.

_helix_scripts_dir() {
    local self="${(%):-%x}"
    while [[ -L "$self" ]]; do self="$(readlink "$self")"; done
    cd "${self:h}/.." && pwd
}

typeset -gA _helix_subs

_helix_refresh() {
    _helix_subs=()
    local dir="$(_helix_scripts_dir)"
    local py="$dir/../venv/bin/python"
    [[ -x "$py" ]] || py="$(command -v python3)"
    local f sub help_out commands
    for f in "$dir"/helix-*; do
        [[ -x "$f" ]] || continue
        case "$f" in
            *.bak|*.pyc|*.pre-*) continue ;;
        esac
        sub="${${f:t}#helix-}"
        help_out=$("$py" "$f" --help 2>/dev/null) || continue
        commands=$(echo "$help_out" | grep -oE '\{[a-z0-9_,-]+\}' | head -1 \
            | tr -d '{}' | tr ',' ' ')
        _helix_subs[$sub]="$commands"
    done
}

_helix() {
    [[ ${#_helix_subs} -eq 0 ]] && _helix_refresh

    local cmd="${words[1]}"

    if [[ "$cmd" == "helix" ]]; then
        if (( CURRENT == 2 )); then
            local -a subs=(${(k)_helix_subs} help)
            _describe 'subcommand' subs
            return
        fi
        local sub="${words[2]}"
        if [[ "$sub" == "help" ]] && (( CURRENT == 3 )); then
            local -a subs=(${(k)_helix_subs})
            _describe 'subcommand' subs
            return
        fi
        if (( CURRENT == 3 )); then
            local -a sc=(${(s/ /)_helix_subs[$sub]})
            _describe 'command' sc
            return
        fi
        return
    fi

    # helix-foo <tab>
    local sub="${cmd#helix-}"
    if (( CURRENT == 2 )); then
        local -a sc=(${(s/ /)_helix_subs[$sub]})
        _describe 'command' sc
        return
    fi
}

_helix "$@"
