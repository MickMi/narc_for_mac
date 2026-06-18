# Design Handoff

This directory contains UI deliverables from the Design AI tool.

## How it works

1. **Design AI** writes complete `.swift` files here
2. **Claude Code** picks them up, compiles, and integrates with business logic
3. Files here are staging — once integrated, they move to `Sources/Views/`

## Structure

```
design-handoff/
├── CURRENT.md        ← Change summary for this batch
├── views/            ← New or rewritten SwiftUI view files
└── assets/           ← Any new image/icon assets
```

## For the Design AI

Write complete, compilable SwiftUI files using tokens from `Sources/Design/DesignTokens.swift`.
Mark any data dependencies with `// TODO: Code 侧接线`.
