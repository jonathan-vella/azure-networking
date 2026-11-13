# Third-party notices

This repository consolidates and updates architectural guidance, diagrams, labs, and operational tools imported from 11 upstream repositories in PR [#1](https://github.com/jonathan-vella/azure-networking/pull/1) (merged into `main` at `9cd4419`). Active handbook chapters use rebuilt vector SVG or Mermaid diagrams. Original upstream snapshot files, raw Draw.io and Excalidraw sources, and retired raster screenshots or animated GIF exports remain preserved in `.archive/` (packaged into gitignored `.archive/legacy-archive.tar.gz` and cataloged with SHA-256 digests in [`.archive/ARCHIVE_MANIFEST.json`](.archive/ARCHIVE_MANIFEST.json)).

Newly authored handbook material, rebuilt vector SVG diagrams, and repository validation scripts are licensed under the root [MIT License](LICENSE). Original copyright notices and MIT license terms for upstream projects are preserved below and apply to retained and adapted portions of those works. For the three upstream snapshots that did not include an explicit license file (`private-endpoints-topologies`, `expressroute-bowtie`, and `azure-networking` / `azure-net`), the destination owner attested on 2026-11-12 to holding authority to copy, edit, relocate, and publicly redistribute those snapshots and their included assets.

## Upstream project provenance and copyright notices

### 1. ExpressRoute segregation options
- **Upstream repository:** [Danieleg82/EXR-segregation-options](https://github.com/Danieleg82/EXR-segregation-options) (`87b566d5e80203aca4467f57a1d5c44b3dadbfc4`)
- **Copyright and license:** Copyright (c) 2023 Daniele Gaiulli, MIT License
- **Current location:** Adapted into `src/content/docs/03-hybrid-connectivity/expressroute-traffic-segregation.md` with rebuilt vector SVG or Mermaid diagrams; original upstream raster screenshots remain preserved in `.archive/legacy-archive.tar.gz` and indexed in `.archive/ARCHIVE_MANIFEST.json`

### 2. AVS hub-and-spoke patterns
- **Upstream repository:** [cynthiatreger/hs-and-ars-for-avs-and-internet-connectivity](https://github.com/cynthiatreger/hs-and-ars-for-avs-and-internet-connectivity) (`82e4f2975c7bc6e72987473c7be63a20ec2093`)
- **Copyright and license:** Copyright (c) 2023 Cynthia Treger, MIT License
- **Current location:** Adapted into `src/content/docs/05-workload-networking/avs-networking.md` with rebuilt vector SVG or Mermaid diagrams

### 3. Private Endpoints Topologies
- **Upstream repository:** [paolosalvatori/private-endpoints-topologies](https://github.com/paolosalvatori/private-endpoints-topologies) (`06c2bd45271722cac975cc418834855d9c3907fb`)
- **Authorization:** Destination-owner redistribution attestation (2026-11-12); upstream attribution to Paolo Salvatori preserved
- **Current location:** Adapted into `src/content/docs/04-network-security/private-link-and-dns-at-scale.md` with rebuilt vector SVG or Mermaid diagrams; original upstream raster screenshots remain preserved in `.archive/legacy-archive.tar.gz` and indexed in `.archive/ARCHIVE_MANIFEST.json`

### 4. ExpressRoute Bowtie
- **Upstream repository:** [Danieleg82/Exr-Bowtie](https://github.com/Danieleg82/Exr-Bowtie) (`fef55a08195e0fc608249d4bcbe2a8bd2e937b46`)
- **Authorization:** Destination-owner redistribution attestation (2026-11-12); upstream attribution to Daniele Gaiulli preserved
- **Current location:** Adapted into `src/content/docs/03-hybrid-connectivity/expressroute-bowtie-failures.md` with rebuilt vector SVG or Mermaid diagrams; original upstream raster exports remain preserved in `.archive/legacy-archive.tar.gz` and indexed in `.archive/ARCHIVE_MANIFEST.json`

### 5. ExpressRoute FastPath
- **Upstream repository:** [cynthiatreger/er-fastpath](https://github.com/cynthiatreger/er-fastpath) (`7cd588c50a1ba68b893c72b77c7686bff6112c28`)
- **Copyright and license:** Copyright (c) 2023 Cynthia Treger, MIT License
- **Current location:** Adapted into `src/content/docs/03-hybrid-connectivity/expressroute-fastpath-and-skus.md` with rebuilt vector SVG or Mermaid diagrams; original upstream animated GIF exports remain preserved in `.archive/legacy-archive.tar.gz` and indexed in `.archive/ARCHIVE_MANIFEST.json`

### 6. ExpressRoute resiliency
- **Upstream repository:** [cynthiatreger/er-resiliency](https://github.com/cynthiatreger/er-resiliency) (`497f570da536a1a71956f6834da89b7ef2db7f51`)
- **Copyright and license:** Copyright (c) 2023 Cynthia Treger, MIT License
- **Current location:** Adapted into `src/content/docs/03-hybrid-connectivity/expressroute-resiliency.md` with rebuilt vector SVG or Mermaid diagrams; original upstream PNG diagrams remain preserved in `.archive/legacy-archive.tar.gz` and indexed in `.archive/ARCHIVE_MANIFEST.json`

### 7. azure-net (`nehalineogi/azure-networking`)
- **Upstream repository:** [nehalineogi/azure-networking](https://github.com/nehalineogi/azure-networking) (`32b7f619193af9cf90d095d2b09012d5afa997de`)
- **Authorization:** Destination-owner redistribution attestation (2026-11-12); upstream attribution to Nehali Neogi and contributors preserved
- **Current location:** Active labs and samples maintained under `labs/aks/`, `labs/foundry-networking/`, and `samples/bgp-bird/`, with handbook chapters in `src/content/docs/05-workload-networking/` using rebuilt vector SVG or Mermaid diagrams; original upstream GIF, PNG, Draw.io, and Excalidraw sources remain preserved in `.archive/legacy-archive.tar.gz` and indexed in `.archive/ARCHIVE_MANIFEST.json`

### 8. Azure Virtual WAN Playground
- **Upstream repository:** [PieterbasNagengast/Azure-HubSpoke-LabBuilder](https://github.com/PieterbasNagengast/Azure-HubSpoke-LabBuilder) (`6fc3fc6d1e4563379d8965d8b47a4292460b22ce`)
- **Copyright and license:** Copyright (c) 2022 Pieterbas Nagengast, MIT License
- **Current location:** `labs/virtual-wan-playground/`

### 9. Azure Netbench
- **Upstream repository:** [vmisson/azure-netbench](https://github.com/vmisson/azure-netbench) (`2f81859ba9d3839d9140cb8344cbe581ce92b832`)
- **Copyright and license:** Copyright (c) 2025 Vincent Misson, MIT License
- **Current location:** `tools/netbench/`

### 10. Azure Firewall Monitor
- **Upstream repository:** [nicolgit/azure-firewall-mon](https://github.com/nicolgit/azure-firewall-mon) (`8c2d1e2b14122477ec3adfc5c2f38ed275210004`)
- **Copyright and license:** Copyright (c) 2022 NicolD, MIT License
- **Current location:** `tools/firewall-monitor/`

### 11. Azure Virtual WAN review
- **Upstream repository:** [jonathan-vella/azure-vwan-review](https://github.com/jonathan-vella/azure-vwan-review) (`a7af698acd9eaefd6b90e5fc5f29a66403aa071b`)
- **Copyright and license:** Copyright (c) 2026 Jonathan Vella, MIT License
- **Current location:** Adapted into `src/content/docs/06-operations-reviews/`

## Preserved MIT license text (applicable to MIT-licensed upstream works above)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

