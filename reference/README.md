# Source automation and configuration references

These are preserved source configuration snapshots, **not active destination
automation**. In particular, workflow files beneath this directory cannot run as
GitHub Actions workflows.

Playground workflows can deploy and delete Azure resources. Netbench workflows
include schedules and storage-access changes. Their repository-root paths and
credential assumptions have not been approved for execution in the destination.
Do not run them manually or move them into `.github/workflows/`.

The review pack's original MkDocs, checks, and configuration are retained for
provenance. The destination uses root `mkdocs.yml` and adapted scripts instead.
Review-pack duplicate symlinks are represented as aliases in `sources.json`;
the canonical Markdown lives under `docs/virtual-wan/review/`.
