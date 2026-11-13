# Azure network benchmark dashboard

Web dashboard and Azure Functions API for querying and charting physical Availability Zone latency (`qperf`) and parallel-stream throughput (`iperf3`) stored in Azure Table Storage.

- **Repository path:** [`jonathan-vella/azure-networking/tools/netbench/dashboard`](https://github.com/jonathan-vella/azure-networking/tree/main/tools/netbench/dashboard) (adapted from [`vmisson/azure-netbench`](https://github.com/vmisson/azure-netbench))
- **Benchmark suite documentation:** [`tools/netbench/README.md`](../README.md)
- **Handbook guide:** [Hands-On Labs & Operational Tools Guide (`tools/netbench`)](../../../src/content/docs/06-operations-reviews/labs-and-tools-guide.md#5-azure-netbench-latency--throughput-suite-toolsnetbench) ([live site](https://jonathan-vella.github.io/azure-networking/06-operations-reviews/labs-and-tools-guide/#5-azure-netbench-latency--throughput-suite-toolsnetbench))

## Architecture

- **Frontend (`web/`):** Static Web App built with Bootstrap 5 and Chart.js.
- **Backend (`api/`):** Azure Functions Node.js 22 LTS HTTP endpoint (`GET /api/data`) using a module-scoped `DefaultAzureCredential` singleton to query Azure Table Storage.
- **Data store:** Azure Table Storage (`perf` table by default) populated by `tools/netbench` Ubuntu 24.04 LTS client VMs.
- **Infrastructure (`infra/`):** Terraform stack (`azurerm ~> 5.13`, `azurecaf ~> 1.2.0`) provisioning a Standard Static Web App, HTTPS-only Linux Function App (Node.js 22 LTS), TLS 1.2 function storage account, and `Storage Table Data Reader` role assignments.

## Capabilities

- Switch regional bar and time-series charts between Latency (µs), Throughput (Gbps), and Throughput (Mbps).
- Display total test count, active regions, average `qperf` latency (µs), average `iperf3` throughput (Gbps and Mbps), and abnormal latency count (`> 500 µs` intra-zone, `> 1000 µs` inter-zone).
- Normalize all 36 `regions.json` region names and `azurerm/locations/azure` short codes (for example `we` to `westeurope` and `inc` to `centralindia`) so historical and new rows aggregate under one canonical region.
- Render historical latency-only rows (`throughputMbps: null`, `throughputGbps: null`) alongside dual-metric `qperf` and `iperf3` records.
- Filter by region, source AZ, destination AZ, and time window (`72h`, `7d`, `30d`, `all`), fetching full history via `/api/data?window=all` when `All Time` is selected, and export filtered rows to CSV.

## Quick start

### Prerequisites

- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) (`azd`)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.9
- [Node.js](https://nodejs.org/) >= 20 (Node.js 22 LTS recommended to match the Function App runtime)
- Existing Azure Storage Account containing benchmark Table Storage entities

### Run automated unit tests

The API includes a zero-dependency `node:test` suite (`api/data/index.test.js`) covering latency/throughput parsing, 36-region short-code normalization, OData filter validation and injection rejection, fallback behavior when `AZURE_STORAGE_ACCOUNT_NAME` is unset, and `MAX_RESULTS` pagination:

```bash
cd tools/netbench/dashboard/api
npm ci
npm test
```

### Deploy to Azure

1. Sign in and initialize the `azd` environment:
   ```bash
   cd tools/netbench/dashboard
   azd auth login
   azd init
   ```

2. Provision the Terraform stack and deploy both services:
   ```bash
   azd up
   ```
   Supply `storage_account_name`, `storage_account_resource_group`, and optional `storage_table_name` or `subscription_id` when prompted or via Terraform variables in `infra/variables.tf`.

### Local development

1. Start the Azure Functions API locally:
   ```bash
   cd tools/netbench/dashboard/api
   npm install
   func start
   ```

2. Serve the static frontend locally:
   ```bash
   cd tools/netbench/dashboard/web
   npx serve .
   ```
   When opened on `localhost` or `127.0.0.1`, the frontend generates multi-region mock latency and throughput data (30 days by default, 45 days when `All Time` is selected).

## Configuration

### Function App environment variables

- `AZURE_STORAGE_ACCOUNT_NAME`: Target Azure Storage Account name. When unset or blank, `/api/data` logs a warning and returns a two-record sample fallback dataset.
- `AZURE_STORAGE_TABLE_NAME`: Table containing benchmark entities (default `perf`).
- `MAX_RESULTS`: Maximum entities returned per request (default `200000`).

### Query parameters (`GET /api/data`)

- `window`: Optional duration preset (`72h`, `7d`, `30d`, `<N>h`, `<N>d`, or `all`; defaults to `30d`). Passing `all` omits the `Timestamp ge ...` OData filter to return full history up to `MAX_RESULTS`.
- `days`: Optional positive day count (`1` to `3650`, clamped) or `all` when `window` is not specified. Malformed or non-numeric strings return HTTP `400`.

### Normalized response entity

```json
{
  "PartitionKey": "00000000-0000-0000-0000-000000000001",
  "RowKey": "we",
  "Region": "westeurope",
  "region": "westeurope",
  "regionDisplayName": "West Europe",
  "Source": "az1",
  "Destination": "az2",
  "Latency": "142.30 us",
  "LatencyUs": 142.3,
  "Bandwidth": "12.485 Gb/sec",
  "ThroughputMbps": 12485,
  "ThroughputGbps": 12.485,
  "latencyUs": 142.3,
  "throughputMbps": 12485,
  "throughputGbps": 12.485,
  "Timestamp": "2026-01-15T12:00:00Z"
}
```

## Project structure

```text
tools/netbench/dashboard/
├── api/                        # Azure Functions Node.js 22 LTS backend
│   ├── data/
│   │   ├── function.json       # HTTP GET /api/data trigger binding
│   │   ├── index.js            # Table query, OData filter builder, entity normalizer
│   │   └── index.test.js       # Zero-dependency node:test unit suite
│   ├── test/                   # GET /api/test health check endpoint
│   ├── host.json               # Functions v4 extension bundle config
│   └── package.json            # Dependencies, engines (>=20), and npm test script
├── web/                        # Static Web App frontend
│   ├── index.html              # Summary KPIs, filter controls, metric toggle, tables
│   ├── script.js               # Chart.js charts, ?window=all loader, CSV export
│   └── package.json            # Static app metadata
├── infra/                      # Terraform infrastructure (azurerm ~> 5.13)
│   ├── .terraform.lock.hcl     # Locked azurerm 5.13.0 and azurecaf 1.2.34 hashes
│   ├── main.tf                 # SWA, Node 22 Function App (HTTPS only), Storage RBAC
│   ├── variables.tf            # Environment, location, and storage inputs
│   └── outputs.tf              # Deployed endpoints
└── azure.yaml                  # Azure Developer CLI (azd) service manifest
```

## License

Licensed under the MIT License. See [LICENSE](../../../LICENSE) and [THIRD_PARTY_NOTICES.md](../../../THIRD_PARTY_NOTICES.md) (upstream attribution: [`vmisson/azure-netbench`](https://github.com/vmisson/azure-netbench)).

