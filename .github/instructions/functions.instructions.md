---
applyTo: "functions/**/*.ts"
---
- TypeScript strict, Firebase Functions v2, region asia-south1, Node 20.
- Validate every callable input with zod. Check auth, custom claims, and App Check on every callable.
- Never log PHI. Use structured logs with ids only.
- Every state-changing function writes an auditLogs entry in the same transaction/batch.
- Idempotent handlers (use event ids / idempotency keys).
