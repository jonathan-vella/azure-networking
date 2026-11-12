# Contributing

## Guiding Principles

- **Practitioner clarity over boilerplate**: Write concise, opinionated Field Architect guidance. Highlight trade-offs, failure modes, and current platform limits verified against Microsoft Learn.
- **Keep boundaries isolated**: Preserve standalone dependency manifests and lockfiles for root documentation (`package.json`), `tools/firewall-monitor/`, and `tools/netbench/`.
- **Safe CI by default**: Repository workflows validate builds, links, Bicep templates, and Terraform syntax using read-only checks (`contents: read`), with GitHub Pages publishing isolated to `.github/workflows/deploy-pages.yml`. Never commit Azure credentials, local settings, Terraform state, or unapproved deployment schedules.
- **Respect attribution**: Retain upstream authorship and license notices in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Local Validation

### Handbook & Repository Checks

```powershell
npm ci
npm run build
npm run verify
```

### Infrastructure & Labs

```powershell
az bicep build --file labs/virtual-wan-playground/main.bicep --stdout > $null
az bicep build --file tools/firewall-monitor/bicep/setup.bicep --stdout > $null
```

### Operational Tools

- **Firewall Monitor (`tools/firewall-monitor/`)**:
  - Frontend: `cd tools/firewall-monitor/firewall-mon-app && npm ci && npm run build && npm test`
  - API: `dotnet build tools/firewall-monitor/firewall-mon-api/api.csproj`
- **Netbench (`tools/netbench/`)**:
  - Terraform: `cd tools/netbench && terraform fmt -check -recursive && terraform init -backend=false && terraform validate`

