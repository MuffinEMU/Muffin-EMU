# Local syntax-check stubs

Fake minimal `boost/` and `fmt/` headers, used ONLY by `ci/syntax-check.sh`.

They exist because this repo's real dependencies come from vcpkg, which CI builds and a
laptop generally does not have. Without them the only way to learn that a CPU-core edit
does not compile is a ~25 minute CI round-trip, which is far too slow a feedback loop to
edit a recompiler against.

These are NOT on the include path of any real build. They are deliberately not on the
CMake path, not in project.yml, and not referenced by the CI workflow. A passing
syntax-check means "this file still parses and type-checks against the rest of the tree";
it does NOT mean the build is green, because these stubs do not implement boost or fmt
semantics - only enough signature for the call sites the CPU core actually uses.
CI remains the authority.
