# Everything renders as bright coloured blobs

**Found:** 2026-09-11 · **Introduced:** 2026-09-01, `1fa623ca` · **Fixed:** `muffin/v46`

## Symptom

Every surface in a running title renders as shifting bright coloured blobs.
Geometry is torn apart, colour is random, and it changes frame to frame. Described
on device as "truly nauseating". It survives reinstalling the app.

The preceding symptom, which the change was **not** trying to fix, was different
and should not be confused with it: most coloured textures in FAST Racing Neo
rendered as flat black or grey. That one has its own separate causes — see
"Not the same bug" below.

## Mechanism

`MetalBufferAllocator.h`'s `GetResourceOptions()` contained:

```cpp
if (options & MTL::ResourceStorageModeShared || options & MTL::ResourceStorageModeManaged)
    options |= MTL::ResourceCPUCacheModeWriteCombined;
```

`MTL::ResourceStorageModeShared` is **0**. Storage mode is a two-bit *field* at
bits 4-5 (Shared=0, Managed=16, Private=32, Memoryless=48), not a flag bit. So
`options & MTL::ResourceStorageModeShared` is `options & 0` — false for every
buffer that has ever existed. Managed matched only by accident of its bit pattern,
and iOS has no Managed storage mode at all.

Net effect: **`CPUCacheModeWriteCombined` was never applied to anything**, and the
entire renderer had only ever run that way.

`1fa623ca` correctly identified this as a bug and corrected it to mask the field
before comparing. That is right about the bug. But on iOS unified memory
essentially every buffer is Shared, so the correction switched write-combined on
for the **whole buffer path simultaneously** — vertex, uniform, index, staging —
none of which had ever run under it.

Write-combined is a contract, not a performance hint. The CPU may only write,
ideally whole cache lines in ascending order; reads are uncached and incoherent,
and scattered writes coalesce out of order. Cemu does not honour that contract and
structurally cannot: `LatteBufferCache` mirrors guest memory and performs
read-modify-write against it, and the staging allocators write scattered
sub-ranges. Those became partially-visible, out-of-order writes that the GPU then
consumed — corrupt vertex data tears geometry, corrupt texture data samples as
random bright colour. Both at once is the blobs.

Corroboration that this was already known for textures and never generalised:
`LatteTextureMtl.cpp:17` still carries `//desc->setCpuCacheMode(MTL::CPUCacheModeWriteCombined);`,
commented out.

## Fix

Stop applying `CPUCacheModeWriteCombined`. `GetStorageMode()` is kept — the
field-masking half of `1fa623ca` is genuinely correct and `RequiresFlush()` needs
it to avoid calling `didModifyRange()` on a Memoryless buffer. Only the
write-combined half is reverted, with a comment at the site explaining why it must
stay off.

Re-enabling it is a real project, not a one-line change: it requires auditing
every writer into these buffers for write-combined safety.

## Why it took so long to find

- **Attribution went to the wrong changes.** It was reported immediately after an
  unrelated batch of work, and that batch got investigated first. The trigger was
  days older.
- **The symptom description drifted.** "Nothing renders", "everything is black"
  and "bright coloured blobs" were all used for it at different points. Each
  implies a completely different mechanism, and two of them sent the search the
  wrong way entirely. The blobs description is what identified it.
- **The commit looked unimpeachable.** A one-line correction to a provably
  always-false condition, with an accurate and well-argued comment. Nothing about
  it reads as risky, which is exactly the problem — see rule 1 in the README.

## Not the same bug

The original black/grey textures are separate and have their own confirmed
causes, fixed on `muffin/texture-decoder-fixes`: `TextureDecoder_R24_X8` and
`X24_G8_UINT` fetched their input and unconditionally wrote zero; `D24_S8_FLOAT`
was wired to a decoder that memsets to zero; two formats had no decoder at all and
silently stayed at their cleared value; and `R10_G10_B10_A2_SNORM` wrote one pixel
per row, leaving the rest as whatever the recycled upload buffer last held.

Keep them apart when testing. Black/grey is a decode problem. Blobs are a memory
coherency problem.
