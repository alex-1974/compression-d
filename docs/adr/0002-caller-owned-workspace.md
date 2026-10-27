# ADR 0002 — Caller-owned workspace

## Decision

Decode APIs receive caller-owned output and temporary workspace. They do not
retain slices after returning and do not allocate on the hot path.

The M0 contract selects codec-specific typed workspaces passed by `ref`, with
fixed arrays for codec storage and explicit decoder state. Decode calls borrow
input/output with `scope`; state retains no references to these slices or the
workspace. Persistent history is copied into the workspace. Exact codec layouts
follow in M1/M2; M0 does not invent a workspace size before those needs are known.

## Consequence

Concurrent callers provide separate workspaces. The API must expose required
workspace size or a typed workspace contract before stabilization. Resuming
requires the same state/workspace pair; sequential reuse requires reset.
See [the core contract](../CORE_CONTRACT.md) for the full ownership rules.
