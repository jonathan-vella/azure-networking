# Azure Network Benchmark Dashboard

Interactive web dashboard for visualizing Azure Availability Zone **latency (`qperf`)** and **parallel-stream throughput (`iperf3`)** metrics stored in Azure Table Storage.

> **Repository location:** [`jonathan-vella/azure-networking/tools/netbench/dashboard`](https://github.com/jonathan-vella/azure-networking/tree/main/tools/netbench/dashboard) (adapted from upstream [`vmisson/azure-netbench`](https://github.com/vmisson/azure-netbench)).

## Architecture

- **Frontend (`web/`)**: Static Web App built with Bootstrap 5 and Chart.js
- **Backend (`api/`)**: Azure Functions Node.js HTTP API (`/api/data`) authenticating via Managed Identity (`DefaultAzureCredential`)
- **Data Storage**: Azure Table Storage containing benchmark entities
- **Infrastructure (`infra/`)**: Terraform configuration for Static Web App, Function App, and `Storage Table Data Reader` RBAC assignments
- **Deployment**: Azure Developer CLI (`azd`)

## Features

- **Metric View Toggle**: Switch regional bar and time-series charts dynamically between **Latency (µs)**, **Throughput (Gbps)**, and **Throughput (Mbps)**
- **Summary KPIs**: Total tests, tested regions, average `qperf` latency (µs), average `iperf3` throughput (Gbps & Mbps), and abnormal latency count
- **Backward Compatibility**: Seamlessly normalizes legacy latency-only Table Storage rows alongside new `LatencyUs` / `ThroughputMbps` / `ThroughputGbps` entities
- **Advanced Filters**: Filter by region (all 36 `netbench` regions supported), source AZ, destination AZ, and time window (`72h`, `7d`, `30d`, `all`)
- **CSV Export**: Export filtered latency (µs) and throughput (Mbps/Gbps) series to CSV
- **Auto Refresh**: Refreshes metrics automatically every 5 minutes

## Quick Start

### Prerequisites

- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) (`azd`)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`)
- Azure subscription with an existing benchmark Storage Account

### Deployment

1. **Initialize the environment**:
   ```bash
   cd tools/netbench/dashboard
   azd auth login
   azd init
   ```

2. **Deploy infrastructure and application**:
   ```bash
   azd up
   ```
   You can customize `storage_account_name`, `storage_account_resource_group`, and `storage_table_name` in `infra/variables.tf` or via Terraform variables.

### Local Development

1. **Start the Azure Functions API locally**:
   ```bash
   cd tools/netbench/dashboard/api
   func start
   ```

2. **Serve the static frontend locally**:
   ```bash
   cd tools/netbench/dashboard/web
   npx serve .
   ```
   When served on `localhost` or `127.0.0.1`, the dashboard automatically generates realistic multi-region latency and throughput mock data.

## Configuration

### Function App Environment Variables

- `AZURE_STORAGE_ACCOUNT_NAME`: Name of your Azure Storage Account
- `AZURE_STORAGE_TABLE_NAME`: Table containing performance data (default: `perf`)
- `MAX_RESULTS`: Maximum entities returned per query (default: `200000`)

### Data Format

Table Storage entities written by `tools/netbench` (`cloud-init-client.txt`) and normalized by `/api/data`:

```json
{
  "PartitionKey": "00000000-0000-0000-0000-000000000001",
  "RowKey": "we",
  "Source": "az1",
  "Destination": "az2",
  "Latency": "142.30 us",
  "LatencyUs": 142.3,
  "Bandwidth": "12.485 Gb/sec",
  "ThroughputMbps": 12485.0,
  "ThroughputGbps": 12.485,
  "latencyUs": 142.3,
  "throughputMbps": 12485.0,
  "throughputGbps": 12.485,
  "Timestamp": "2026-01-15T12:00:00Z"
}
```

Historical rows that only contain `Latency` (without `ThroughputMbps` / `ThroughputGbps` / `Bandwidth`) return `throughputMbps: null` and `throughputGbps: null` and render cleanly in the UI.

## Project Structure

```text
tools/netbench/dashboard/
├── api/                    # Azure Functions backend
│   ├── data/               # GET /api/data Table Storage query & normalization
│   ├── test/               # Health check endpoint
│   ├── host.json           # Functions runtime config
│   └── package.json        # Node.js dependencies
├── web/                    # Static web application
│   ├── index.html          # Dashboard layout, summary cards, metric toggle, tables
│   ├── script.js           # Chart.js rendering, filtering, CSV export
│   └── package.json        # Static app metadata
├── infra/                  # Terraform infrastructure
│   ├── main.tf             # Static Web App, Function App, Storage RBAC
│   ├── variables.tf        # Environment, location, and storage variables
│   └── outputs.tf          # Deployed endpoints
└── azure.yaml              # Azure Developer CLI (azd) service manifest
```

## License

Licensed under the MIT License — see [LICENSE](../../../LICENSE) and [THIRD_PARTY_NOTICES.md](../../../THIRD_PARTY_NOTICES.md) (upstream attribution: [`vmisson/azure-netbench`](https://github.com/vmisson/azure-netbench)).

