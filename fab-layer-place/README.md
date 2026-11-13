# fab-layer-place

The place layer's runtime (`spec/statements.md` §26, §29; `spec/layout.md`):
from fab-core's analysis to the Place, every diagram's seed, metric and flow
and every edge's span and collapse resolved, and the layer's own
diagnostics. Pure functions, no I/O. Depends on fab-core; its consumers call
it.

```
zig build test
```

Part of [fAB](../README.md). Pre-alpha. Licensed under AGPL-3.0-or-later.
