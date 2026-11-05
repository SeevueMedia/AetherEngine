# Optional ASS overlay

The playback core exposes raw ASS events, script headers and MKV font payloads;
its built-in text path does not paint full ASS. `AetherASS` adds a surface-neutral
libass renderer. Only consumers of that product link the font/shaping stack.

Confine `ASSRenderer` to a serial queue. Supply explicit memory/script/cache
limits, call `replaceFonts` with embedded or downloaded font bytes, then `load`
a full ASS/SSA script (`ASSScriptBuilder` can assemble engine cues). Paint copied
`Frame.image` only when `changed`, using `engine.sourceTime` and the video rect.
Pass `forceRedraw: true` after clearing the destination (such as a seek within
one static cue). `replaceFonts` rebuilds the font selector and caches before subsequent rendering,
so external delivery and eviction require no global CoreText registration. Hosts
own font fetching, fallback coverage, caching, cancellation and scheduling.

The source remains under the repository LGPL. `mpvkit/libass-build` is pinned to
its 0.17.5 commit, with checksum-verified Apple XCFrameworks. That release includes
libass's CVE-2026-61626 and CVE-2026-61627 fixes. It provides libass (ISC), FreeType,
HarfBuzz, FriBidi and libunibreak under their respective licences. Source and build
recipes are public in the pinned package; consumers retain the corresponding
notices and relinking obligations. No FFmpeg filters or network client are added.

Run the renderer tests on an owned simulator with `xcodebuild test -scheme
AetherASSTests -destination "platform=iOS Simulator,id=<UDID>"`.
