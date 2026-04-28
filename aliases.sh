export PATH="/opt/npm-global/bin:$PATH"
alias claude='claude --allow-dangerously-skip-permissions'
alias codex='codex --dangerously-bypass-approvals-and-sandbox'
alias copilot='copilot --yolo'
alias crush='crush --yolo'
alias droid='factory-droid'
alias gemini='gemini --yolo'
alias kimi='kimi --yolo'
alias links='/usr/bin/lnks'
alias links2='/usr/bin/lnks2'
alias lynx='/usr/bin/lyx'
#opencode runs permissively by default, so no alias needed
#vibe permissions are complicated; see /home/llm/.vibe/config.toml
alias ll='ls -lh --color=auto'
export LS_COLORS='rs=0:di=01;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:su=37;41:sg=30;43:tw=30;42:ow=31:st=37;44:ex=01;32:';
function git_branch_name() {
  branch=$(git symbolic-ref --short HEAD 2>/dev/null)
  echo "${branch:-}"
}
function prompt() {
    local BLUE_DARK="\[\033[0;34m\]"
    local BROWN="\[\033[0;33m\]"
    local CYAN_DARK="\[\033[0;36m\]"
    local GREEN_DARK="\[\033[0;32m\]"
    local PURPLE_DARK="\[\033[0;35m\]"
    local RED_DARK="\[\033[0;31m\]"
    local BLUE_LIGHT="\[\033[1;34m\]"
    local TAN="\[\033[1;33m\]"
    local CYAN_LIGHT="\[\033[1;36m\]"
    local GREEN_LIGHT="\[\033[1;32m\]"
    local PINK="\[\033[1;31m\]"
    local PURPLE_LIGHT="\[\033[1;35m\]"
    local RED_LIGHT="\[\033[0;38m\]"
    local BLACK="\[\033[0;30m\]"
    local GRAY="\[\033[1;30m\]"
    local WHITE="\[\033[1;37m\]"
    local WHITE="\[\033[1;37m\]"
    local NC="\[\033[0m\]"
    case $TERM in
        xterm*)
            TITLEBAR='\[\033]0;\u@\h:\w\007\]'
            ;;
        *)
            TITLEBAR=""
            ;;
    esac
    branch=$(git_branch_name)
    if [ -n "$branch" ]; then
        branch_str=" ($branch)"
    else
        branch_str=""
    fi
    export PS1="\n$BLUE_LIGHT\u$NC@$BROWN\H$NC:$WHITE\!$NC:$CYAN_LIGHT\#$NC:$RED_DARK[\d  \T]$CYAN_DARK $branch_str$NC\n\w\n\$ "
    export PS2='> '
    export PS4='+ '
}
prompt