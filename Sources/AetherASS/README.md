# Optional ASS overlay

The playback core exposes raw ASS events, script headers and MKV font payloads;
its built-in text path does not paint full ASS. `AetherASS` adds a surface-neutral
libass renderer. Only consumers of that product link the font/shaping stack.

Confine `ASSRenderer` to a serial queue. Supply explicit memory/script/cache
limits, call `replaceFonts` with embedded or downloaded font bytes, then `load`
a full ASS/SSA script (`ASSScriptBuilder` can assemble engine cues). Paint copied
`Frame.image` only when `changed`, using `engine.sourceTime` and the video rect.
`replaceFonts` rebuilds the font selector and caches before subsequent rendering,
so external delivery and eviction require no global CoreText registration. Hosts
own font fetching, fallback coverage, caching, cancellation and scheduling.

The source remains under the repository LGPL. `swift-libass` 1.4.0 is an MIT
wrapper with Apple simulator/device slices; it contains libass 0.17.3 (ISC),
FreeType, HarfBuzz, FriBidi, Fontconfig and libpng under their respective licences.
See its pinned source/build recipes and the upstream projects for notices and
relinking obligations. No GPL FFmpeg filters or network client are introduced.
