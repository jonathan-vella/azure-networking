# Contributing

## Guiding principles

- Document concrete topology trade-offs, packet-walk failure modes, and current Azure platform limits verified against `learn.microsoft.com`. Prefer vector SVG and Mermaid 12 diagrams over static raster screenshots.
- Maintain standalone dependency manifests across workspaces: public `registry.npmjs.org` lockfiles for root documentation (`package.json`: Astro 7, Starlight 0.42, Mermaid 12), `tools/firewall-monitor/firewall-mon-app/` (Angular 22, Vitest 5), `tools/netbench/dashboard/api/`, and `tools/netbench/dashboard/web/`, alongside `.NET 8` (`tools/firewall-monitor/firewall-mon-api/api.csproj`) and Terraform manifests (`tools/netbench/providers.tf` with `azurerm` 5.13 and `azapi` 2.13, plus `tools/netbench/dashboard/infra/main.tf`).
- Keep pull request and branch checks in `.github/workflows/checks.yml` read-only (`contents: read`) with zero live cloud deployments. GitHub Pages publishing stays isolated in `.github/workflows/deploy-pages.yml`. Never commit Azure credentials, local Function settings, Terraform state files, private package feed URLs, or scheduled deployment triggers.
- Retain upstream copyright notices, redistribution attestations, and archive provenance in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [`.archive/ARCHIVE_MANIFEST.json`](.archive/ARCHIVE_MANIFEST.json).

## Local validation

Run the matching validation suite from the repository root before opening a pull request. These commands mirror `.github/workflows/checks.yml`.

### Handbook and repository integrity (`Node.js 22+`)

```powershell
npm ci
npm run verify    # Validates routes, exact-case links/assets, anchors, Mermaid 12 headers, lockfiles, and .archive/ARCHIVE_MANIFEST.json
npm run build     # Builds Astro 7 + Starlight 0.42 static site
```

### Bicep labs and tool templates (`Azure CLI + Bicep 0.48.1+`)

```powershell
az bicep build --file labs/virtual-wan-playground/main.bicep --stdout > $null
az bicep build --file labs/foundry-networking/build-foundry-standard-agent-vnet.bicep --stdout > $null
az bicep build --file tools/firewall-monitor/bicep/setup.bicep --stdout > $null
az bicep build --file tools/firewall-monitor/bicep/firewall-mon-azure-stuff.bicep --stdout > $null
```

### Operational tools (`Node.js 22+`, `.NET 8`, `Terraform 1.9.x`)

- **Firewall Monitor (`tools/firewall-monitor/`)**:
  - Angular 22 + Vitest 5 frontend: `npm --prefix tools/firewall-monitor/firewall-mon-app ci; npm --prefix tools/firewall-monitor/firewall-mon-app run build; npm --prefix tools/firewall-monitor/firewall-mon-app test`
  - .NET 8 isolated Azure Functions API: `dotnet build tools/firewall-monitor/firewall-mon-api/api.csproj --configuration Release`
- **Netbench (`tools/netbench/`)**:
  - Benchmark Terraform (`azurerm ~> 5.13`, `azapi ~> 2.13`): `terraform -chdir=tools/netbench fmt -check -recursive; terraform -chdir=tools/netbench init -backend=false; terraform -chdir=tools/netbench validate`
  - Dashboard Terraform (`tools/netbench/dashboard/infra/`): `terraform -chdir=tools/netbench/dashboard/infra init -backend=false; terraform -chdir=tools/netbench/dashboard/infra validate`


