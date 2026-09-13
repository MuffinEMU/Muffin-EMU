# Post-mortems

One file per incident where a change made the emulator **worse** in a way that
took real effort to find. Not a changelog and not a blame log — the point is the
*mechanism*, so the next person recognises the shape before losing a week to it.

Write one when a regression was hard to attribute, silent, or survived a
reinstall. Skip it for ordinary bugs found and fixed in the same sitting.

## The rules these incidents produced

Each is here because breaking it actually cost us something. They are ordered by
how much.

### 1. A tag is a label, not a provenance record

Two releases were tagged at the same commit and shipped different binaries. A
GitHub release resolves its target at publish time; the IPA comes from a workflow
run that resolved its own `headSha` when the run started. Nothing forces those to
agree and nothing reports it when they do not.

Both facts were true at once: the tags really did point at one commit, and the
two IPAs really were different code. That is what made checking the tags feel
conclusive while settling nothing.

If you need to know what is in a binary, ask the build, not the tag. And when
someone's device disagrees with your repository, the device is right - the
repository says what should be true, the device says what is.

See `2026-09-12-two-tags-one-commit.md`. Listed first because it cost the most:
about a week spent on the wrong line.

### 2. An always-false condition may be load-bearing

The highest-value rule in this file, and the least intuitive.

When you find a test that can never be true — `options & SomeEnum` where the enum
is `0`, a `default:` that is unreachable, a flag nothing sets — you have not
found a dead line. You have found **a code path that has never executed in this
program's life**, sitting behind a condition that was silently protecting you
from it.

Correcting the test does not fix a bug. It *enables a feature*, all at once,
everywhere, with zero prior coverage. Treat it as one: land it alone, behind a
toggle if you can, and test it on device before anything else rides on it. Never
bundle it with unrelated work, because when the screen fills with garbage a week
later nobody will suspect the "obviously correct" one-line correction.

See `2026-09-11-write-combined-blobs.md`, which is exactly this.

### 3. Never report success for work that failed

`Compile()` returned `true` while handing back a null pipeline. Every caller
believed it. The null was cached permanently, and every draw that needed it was
skipped in silence for the rest of the session.

A function that cannot fail should return `void`. A function that can must
report it, and its callers must handle it. "Log it and return true" is not error
handling; it is a lie with a receipt.

### 4. Never silently drop work

`if (!pipelineObj->m_pipeline) return;` — a draw call vanishing with no log. The
guest asked for something, the emulator did nothing, and nothing recorded it.

If you skip requested work, say so at least once per distinct cause, and key the
one-shot on the *cause*, not the call site. `cemuLog_logOnce()` keys on the call
site, so the first caller permanently silences every other one — that has already
caused two separate diagnostic blind spots here (the TV/pad `CAMetalLayer` logs,
and the scan-buffer drop logs).

### 5. Anything written to disk must carry a version

`MTL::BinaryArchive` had none. When the pipeline hash was corrected, every
machine still held an archive built under the old, colliding hash — and kept
loading it. The fix could not take effect, and reinstalling the app did not help
because the file lives under `Documents`.

Put the version in the **filename**, so a mismatch means the file is never opened
rather than opened and mistrusted, and delete other versions on startup so a
stale file cannot lurk. Bump it whenever anything that decides *what a cache
entry means* changes.

### 6. If the same rule is implemented twice, change both or neither

The app's version string is derived in two places: a shell expression in
`build-ios-app.yml` that stamps `CFBundleShortVersionString`, and `version_of()`
in `ci/generate-sidestore-source.py` that fills the install sources. They must
agree, or the app reports one version while the feed advertises another.

Both were taught to split a flat tag (`v47` to 4.7). Later, tags started being
written dotted (`v4.8`), and only the Python side was taught the second scheme.
The shell kept matching leading digits, captured `4` out of `v4.8`, divided it by
ten, and shipped the build as **0.4**.

Nothing failed. Both expressions were individually reasonable and neither errored.
The bug lived entirely in the gap between them.

When you find logic duplicated across languages or files, either collapse it to
one implementation, or write each one's comment so it names the other. Both of
these now say the other exists and has to move with it - that is cheaper than
collapsing them across a YAML/Python boundary, and it is what would have caught
this.

### 7. Ask when the symptom started before trusting attribution

A regression reported right after a batch of changes is not evidence those
changes caused it. In the incident below, the trigger predated the suspected work
by days, and one sentence from the person seeing it — "it started the day we
did X" — was worth more than hours of reading.

Ask for the timeline first. Ask what the screen actually looks like, precisely:
"nothing renders", "everything is black", and "bright coloured blobs" have
completely different causes and it is not safe to translate between them.
