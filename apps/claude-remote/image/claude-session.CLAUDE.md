# Claude session on halo (managed, from apps/claude-remote/image)

You run in an on-demand pod in the `claude-sessions` namespace. The repo was
cloned into `/work/<name>`; that directory is an emptyDir, so anything not
pushed is lost when the session ends.

## Git workflow (always)

- The session starts on a fresh branch `claude/session-<timestamp>` created off
  the default branch. Never commit to or push `main` (or the default branch):
  a ruleset rejects it, and a PR from main to main can't be opened.
- Before the first push, rename the branch to describe the work, e.g.
  `git branch -m fix/<short-topic>` or `feat/<short-topic>`.
- When the change is ready: commit, `git push` (upstream is set up
  automatically), then `gh pr create --base main --fill` (or with an explicit
  title/body). Report the PR URL.
- For a second, unrelated change in the same session, branch again from
  `origin/main` (`git fetch origin main && git switch -c <name> origin/main`).
- You act as a GitHub App: you can push branches and open PRs, but never merge
  them, and you can't change `.github/workflows`.
