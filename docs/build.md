# Building and validating the current bounded implementation

The current scope is the portable `ibms::BeatPosition` type, the
`ibms::BmsDocument` byte-metadata core, and the bounded native macOS document
session. The native surface currently covers New, Open, Save, Save As, the five
metadata fields, undo/redo, encoding selection, and the attached Open/Save and
discard sheets. Full chart-format compatibility, note editing, playback,
BMSON, integrations, and pixel/performance acceptance remain outside this
scope.

The project requires CMake 3.26 or newer and a C++ compiler with `__int128`
support. Apple Clang and GCC are supported. Microsoft Visual C++ requires a
future wide-integer backend and is rejected during configuration with a clear
diagnostic.

From the repository root, configure and build the application configurations:

```sh
cmake --preset debug
cmake --build --preset debug
ctest --preset debug

cmake --preset release
cmake --build --preset release
ctest --preset release
```

The resulting native application bundles are:

```text
out/build/debug/macos/IBMSNative.app
out/build/release/macos/IBMSNative.app
```

For core-only builds, use `core-debug` or `core-release`; these presets set
`IBMS_BUILD_MACOS_APP=OFF` and write under `out/build/core-debug` or
`out/build/core-release`.

The bounded behavior and evidence record is in
`docs/validation/bms-metadata-batch.md`. The current evidence includes Release
CTest 4/4, an independent final Debug 4/4, independent
core ASan/UBSan 2/2, and strict release warning checks 2/2. The native link
still prints a duplicate `-lc++` warning; it has not blocked these results.
