# API and release decision

The package ABI remains experimental and source-visible, but the GZIP streaming
consumer surface is promoted as a stable source/API contract from v0.3.0.
Callers must import codec modules explicitly.
The package module intentionally does not wildcard-export them.

## Compatibility policy

- DMD and LDC are supported compiler families. The repository gates compile
  the core with both when both toolchains are available; the checked consumer
  probes enable DIP1000 and the required `@safe @nogc nothrow` contracts.
- A release candidate must pin the minimum DMD/LDC versions in CI and record
  the compiler versions in the verification report.
- Numeric enum values, struct layout and experimental function names are not
  stable. For the admitted GZIP surface, source-level names and semantics are
  protected by the compatibility policy below; private state layout is not an
  ABI promise.
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

The first admitted consumer surface is the GZIP streaming decoder documented in
`docs/GZIP_STREAMING.md`. Its state/result semantics, ownership rules, error
categories and limit behavior are covered by the framing gate under DMD and
LDC. Other modules remain experimental and applications should not infer
stability for them.
