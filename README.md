# git-wt

A small Zsh plugin for Git worktrees.

Load `git-wt.plugin.zsh` with a Zsh plugin manager, or source it directly.

```zsh
source /path/to/git-wt/git-wt.plugin.zsh

git wt --init
git wt NAME
git wt --rm NAME
git wt --completions
```

`git wt NAME` creates a missing worktree, then changes to it. New worktrees live at
`~/.local/share/git-wt/ENCODED-REPOSITORY/NAME`. The repository is the main
repository's absolute path (the parent of Git's absolute common directory), even
when the command runs inside a linked worktree. Encoding strips the leading `/`
and replaces each remaining `/` with `--`: `/home/a/repo` becomes
`home--a--repo`. There is no collision handling.

This location applies only to new worktrees. Existing registered worktrees in
the main repository's `.worktrees/` directory stay where they are: they can
still be opened, removed with `git wt --rm NAME`, and completed. When a name
exists in both locations, the external worktree takes precedence. Unregistered
directories are not treated as existing worktrees.

`git wt --init` creates `.wtinit` in the main repository if it is missing and
leaves existing `.wtinit` and `.gitignore` files unchanged. It does not add a
`.gitignore` entry. New worktrees run the main repository's `.wtinit` with the
new worktree as their current directory. Opening an existing worktree does not
run the script.
