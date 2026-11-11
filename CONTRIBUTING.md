# Contributing

Keep architectural articles and their assets together. Preserve each lab or tool's
deployment boundary, dependency manifests, lockfiles, and scoped license notices.
Record source-file moves, deduplicated aliases, and exclusions in `sources.json`.
Do not replace an upstream author's attribution with the fork owner's name.

Use `python scripts/verify_consolidation.py`, `node scripts/verify.mjs`,
`python -m unittest discover -s scripts -p "test_*.py"`, and
`python -m mkdocs build --strict` in an environment installed from
`requirements.txt`. Run case-sensitive documentation checks on Linux as well.
The verifier prints blocked sources; `--require-complete` makes those blockers fail.

Build the playground with
`az bicep build --file labs/virtual-wan-playground/main.bicep --outfile <temporary-file>`.
For Netbench, run `terraform fmt -check -recursive`, `terraform init -backend=false`,
and `terraform validate` from `tools/netbench/`. Do not connect to production state,
apply infrastructure, or run cleanup during migration validation.

The playground's stale Network and Compute API versions were updated to stable
versions accepted by its existing lint rules. Resource properties and deployment
parameters are unchanged. Keep `ARM/main.json` generated from `main.bicep`;
compile all `bicepparams/*.bicepparam` scenarios when changing modules.

Firewall Monitor and its source automation are withheld from the public tree.
Its successful API, Angular and Bicep build receipts remain in private preparation.
Do not add withheld material before its publication gates are resolved.
Prepared files with `publication_blocks` are still checked for fidelity, and
`--require-complete` must fail until those blocks are explicitly resolved.

Deployment, cleanup, schedules, source PR merges, repository settings, GitHub Pages
publication, and fork detachment require separate approval. Reference workflows
are intentionally outside `.github/workflows/`; copying them back without adapting
their paths, permissions, credentials, and safeguards is unsafe.

Do not commit private backups, permission correspondence, local settings, credentials,
Terraform state, generated sites, or installed dependencies. Use local redacted
secret scanning before publishing. Previously public material is not automatically
licensed for redistribution.
