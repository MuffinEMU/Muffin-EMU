# Post-mortems

One file per incident where a change made the emulator worse in a way that
took real effort to find — not a changelog, not a blame log, just what
happened and why, so the shape is recognizable next time.

Write one when a regression was hard to attribute, silent, or survived a
reinstall. Skip it for ordinary bugs found and fixed in the same sitting.

## Files

- [`2026-09-11-write-combined-blobs.md`](2026-09-11-write-combined-blobs.md) —
  a one-line fix to an always-false condition turned on write-combined memory
  for every buffer at once, and Cemu's buffer cache can't tolerate that.
- [`2026-09-12-two-tags-one-commit.md`](2026-09-12-two-tags-one-commit.md) —
  two release tags pointed at the same commit but shipped different binaries,
  because a GitHub release doesn't record what commit its build actually came
  from.
