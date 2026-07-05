---
id: merging-issues
swift: mergingIssues
title: Merging Issues
icon: arrow.triangle.merge
section: The App
---
# Merging Issues

Merging happens in the Merge section of an issue in review. It is a local operation; Plumage neither pushes nor opens a pull request.

## Squash by default

The default mode squashes the issue branch into a single commit on the target branch, one commit per issue. The per-task checkpoint commits stay behind on the issue branch. Fast-forward mode is available when the target branch has no commits the issue branch lacks.

## The squash subject

The commit subject is prefilled from the spec's `mergeSubject` frontmatter field (falling back to the issue title) and can be edited before merging. The bundled workflow's convention is an imperative one-liner describing the change, without issue id, slug or merge mechanics like "squash". The Merge button stays disabled while the subject is empty.

## Guards and rollback

Before merging, Plumage checks that the working tree is clean and that no implement run is active in the checkout. After a successful merge the issue's status flips to `done`. If anything fails mid-merge, Plumage rolls back and returns to the branch you were on.

## Rebase & Merge

When fast-forward is impossible because the target branch has moved on, a Rebase & Merge action appears. It rebases the issue branch onto the target. On a conflict it aborts automatically and leaves the branch unchanged for manual resolution.

## Branch cleanup

"Delete branch after merge" is on by default. After a squash, git considers the branch unmerged, so Plumage force-deletes it. This is safe because the merge just landed its content. If the branch is checked out in another worktree, a clean worktree is removed along with it; a dirty worktree keeps both and shows a warning instead.

## Merge target

The target branch is selectable per project and remembered in the `.plumage` bundle (`merge-target.json`).
