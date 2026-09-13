# Everything renders as bright coloured blobs

**Found:** 2026-09-11 · **Introduced:** 2026-09-01, `1fa623ca` · **Fixed:** `muffin/v46`

## Symptom

Every surface in a running title renders as shifting bright coloured blobs —
geometry torn apart, colour random, changing frame to frame. Described on
device at the time as "truly nauseating." Survives reinstalling the app.

Don't confuse this with the earlier bug where most coloured textures in FAST
Racing Neo rendered flat black or grey — different bug, different causes, see
"Not the same bug" below.

## Mechanism

`MetalBufferAllocator.h`'s `GetResourceOptions()` had:

```cpp
if (options & MTL::ResourceStorageModeShared || options & MTL::ResourceStorageModeManaged)
    options |= MTL::ResourceCPUCacheModeWriteCombined;
```

`MTL::ResourceStorageModeShared` is `0`. Storage mode is a two-bit field at
bits 4-5 (Shared=0, Managed=16, Private=32, Memoryless=48), not a flag bit —
so `options & MTL::ResourceStorageModeShared` is `options & 0`, always false.
Managed only matched by accident of its bit pattern, and iOS doesn't even have
a Managed storage mode.

So write-combined had never actually been applied to anything. The renderer
had been running without it the whole time.

`1fa623ca` correctly spotted this as a bug and fixed it by masking the field
before comparing — that part's right. But on iOS, with unified memory,
basically every buffer is Shared, so the fix turned write-combined on for the
entire buffer path at once: vertex, uniform, index, staging. None of it had
ever run that way before.

Write-combined memory is a real contract: the CPU can write to it (ideally
whole cache lines, in order), but reads are uncached and incoherent, and
scattered writes can land out of order. Cemu doesn't honor that and can't
easily be made to — `LatteBufferCache` mirrors guest memory and does
read-modify-write against it, and the staging allocators write scattered
sub-ranges. Under write-combined those become partially-visible, out-of-order
writes that the GPU then reads. Corrupt vertex data tears geometry; corrupt
texture data samples as random bright colour. Both together is the blobs.

Worth noting: `LatteTextureMtl.cpp:17` still has
`//desc->setCpuCacheMode(MTL::CPUCacheModeWriteCombined);` commented out —
someone already knew this was unsafe for textures and just never generalized
it.

## Fix

Stop setting `CPUCacheModeWriteCombined`. Kept `GetStorageMode()` — the
field-masking part of `1fa623ca` was genuinely correct, and `RequiresFlush()`
needs it to avoid calling `didModifyRange()` on a Memoryless buffer. Only the
write-combined half got reverted, with a comment at the call site explaining
why it has to stay off.

Turning it back on properly is its own project, not a one-line change — it
means auditing every writer into these buffers for write-combined safety.

## Why it took so long to find

- Attribution went to the wrong changes first. The regression showed up right
  after an unrelated batch of work, so that got investigated for hours before
  anyone looked further back. The actual trigger was days older.
- The symptom description kept changing: "nothing renders," "everything is
  black," "bright coloured blobs" — all used for the same bug at different
  points, and the first two point at completely different mechanisms. "Blobs"
  is the one that actually led somewhere.
- The commit looked totally safe. A one-line fix to a provably always-false
  condition, with a comment explaining exactly why. Nothing about it reads as
  risky — which is sort of the trap: correcting a dead condition can turn a
  code path live for the first time ever.

## Not the same bug

The original black/grey texture problem is separate, with its own confirmed
causes, fixed on `muffin/texture-decoder-fixes`: `TextureDecoder_R24_X8` and
`X24_G8_UINT` fetched their input and unconditionally wrote zero;
`D24_S8_FLOAT` was wired to a decoder that memsets to zero; two formats had no
decoder at all and just stayed at their cleared value; `R10_G10_B10_A2_SNORM`
wrote one pixel per row and left the rest as whatever the recycled upload
buffer last held.

Keep them apart when testing — black/grey is a decode problem, blobs is a
memory coherency problem.
