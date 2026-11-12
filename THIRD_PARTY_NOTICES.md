# Third-party notices

This inventory records provenance and license status for all 11 requested upstream
projects. Exact per-file source and destination mappings, pinned commits, and
dispositions are in [sources.json](sources.json). A path marked `reference-only`
is copied for provenance but is not active destination automation.

"Verified" means a source-level license was present in the pinned snapshot; it is
not independent verification that the license covers every third-party asset.
Third-party assets, external services, and embedded contributions must retain any
separate notices and license terms. No separate asset-level license inventory was
established for these snapshots; do not assume the project license overrides
third-party terms. For snapshots without an applicable upstream license, no
permission is inferred from public availability or a destination license. On
2026-11-12, the destination owner attested that they have authority to permit
copying, editing, relocation, and public redistribution of the three pinned
snapshots without upstream license evidence, including their included
third-party assets. These copies are included in the open draft PR #1, which
remains marked **DO NOT MERGE** pending review and cutover.

## Upstream project inventory

### ExpressRoute segregation options

- **Upstream repository:** [Danieleg82/EXR-segregation-options](https://github.com/Danieleg82/EXR-segregation-options)
- **Pinned commit:** `87b566d5e80203aca4467f57a1d5c44b3dadbfc4`
- **Incorporated paths:** `docs/expressroute/segregation/**` (15 files; exact paths in `sources.json`)
- **Original license:** MIT; copied at [docs/expressroute/segregation/LICENSE](docs/expressroute/segregation/LICENSE)
- **Copyright holder:** Daniele Gaiulli, 2023
- **Attribution:** Retain the copyright and MIT license notice in the copied LICENSE file and substantial copies.
- **Third-party assets:** No separate asset-level license inventory was established; review notices accompanying individual assets.
- **Status:** Verified (source-level MIT license).

### AVS hub-and-spoke patterns

- **Upstream repository:** [cynthiatreger/hs-and-ars-for-avs-and-internet-connectivity](https://github.com/cynthiatreger/hs-and-ars-for-avs-and-internet-connectivity)
- **Pinned commit:** `82e4f2975c7bc6e7298587473c7be63a20ec2093`
- **Incorporated paths:** `docs/avs/hub-spoke/**` (2 files; exact paths in `sources.json`)
- **Original license:** MIT; copied at [docs/avs/hub-spoke/LICENSE.md](docs/avs/hub-spoke/LICENSE.md)
- **Copyright holder:** Cynthia Treger, 2023
- **Attribution:** Retain the copyright and MIT license notice in the copied LICENSE file and substantial copies.
- **Third-party assets:** No separate asset-level license inventory was established; review notices accompanying individual assets.
- **Status:** Verified (source-level MIT license).

### Private Endpoints Topologies

- **Upstream repository:** [paolosalvatori/private-endpoints-topologies](https://github.com/paolosalvatori/private-endpoints-topologies)
- **Pinned commit:** `06c2bd45271722cac975cc418834855d9c3907fb`
- **Prepared paths:** `docs/private-link/topologies/**` (9 files; exact paths in `sources.json`); prepared locally and not yet published.
- **Original license:** Not identified in the pinned snapshot.
- **Redistribution status:** Authorized by the destination owner, who attested on 2026-11-12 that they have authority to permit redistribution of this pinned snapshot and included third-party assets.
- **Permission request:** [Issue #11](https://github.com/paolosalvatori/private-endpoints-topologies/issues/11) records the earlier request; the destination-owner authorization is recorded in `sources.json`.
- **Attribution:** Upstream repository and pinned commit are retained here and in `sources.json`.
- **Third-party assets:** No separate asset-level license inventory was established; review notices accompanying individual assets.
- **Status:** Included in open draft PR #1; authorized for redistribution by the destination-owner attestation.

### ExpressRoute Bowtie

- **Upstream repository:** [Danieleg82/Exr-Bowtie](https://github.com/Danieleg82/Exr-Bowtie)
- **Pinned commit:** `fef55a08195e0fc608249d4bcbe2a8bd2e937b46`
- **Prepared paths:** `docs/expressroute/bowtie/**` (20 files; exact paths in `sources.json`); prepared locally and not yet published.
- **Original license:** Not identified in the pinned snapshot.
- **Redistribution status:** Authorized by the destination owner, who attested on 2026-11-12 that they have authority to permit redistribution of this pinned snapshot and included third-party assets.
- **Permission request:** [Issue #2](https://github.com/Danieleg82/Exr-Bowtie/issues/2) records the earlier request; the destination-owner authorization is recorded in `sources.json`.
- **Attribution:** Upstream repository and pinned commit are retained here and in `sources.json`.
- **Third-party assets:** No separate asset-level license inventory was established; review notices accompanying individual assets.
- **Status:** Included in open draft PR #1; authorized for redistribution by the destination-owner attestation.

### ExpressRoute FastPath

- **Upstream repository:** [cynthiatreger/er-fastpath](https://github.com/cynthiatreger/er-fastpath)
- **Pinned commit:** `7cd588c50a1ba68b893c72b77c7686bff6112c28`
- **Incorporated paths:** `docs/expressroute/fastpath/**` (4 files; exact paths in `sources.json`)
- **Original license:** MIT; copied at [docs/expressroute/fastpath/LICENSE](docs/expressroute/fastpath/LICENSE)
- **Copyright holder:** Cynthia Treger, 2023
- **Attribution:** Retain the copyright and MIT license notice in the copied LICENSE file and substantial copies.
- **Third-party assets:** No separate asset-level license inventory was established; review notices accompanying individual assets.
- **Status:** Verified (source-level MIT license).

### ExpressRoute resiliency

- **Upstream repository:** [cynthiatreger/er-resiliency](https://github.com/cynthiatreger/er-resiliency)
- **Pinned commit:** `497f570da536a1a71956f6834da89b7ef2db7f51`
- **Incorporated paths:** `docs/expressroute/resiliency/**` (20 files; exact paths in `sources.json`)
- **Original license:** MIT; copied at [docs/expressroute/resiliency/LICENSE](docs/expressroute/resiliency/LICENSE)
- **Copyright holder:** Cynthia Treger, 2023
- **Attribution:** Retain the copyright and MIT license notice in the copied LICENSE file and substantial copies.
- **Third-party assets:** No separate asset-level license inventory was established; review notices accompanying individual assets.
- **Status:** Verified (source-level MIT license).

### azure-net

- **Upstream repository:** [nehalineogi/azure-networking](https://github.com/nehalineogi/azure-networking)
- **Pinned commit:** `32b7f619193af9cf90d095d2b09012d5afa997de`
- **Prepared paths:** 113 final file mappings, including two reference-only editor configuration files; exact mappings are in `sources.json`.
- **Original license:** Not identified in the pinned snapshot.
- **Redistribution status:** Authorized by the destination owner, who attested on 2026-11-12 that they have authority to permit redistribution of this pinned snapshot and included third-party assets.
- **Permission request:** [Issue #8](https://github.com/nehalineogi/azure-networking/issues/8) records the earlier request; the destination-owner authorization is recorded in `sources.json`.
- **Attribution:** The upstream repository and pinned commit are retained in `sources.json`; acknowledgments in the copied README remain intact.
- **Excluded or changed:** The source `CNAME` is not adopted. The bundled `calicoctl` binary is intentionally omitted; AKS-managed examples use `kubectl`, and [docs/azure-net/calicoctl.md](docs/azure-net/calicoctl.md) explains version matching for self-managed Calico clusters. A byte-identical duplicate GIF maps to its retained canonical copy. Three identical `cloud-init.txt` files remain at their separate example paths.
- **Third-party assets:** External icon and video references remain links; no separate asset-level license inventory was established. Retain any applicable third-party notices and terms.
- **Status:** Included in open draft PR #1; authorized for redistribution by the destination-owner attestation; the bundled `calicoctl` omission is intentional.

### Azure Virtual WAN Playground

- **Upstream repository:** [PieterbasNagengast/Azure-HubSpoke-LabBuilder](https://github.com/PieterbasNagengast/Azure-HubSpoke-LabBuilder)
- **Pinned commit:** `6fc3fc6d1e4563379d8965d8b47a4292460b22ce`
- **Incorporated paths:** `labs/virtual-wan-playground/**` (64 files); `reference/Azure-VirtualWAN-Playground/**` (9 reference-only files; exact paths in `sources.json`)
- **Original license:** MIT; copied at [labs/virtual-wan-playground/LICENSE](labs/virtual-wan-playground/LICENSE)
- **Copyright holder:** Pieterbas Nagengast, 2022
- **Attribution:** Retain the copyright and MIT license notice in the copied LICENSE file and substantial copies.
- **Third-party assets:** No separate asset-level license inventory was established; review notices accompanying individual assets.
- **Status:** Verified (source-level MIT license).

### Azure Netbench

- **Upstream repository:** [vmisson/azure-netbench](https://github.com/vmisson/azure-netbench)
- **Pinned commit:** `2f81859ba9d3839d9140cb8344cbe581ce92b832`
- **Incorporated paths:** `tools/netbench/**` (74 files); `reference/azure-netbench/workflows/**` (36 reference-only files; exact paths in `sources.json`)
- **Original license:** MIT; copied at [tools/netbench/LICENSE](tools/netbench/LICENSE)
- **Copyright holder:** Vincent Misson, 2025
- **Attribution:** Retain the copyright and MIT license notice in the copied LICENSE file and substantial copies.
- **Third-party assets:** No separate asset-level license inventory was established; review notices accompanying individual assets.
- **Status:** Verified (source-level MIT license).

### Azure Firewall Monitor

- **Upstream repository:** [nicolgit/azure-firewall-mon](https://github.com/nicolgit/azure-firewall-mon)
- **Pinned commit:** `8c2d1e2b14122477ec3adfc5c2f38ed275210004`
- **Prepared paths:** `tools/firewall-monitor/**` (86 selected files; exact paths in `sources.json`); prepared locally and not yet published.
- **Original license:** MIT in the pinned snapshot's private preparation.
- **Copyright holder:** NicolD, 2022
- **Attribution:** Retain the MIT copyright and license notice.
- **Third-party assets:** No separate asset-level license inventory was established; review notices accompanying individual assets.
- **Security status:** Local scans of the selected publication tree, destination history, and all 11 private source backup histories found no secrets; reports remain private.
- **Status:** Included in open draft PR #1; not merged.

### Azure Virtual WAN review

- **Upstream repository:** [jonathan-vella/azure-vwan-review](https://github.com/jonathan-vella/azure-vwan-review)
- **Pinned commit:** `a7af698acd9eaefd6b90e5fc5f29a66403aa071b`
- **Incorporated paths:** `docs/virtual-wan/review/**` (13 files); `reference/azure-vwan-review/**` (17 reference-only files), plus 4 symlink aliases and 1 directory alias (exact paths in `sources.json`)
- **Original license:** MIT; copied at [docs/virtual-wan/review/LICENSE](docs/virtual-wan/review/LICENSE)
- **Copyright holder:** Jonathan Vella, 2026
- **Attribution:** Retain the copyright and MIT license notice in the copied LICENSE file and substantial copies.
- **Third-party assets:** No separate asset-level license inventory was established; review notices accompanying individual assets.
- **Status:** Verified (source-level MIT license).

Coauthor credits, documentation references, external image URLs, and upstream
contributor acknowledgments remain in copied content. External references are not
a claim of ownership, permission to copy, or an endorsement. "Reference-only"
files remain outside active destination workflows.
