#!/usr/bin/env zsh

emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

readonly PROJECT_ROOT=${0:A:h:h}
readonly INIT_FAILURE_STATUS=7
local temporary_directory

temporary_directory=$(mktemp --directory)
trap 'rm --recursive --force -- "$temporary_directory"' EXIT

readonly REPOSITORY="${temporary_directory}/repository"
source "${PROJECT_ROOT}/git-wt.plugin.zsh"
source "${PROJECT_ROOT}/git-wt.plugin.zsh"

fail() {
  print -ru2 -- "test failure: $1"
  return 1
}

assert_file() {
  [[ -f $1 ]] || fail "expected file $1"
}

assert_directory() {
  [[ -d $1 ]] || fail "expected directory $1"
}

assert_status() {
  local -r expected=$1
  local -r actual=$2
  (( actual == expected )) || fail "expected status ${expected}, got ${actual}"
}

assert_empty_file() {
  [[ ! -s $1 ]] || fail "expected empty file $1"
}

mkdir --parents -- "$REPOSITORY"
git -C "$REPOSITORY" init --quiet
git -C "$REPOSITORY" config user.email 'git-wt-test@example.com'
git -C "$REPOSITORY" config user.name 'git wt test'
print -r -- 'seed' > "${REPOSITORY}/seed.txt"
git -C "$REPOSITORY" add seed.txt
git -C "$REPOSITORY" commit --quiet --message 'seed'

(
  cd -- "$REPOSITORY"
  git wt --init
)
assert_file "${REPOSITORY}/.gitignore"
assert_file "${REPOSITORY}/.wtinit"
[[ "$(<"${REPOSITORY}/.gitignore")" == '/.worktrees/' ]] || fail '--init wrote the wrong ignore entry'

cat > "${REPOSITORY}/.wtinit" <<'EOF'
#!/usr/bin/env zsh
print -r -- "$PWD" > "${PWD:h:h}/init-cwd"
EOF
readonly CUSTOM_INIT_CONTENT=$(<"${REPOSITORY}/.wtinit")

(
  cd -- "$REPOSITORY"
  git wt --init
  git wt alpha 2> "${temporary_directory}/create-status"
  [[ $PWD == "${REPOSITORY}/.worktrees/alpha" ]] || fail 'create did not change to the worktree'
)
[[ "$(<"${temporary_directory}/create-status")" == 'creating worktree…' ]] || fail 'create printed the wrong status'
[[ "$(<"${REPOSITORY}/.wtinit")" == "$CUSTOM_INIT_CONTENT" ]] || fail '--init replaced an existing .wtinit'
[[ "$(<"${REPOSITORY}/init-cwd")" == "${REPOSITORY}/.worktrees/alpha" ]] || fail '.wtinit used the wrong current directory'
assert_directory "${REPOSITORY}/.worktrees/alpha"

(
  cd -- "$REPOSITORY"
  git wt alpha > "${temporary_directory}/switch-output" 2> "${temporary_directory}/switch-error"
  [[ $PWD == "${REPOSITORY}/.worktrees/alpha" ]] || fail 'switch did not change to the worktree'
)
assert_empty_file "${temporary_directory}/switch-output"
assert_empty_file "${temporary_directory}/switch-error"

git -C "$REPOSITORY" branch existing
(
  cd -- "$REPOSITORY"
  git wt existing 2>/dev/null
  [[ $PWD == "${REPOSITORY}/.worktrees/existing" ]] || fail 'existing branch create did not change directory'
)
[[ "$(git -C "${REPOSITORY}/.worktrees/existing" branch --show-current)" == existing ]] || fail 'create did not use the existing branch'

(
  cd -- "${REPOSITORY}/.worktrees/alpha"
  git wt beta 2>/dev/null
  [[ $PWD == "${REPOSITORY}/.worktrees/beta" ]] || fail 'linked create did not change directory'
)
assert_directory "${REPOSITORY}/.worktrees/beta"
[[ "$(git -C "${REPOSITORY}/.worktrees/beta" branch --show-current)" == beta ]] || fail 'linked create created the wrong branch'

_describe() {
  print -rl -- "${worktrees[@]}"
}
local completion_names
completion_names=$(
  cd -- "$REPOSITORY"
  _git_wt_managed_worktrees
)
unfunction _describe
local -a completion_worktrees=("${(f)completion_names}")
[[ ${completion_worktrees[(r)alpha]} == alpha ]] || fail 'completions omitted alpha'
[[ ${completion_worktrees[(r)beta]} == beta ]] || fail 'completions omitted beta'
[[ ${completion_worktrees[(r)existing]} == existing ]] || fail 'completions omitted existing'

print -r -- 'dirty' >> "${REPOSITORY}/.worktrees/alpha/seed.txt"
local remove_status
if (
  cd -- "${REPOSITORY}/.worktrees/alpha"
  remove_status=0
  git wt --rm alpha 2> "${temporary_directory}/remove-error" || remove_status=$?
  (( remove_status != 0 )) || fail '--rm removed a dirty worktree without --force'
  [[ $PWD == "${REPOSITORY}/.worktrees/alpha" ]] || fail 'failed removal did not restore the current directory'
  return "$remove_status"
); then
  fail '--rm removed a dirty worktree without --force'
else
  remove_status=$?
fi
assert_status 1 "$remove_status"
[[ "$(<"${temporary_directory}/remove-error")" == *'Git could not remove worktree alpha'* ]] || fail '--rm did not log its failure'

(
  cd -- "${REPOSITORY}/.worktrees/alpha"
  git wt --rm --force alpha
  [[ $PWD == "$REPOSITORY" ]] || fail 'removal from the worktree did not change to the repository root'
)
[[ ! -e "${REPOSITORY}/.worktrees/alpha" ]] || fail 'forced --rm left the worktree directory'
git -C "$REPOSITORY" show-ref --verify --quiet refs/heads/alpha || fail '--rm deleted the worktree branch'

cat > "${REPOSITORY}/.wtinit" <<EOF
#!/usr/bin/env zsh
exit ${INIT_FAILURE_STATUS}
EOF
local create_status
if (
  cd -- "$REPOSITORY"
  git wt failed-init
) 2> "${temporary_directory}/create-error"; then
  fail 'create succeeded after .wtinit failed'
else
  create_status=$?
fi
assert_status "$INIT_FAILURE_STATUS" "$create_status"
assert_directory "${REPOSITORY}/.worktrees/failed-init"
[[ "$(<"${temporary_directory}/create-error")" == *'creating worktree…'* ]] || fail 'failed create omitted its status'
[[ "$(<"${temporary_directory}/create-error")" == *'.wtinit failed for worktree failed-init'* ]] || fail 'create did not log the init failure'

(
  cd -- "$REPOSITORY"
  git wt --rm beta
  git wt --rm existing
  git wt --rm --force failed-init
)

local completions_file="${temporary_directory}/_git-wt"
(
  cd -- "$REPOSITORY"
  git wt --completions
) > "$completions_file"
zsh -n "$completions_file"
[[ "$(<"$completions_file")" == *'_git_wt_managed_worktrees'* ]] || fail 'completions omitted managed worktrees'
[[ "$(<"$completions_file")" == *'--rm[remove a managed worktree]'* ]] || fail 'completions omitted --rm'

print -r -- 'All integration checks passed.'
