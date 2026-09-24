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

_git_wt_complete_git() {
  if [[ ${words[2]-} != wt ]]; then
    _git "$@"
    return
  fi

  local -a words=("${words[@]}")
  local -i CURRENT=$CURRENT
  shift words
  (( CURRENT-- ))
  _git-wt "$@"
}

if (( ${+functions[compdef]} )); then
  compdef _git_wt_complete_git git g
  compdef _git-wt git-wt
fi
