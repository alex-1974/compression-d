# ADR 0002 — Caller-owned workspace

## Decision

Decode APIs receive caller-owned output and temporary workspace. They do not
retain slices after returning and do not allocate on the hot path.

## Consequence

Concurrent callers provide separate workspaces. The API must expose required
workspace size or a typed workspace contract before stabilization.
