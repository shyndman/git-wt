#!/usr/bin/env zsh

emulate -LR zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

readonly PROJECT_ROOT=${0:A:h:h}
readonly INIT_FAILURE_STATUS=7
local temporary_directory

temporary_directory=$(mktemp --directory)
trap 'rm --recursive --force -- "$temporary_directory"' EXIT

readonly REPOSITORY="${temporary_directory}/repository"
export PATH="${PROJECT_ROOT}:${PATH}"

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

mkdir --parents -- "$REPOSITORY"
git -C "$REPOSITORY" init --quiet
git -C "$REPOSITORY" config user.email 'git-wt-test@example.com'
git -C "$REPOSITORY" config user.name 'git wt test'
print -r -- 'seed' > "${REPOSITORY}/seed.txt"
git -C "$REPOSITORY" add seed.txt
git -C "$REPOSITORY" commit --quiet --message 'seed'

(
  cd -- "$REPOSITORY"
  git wt init
)
assert_file "${REPOSITORY}/.gitignore"
assert_file "${REPOSITORY}/.wtinit"
[[ "$(<"${REPOSITORY}/.gitignore")" == '/.worktrees/' ]] || fail 'init wrote the wrong ignore entry'

cat > "${REPOSITORY}/.wtinit" <<'EOF'
#!/usr/bin/env zsh
print -r -- "$PWD" > "${PWD:h:h}/init-cwd"
EOF
readonly CUSTOM_INIT_CONTENT=$(<"${REPOSITORY}/.wtinit")

(
  cd -- "$REPOSITORY"
  git wt init
  git wt add alpha
)
[[ "$(<"${REPOSITORY}/.wtinit")" == "$CUSTOM_INIT_CONTENT" ]] || fail 'init replaced an existing .wtinit'
[[ "$(<"${REPOSITORY}/init-cwd")" == "${REPOSITORY}/.worktrees/alpha" ]] || fail '.wtinit used the wrong current directory'
assert_directory "${REPOSITORY}/.worktrees/alpha"

git -C "$REPOSITORY" branch existing
(
  cd -- "$REPOSITORY"
  git wt add existing
)
[[ "$(git -C "${REPOSITORY}/.worktrees/existing" branch --show-current)" == existing ]] || fail 'add did not use the existing branch'

(
  cd -- "${REPOSITORY}/.worktrees/alpha"
  git wt add beta
)
assert_directory "${REPOSITORY}/.worktrees/beta"
[[ "$(git -C "${REPOSITORY}/.worktrees/beta" branch --show-current)" == beta ]] || fail 'linked add created the wrong branch'

print -r -- 'dirty' >> "${REPOSITORY}/.worktrees/alpha/seed.txt"
local remove_status
if (
  cd -- "$REPOSITORY"
  git wt rm alpha
) 2> "${temporary_directory}/remove-error"; then
  fail 'rm removed a dirty worktree without --force'
else
  remove_status=$?
fi
assert_status 1 "$remove_status"
[[ "$(<"${temporary_directory}/remove-error")" == *'Git could not remove worktree alpha'* ]] || fail 'rm did not log its failure'

(
  cd -- "$REPOSITORY"
  git wt rm --force alpha
)
[[ ! -e "${REPOSITORY}/.worktrees/alpha" ]] || fail 'forced rm left the worktree directory'
git -C "$REPOSITORY" show-ref --verify --quiet refs/heads/alpha || fail 'rm deleted the worktree branch'

cat > "${REPOSITORY}/.wtinit" <<EOF
#!/usr/bin/env zsh
exit ${INIT_FAILURE_STATUS}
EOF
local add_status
if (
  cd -- "$REPOSITORY"
  git wt add failed-init
) 2> "${temporary_directory}/add-error"; then
  fail 'add succeeded after .wtinit failed'
else
  add_status=$?
fi
assert_status "$INIT_FAILURE_STATUS" "$add_status"
assert_directory "${REPOSITORY}/.worktrees/failed-init"
[[ "$(<"${temporary_directory}/add-error")" == *'.wtinit failed for worktree failed-init'* ]] || fail 'add did not log the init failure'

(
  cd -- "$REPOSITORY"
  git wt rm beta
  git wt rm existing
  git wt rm --force failed-init
)

local completions_file="${temporary_directory}/_git-wt"
(
  cd -- "$REPOSITORY"
  git wt completions
) > "$completions_file"
zsh -n "$completions_file"
[[ "$(<"$completions_file")" == *'_git_wt_managed_worktrees'* ]] || fail 'completions omitted managed worktrees'

mkdir --parents -- "${temporary_directory}/home"
HOME="${temporary_directory}/home" "${PROJECT_ROOT}/install.zsh" >/dev/null
[[ -x "${temporary_directory}/home/.local/bin/git-wt" ]] || fail 'installer did not create an executable'

print -r -- 'All integration checks passed.'
