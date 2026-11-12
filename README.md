# Azure networking

Azure networking architectures, patterns, labs, and tools.

## Architectures

- [ExpressRoute traffic segregation](docs/expressroute/segregation/README.md)
- [ExpressRoute FastPath](docs/expressroute/fastpath/README.md)
- [ExpressRoute resiliency](docs/expressroute/resiliency/README.md)
- [AVS hub-and-spoke patterns](docs/avs/hub-spoke/README.md)
- [Virtual WAN review pack](docs/virtual-wan/review/README.md)

## Labs and tools

- [Virtual WAN and hub-and-spoke playground](labs/virtual-wan-playground/README.md)
- [Network benchmark](tools/netbench/README.md)

## Consolidation status

This is a **partial consolidation** pending review and source cutover.
All 11 pinned source snapshots are included in the open draft PR #1, which remains
marked **DO NOT MERGE**. The three sources without upstream license evidence are
covered by the destination owner's authority attestation. Local secret scans of
the selected publication tree, destination history, and all 11 private source
backup histories found no findings. No source repository has been detached,
privatized, or otherwise changed.

[sources.json](sources.json) records every pinned source file and its disposition.
[Third-party notices](THIRD_PARTY_NOTICES.md) preserve attribution and license scope.
Source automation is retained under [reference/](reference/README.md), not activated
as destination deployment workflows. Imported documentation may describe source
automation or upstream deployments that are not enabled here.

## Local checks

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
.\.venv\Scripts\python scripts\verify_consolidation.py
node scripts\verify.mjs
.\.venv\Scripts\python -m mkdocs build --strict
```

Use `--require-complete` with the consolidation verifier to fail while any source
remains blocked. See [CONTRIBUTING.md](CONTRIBUTING.md) for boundaries and validation.
