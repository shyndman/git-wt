# git-wt plugin

if [[ -n ${GIT_WT_PLUGIN_LOADED:-} ]]; then
  return
fi
typeset -g GIT_WT_PLUGIN_LOADED=1

typeset -gr GIT_WT_PLUGIN_FILE="${${(%):-%N}:A}"
typeset -gr GIT_WT_PLUGIN_DIRECTORY="${GIT_WT_PLUGIN_FILE:h}"

source "${GIT_WT_PLUGIN_DIRECTORY}/git-wt"

git() {
  if [[ ${1:-} == wt ]]; then
    shift
    _git_wt_main "$@"
    return
  fi

  command git "$@"
}

if (( ${+functions[compdef]} )); then
  compdef _git git
  compdef _git-wt git-wt
fi
