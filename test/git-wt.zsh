#!/usr/bin/env zsh

emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

readonly PROJECT_ROOT=${0:A:h:h}
readonly INIT_FAILURE_STATUS=7
local temporary_directory

temporary_directory=$(mktemp --directory)
trap 'rm --recursive --force -- "$temporary_directory"' EXIT

readonly REPOSITORY="${temporary_directory}/repository"
export HOME="${temporary_directory}/home"
readonly WORKTREES="${HOME}/.local/share/git-wt/${${REPOSITORY#/}//\//--}"
mkdir --parents -- "$HOME"
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
[[ ! -e "${REPOSITORY}/.gitignore" ]] || fail '--init created an ignore file'
assert_file "${REPOSITORY}/.wtinit"
print -rn -- 'user ignore content' > "${REPOSITORY}/.gitignore"

cat > "${REPOSITORY}/.wtinit" <<'EOF'
#!/usr/bin/env zsh
print -r -- "$PWD" > "${HOME}/init-cwd"
EOF
readonly CUSTOM_INIT_CONTENT=$(<"${REPOSITORY}/.wtinit")

(
  cd -- "$REPOSITORY"
  git wt --init
  git wt alpha 2>/dev/null
  [[ $PWD == "${WORKTREES}/alpha" ]] || fail 'create did not change to the worktree'
)
[[ "$(<"${REPOSITORY}/.gitignore")" == 'user ignore content' ]] || fail '--init changed the user ignore file'
[[ "$(<"${REPOSITORY}/.wtinit")" == "$CUSTOM_INIT_CONTENT" ]] || fail '--init replaced an existing .wtinit'
[[ "$(<"${HOME}/init-cwd")" == "${WORKTREES}/alpha" ]] || fail '.wtinit used the wrong current directory'
assert_directory "${WORKTREES}/alpha"

(
  cd -- "$REPOSITORY"
  git wt alpha > "${temporary_directory}/switch-output" 2> "${temporary_directory}/switch-error"
  [[ $PWD == "${WORKTREES}/alpha" ]] || fail 'switch did not change to the worktree'
)
assert_empty_file "${temporary_directory}/switch-output"
assert_empty_file "${temporary_directory}/switch-error"

git -C "$REPOSITORY" branch existing
(
  cd -- "$REPOSITORY"
  git wt existing 2>/dev/null
  [[ $PWD == "${WORKTREES}/existing" ]] || fail 'existing branch create did not change directory'
)
[[ "$(git -C "${WORKTREES}/existing" branch --show-current)" == existing ]] || fail 'create did not use the existing branch'

(
  cd -- "${WORKTREES}/alpha"
  git wt beta 2>/dev/null
  [[ $PWD == "${WORKTREES}/beta" ]] || fail 'linked create did not change directory'
)
assert_directory "${WORKTREES}/beta"
[[ "$(git -C "${WORKTREES}/beta" branch --show-current)" == beta ]] || fail 'linked create created the wrong branch'
[[ "$(<"${HOME}/init-cwd")" == "${WORKTREES}/beta" ]] || fail 'linked create did not run the main repository init script'
[[ ! -d "${REPOSITORY}/.worktrees" ]] || fail 'new worktrees created the legacy directory'

git -C "$REPOSITORY" worktree add --quiet "${REPOSITORY}/.worktrees/legacy"
mkdir --parents -- "${REPOSITORY}/.worktrees/unregistered"
(
  cd -- "${WORKTREES}/beta"
  git wt legacy
  [[ $PWD == "${REPOSITORY}/.worktrees/legacy" ]] || fail 'legacy open did not use the registered worktree'
  git wt from-legacy 2>/dev/null
  [[ $PWD == "${WORKTREES}/from-legacy" ]] || fail 'legacy linked create did not use the external location'
)

_describe() {
  print -rl -- "${worktrees[@]}"
}
local completion_names
completion_names=$(
  cd -- "${WORKTREES}/beta"
  _git_wt_managed_worktrees
)
unfunction _describe
local -a completion_worktrees=("${(f)completion_names}")
[[ ${completion_worktrees[(r)alpha]} == alpha ]] || fail 'completions omitted alpha'
[[ ${completion_worktrees[(r)beta]} == beta ]] || fail 'completions omitted beta'
[[ ${completion_worktrees[(r)existing]} == existing ]] || fail 'completions omitted existing'
[[ ${completion_worktrees[(r)legacy]} == legacy ]] || fail 'completions omitted legacy'
[[ ${completion_worktrees[(r)from-legacy]} == from-legacy ]] || fail 'completions omitted external creation from legacy'
[[ ${completion_worktrees[(Ie)unregistered]} == 0 ]] || fail 'completions included an unregistered directory'

local completions_file="${temporary_directory}/_git-wt"
(
  cd -- "$REPOSITORY"
  git wt --completions
) > "$completions_file"
local emitted_names
emitted_names=$(zsh -f -c '
  source "$1"
  _describe() { print -rl -- "${worktrees[@]}"; }
  cd -- "$2"
  _git_wt_managed_worktrees
' zsh "$completions_file" "${WORKTREES}/beta")
[[ $emitted_names == "$completion_names" ]] || fail 'emitted completions did not enumerate the same worktrees'

(
  cd -- "${REPOSITORY}/.worktrees/legacy"
  git wt --rm legacy
  [[ $PWD == "$REPOSITORY" ]] || fail 'legacy removal did not return to the main repository'
)
[[ ! -e "${REPOSITORY}/.worktrees/legacy" ]] || fail 'legacy removal left the directory'
assert_directory "${REPOSITORY}/.worktrees/unregistered"

print -r -- 'dirty' >> "${WORKTREES}/alpha/seed.txt"
local remove_status
if (
  cd -- "${WORKTREES}/alpha"
  remove_status=0
  git wt --rm alpha 2> "${temporary_directory}/remove-error" || remove_status=$?
  (( remove_status != 0 )) || fail '--rm removed a dirty worktree without --force'
  [[ $PWD == "${WORKTREES}/alpha" ]] || fail 'failed removal did not restore the current directory'
  return "$remove_status"
); then
  fail '--rm removed a dirty worktree without --force'
else
  remove_status=$?
fi
assert_status 1 "$remove_status"
[[ "$(<"${temporary_directory}/remove-error")" == *'Git could not remove worktree alpha'* ]] || fail '--rm did not log its failure'

(
  cd -- "${WORKTREES}/alpha"
  git wt --rm --force alpha
  [[ $PWD == "$REPOSITORY" ]] || fail 'removal from the worktree did not change to the repository root'
)
[[ ! -e "${WORKTREES}/alpha" ]] || fail 'forced --rm left the worktree directory'
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
assert_directory "${WORKTREES}/failed-init"
[[ "$(<"${temporary_directory}/create-error")" == *'.wtinit failed for worktree failed-init'* ]] || fail 'create did not log the init failure'

(
  cd -- "$REPOSITORY"
  git wt --rm beta
  git wt --rm existing
  git wt --rm from-legacy
  git wt --rm --force failed-init
)


print -r -- 'All integration checks passed.'
