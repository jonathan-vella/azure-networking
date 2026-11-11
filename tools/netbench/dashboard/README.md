# Azure Network Benchmark Dashboard

A comprehensive dashboard for visualizing Azure network performance data stored in Azure Table Storage.

## Architecture

- **Frontend**: Static Web App with responsive HTML5/CSS3/JavaScript
- **Backend**: Azure Functions API for data access
- **Data Storage**: Azure Table Storage containing network performance metrics
- **Infrastructure**: Terraform for Infrastructure as Code
- **Deployment**: Azure Developer CLI (azd)

## Features

- 📊 **Real-time Charts**: Bandwidth and latency visualization by region
- 🔍 **Advanced Filters**: Filter by region, availability zone, and time range
- 📈 **Time Series Analysis**: Track performance trends over time
- 📤 **Data Export**: Export filtered data to CSV format
- 📱 **Responsive Design**: Mobile-friendly interface
- 🔄 **Auto Refresh**: Automatic data refresh every 5 minutes

## Quick Start

### Prerequisites

- [Azure Developer CLI](https://docs.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- Azure subscription

### Deployment

1. **Initialize the environment**:
   ```bash
   cd dashboard
   azd auth login
   azd init
   ```

2. **Deploy infrastructure and application**:
   ```bash
   azd up
   ```

3. **Access your dashboard**:
   The deployment will output the URL of your Static Web App.

### Local Development

1. **Start the Azure Functions locally**:
   ```bash
   cd api
   func start
   ```

2. **Serve the static web app locally**:
   ```bash
   cd web
   # Use any local web server, e.g.:
   python -m http.server 8000
   # or
   npx serve .
   ```

## Configuration

### Environment Variables

The Azure Function requires these environment variables:

- `AZURE_STORAGE_ACCOUNT_NAME`: Name of your Azure Storage Account
- `AZURE_STORAGE_TABLE_NAME`: Name of the table containing performance data (default: "perf")

### Data Format

The expected data format in Azure Table Storage:

```json
{
  "PartitionKey": "test-partition",
  "RowKey": "region-name",
  "Source": "az1",
  "Destination": "az2", 
  "Bandwidth": "15.23 Gb/sec",
  "Latency": "125 us",
  "Timestamp": "2025-01-01T12:00:00Z"
}
```

## Project Structure

```
dashboard/
├── api/                    # Azure Functions backend
│   ├── benchmark-data/     # HTTP trigger function
│   ├── host.json          # Functions runtime config
│   └── package.json       # Node.js dependencies
├── web/                   # Static web application
│   ├── index.html         # Main dashboard page
│   ├── script.js          # Dashboard logic and charts
│   └── package.json       # Static app metadata
├── infra/                 # Terraform infrastructure
│   ├── main.tf           # Main infrastructure resources
│   ├── variables.tf      # Input variables
│   ├── outputs.tf        # Output values
│   └── providers.tf      # Provider configurations
└── azure.yaml            # azd configuration
```

## Technology Stack

- **Frontend**: HTML5, CSS3 (Bootstrap 5), JavaScript (Chart.js)
- **Backend**: Node.js, Azure Functions v4
- **Infrastructure**: Terraform, Azure Resource Manager
- **Storage**: Azure Table Storage
- **Identity**: Azure Managed Identity
- **Hosting**: Azure Static Web Apps, Azure Functions

## Monitoring and Troubleshooting

### View Logs

```bash
# Function App logs
az functionapp logs tail --name <function-app-name> --resource-group <resource-group>

# Application Insights (if configured)
# Check the Azure portal for Application Insights dashboard
```

### Common Issues

1. **API not responding**: Check Function App permissions and managed identity configuration
2. **Data not loading**: Verify storage account name and table name in environment variables
3. **Charts not displaying**: Check browser console for JavaScript errors

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
