# API and release decision

The current `compression-d` API is experimental and source-visible, but not
promoted as a stable package ABI. Callers must import codec modules explicitly.
The package module intentionally does not wildcard-export them.

## Compatibility policy

- DMD and LDC are supported compiler families. The repository gates compile
  the core with both when both toolchains are available; the checked consumer
  probes enable DIP1000 and the required `@safe @nogc nothrow` contracts.
- A release candidate must pin the minimum DMD/LDC versions in CI and record
  the compiler versions in the verification report.
- Numeric enum values, struct layout and experimental function names are not
  stable until an ABI review and release decision are recorded.
- Codec operations take caller-owned slices and typed state/workspaces. No
  hidden allocation, C backend or retained input reference is permitted.

## Workspace contracts

`compression.deflate.inflateWorkspaceBytes` is the exact fixed size of one
`InflateWorkspace` on the compiling target. It is a value-type workspace and
must be owned exclusively by one active decode operation. The encoder's
`HashChainMatchFinder` is likewise value-owned; its exact fixed footprint is
available as `compression.encode.hashChainWorkspaceBytes` and includes the
hash heads, predecessor ring and 32-KiB history. These constants are compile-
time facts rather than portable ABI promises.

## Release gate

No first public release is declared by this change. Before promotion, the
project must complete the license/dependency review, pin compiler support in
CI, decide whether the PNG container work belongs in `imageio-d`, and approve
an ABI/API compatibility policy. Until then, applications should treat the
interfaces as experimental and pin a repository commit.
