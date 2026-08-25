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

`git wt NAME` creates a missing worktree, then changes to it. Worktrees live in `.worktrees/`. New worktrees run `.wtinit`.
