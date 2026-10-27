# ADR 0001 — Pure-D core

## Decision

The codec core is implemented in D without C bindings, system libraries or
backend wrappers.

## Rationale

This gives the project control over safety annotations, workspace ownership,
expansion limits, error contracts and compiler-specific optimization.

## Consequence

The project owns a larger correctness and compatibility burden. Every codec
must have an independent reference corpus before admission.
