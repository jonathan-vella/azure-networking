class NetworkBenchmarkDashboard {
    constructor() {
        this.data = [];
        this.filteredData = [];
        this.charts = {};
        this.isLoading = false;
        this.eventListenersSetup = false;
        this.refreshInterval = null;
        this.latencySortOrder = 'alphabetical'; // Default sort order
        this.selectedMetric = 'latency'; // 'latency' | 'throughputGbps' | 'throughputMbps'
        
        this.init();
    }

    async init() {
        try {
            await this.loadData();
            this.setupEventListeners();
            this.renderDashboard();
        } catch (error) {
            this.showError('Error loading data: ' + error.message);
        }
    }

    async loadData() {
        // Prevent concurrent calls
        if (this.isLoading) {
            return;
        }
        
        this.showLoading(true);
        
        try {
            // Use real API to get data from Azure Table Storage
            if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
                // For local development, use mock data
                this.data = this.generateMockData();
            } else {
                try {
                    // Real call to Azure Table Storage via Function App (configurable via window.NETBENCH_API_URL, defaults to /api/data with legacy fallback)
                    const apiUrl = window.NETBENCH_API_URL || '/api/data';
                    console.log('Fetching data from API:', apiUrl);
                    
                    const response = await fetch(apiUrl);
                    if (!response.ok) {
                        throw new Error(`HTTP error! status: ${response.status}`);
                    }
                    
                    const apiData = await response.json();
                    console.log('API returned data:', apiData.length, 'records');
                    
                    if (apiData.length === 0) {
                        console.warn('No data returned from API, using mock data as fallback');
                        this.data = this.generateMockData();
                    } else {
                        this.data = apiData;
                    }
                } catch (apiError) {
                    console.error('API call failed:', apiError.message);
                    console.log('Using mock data as fallback');
                    this.data = this.generateMockData();
                    
                    // Show a warning message
                    this.showError(`Using test data - API unavailable: ${apiError.message}`);
                }
            }
            
            this.processData();
            this.showLoading(false);
            
        } catch (error) {
            this.showLoading(false);
            throw error;
        }
    }

    generateMockData() {
        const regions = ['francecentral', 'westeurope', 'northeurope', 'centralus', 'eastasia'];
        const sources = ['az1', 'az2', 'az3'];
        const destinations = ['az1', 'az2', 'az3'];
        const mockData = [];

        // Generate data for the last 30 days
        const now = new Date();
        for (let days = 0; days < 30; days++) {
            for (let hours = 0; hours < 24; hours += 6) { // Every 6 hours
                regions.forEach(region => {
                    sources.forEach(source => {
                        destinations.forEach(destination => {
                            // Include all cases, even when source === destination
                            const timestamp = new Date(now);
                            timestamp.setDate(timestamp.getDate() - days);
                            timestamp.setHours(hours, 0, 0, 0);

                            // Simulate variable performance based on distance
                            const isSameAZ = source === destination;
                            const baseBandwidth = isSameAZ ? 12.2 : Math.random() * 4 + 8.5;
                            const baseLatency = isSameAZ ? 65 : Math.random() * 350 + 110;
                            const tpGbps = Number(Math.max(0.5, baseBandwidth + (Math.random() - 0.5) * 1.5).toFixed(3));
                            const tpMbps = Number((tpGbps * 1000).toFixed(2));
                            const latUs = Math.max(15, Math.round(baseLatency + (Math.random() - 0.5) * 40));

                            mockData.push({
                                PartitionKey: `test-${Math.random().toString(36).slice(2, 11)}`,
                                RowKey: region,
                                Source: source,
                                Destination: destination,
                                Bandwidth: `${tpGbps.toFixed(3)} Gb/sec`,
                                ThroughputGbps: tpGbps,
                                ThroughputMbps: tpMbps,
                                throughputGbps: tpGbps,
                                throughputMbps: tpMbps,
                                Latency: `${latUs} us`,
                                LatencyUs: latUs,
                                latencyUs: latUs,
                                Timestamp: timestamp.toISOString()
                            });
                        });
                    });
                });
            }
        }

        return mockData;
    }

    processData() {
        console.log('Processing data:', this.data.length, 'items');
        console.log('Sample raw data:', this.data.slice(0, 2));
        
        // Convert raw data to internal format (preserving backward compatibility with latency-only rows)
        this.data = this.data.map(item => {
            let throughputMbps = null;
            let throughputGbps = null;

            const directMbps = item.throughputMbps ?? item.ThroughputMbps;
            const directGbps = item.throughputGbps ?? item.ThroughputGbps;

            if (directMbps !== undefined && directMbps !== null && String(directMbps).trim() !== '' && !Number.isNaN(Number(directMbps))) {
                throughputMbps = Number(directMbps);
            }
            if (directGbps !== undefined && directGbps !== null && String(directGbps).trim() !== '' && !Number.isNaN(Number(directGbps))) {
                throughputGbps = Number(directGbps);
            }

            if (throughputMbps === null && throughputGbps !== null) {
                throughputMbps = Number((throughputGbps * 1000).toFixed(2));
            } else if (throughputGbps === null && throughputMbps !== null) {
                throughputGbps = Number((throughputMbps / 1000).toFixed(3));
            }

            // Fallback to legacy Bandwidth field when present
            if (throughputMbps === null && throughputGbps === null && item.Bandwidth !== undefined && item.Bandwidth !== null && String(item.Bandwidth).trim() !== '') {
                if (typeof item.Bandwidth === 'string') {
                    const bwMatch = item.Bandwidth.match(/([\d.]+)\s*(gb|gbit|gbps|mb|mbit|mbps|kb|kbit|kbps)?/i);
                    if (bwMatch) {
                        const val = parseFloat(bwMatch[1]);
                        const unit = (bwMatch[2] || 'gb').toLowerCase();
                        if (unit.startsWith('gb')) {
                            throughputGbps = val;
                            throughputMbps = val * 1000;
                        } else if (unit.startsWith('kb')) {
                            throughputMbps = val / 1000;
                            throughputGbps = val / 1000000;
                        } else {
                            throughputMbps = val;
                            throughputGbps = val / 1000;
                        }
                    }
                } else if (typeof item.Bandwidth === 'number' && Number.isFinite(item.Bandwidth)) {
                    throughputMbps = item.Bandwidth;
                    throughputGbps = item.Bandwidth / 1000;
                }
            }

            // Parse latency - prefer numeric LatencyUs / latencyUs, fallback to Latency string
            let latency = 0;
            const directLatUs = item.latencyUs ?? item.LatencyUs;
            if (directLatUs !== undefined && directLatUs !== null && String(directLatUs).trim() !== '' && !Number.isNaN(Number(directLatUs))) {
                latency = Number(directLatUs);
            } else if (typeof item.Latency === 'string') {
                const latMatch = item.Latency.match(/([\d.]+)\s*(ns|us|µs|μs|ms|s|sec)?/i);
                if (latMatch) {
                    latency = parseFloat(latMatch[1]);
                    const unit = (latMatch[2] || 'us').toLowerCase();
                    if (unit === 'ns') {
                        latency = latency / 1000;
                    } else if (unit === 'ms') {
                        latency = latency * 1000;
                    } else if (unit === 's' || unit === 'sec') {
                        latency = latency * 1000000;
                    }
                }
            } else {
                latency = parseFloat(item.Latency) || 0;
            }

            return {
                timestamp: new Date(item.Timestamp),
                region: item.RowKey || 'unknown',
                source: item.Source || 'unknown',
                destination: item.Destination || 'unknown',
                bandwidth: throughputGbps ?? 0,
                throughputMbps,
                throughputGbps,
                latency: latency,
                raw: item
            };
        });

        console.log('Processed data sample:', this.data.slice(0, 2));
        
        this.populateFilters();
        
        // Apply initial filters
        this.applyFilters();
    }

    getMetricMeta() {
        switch (this.selectedMetric) {
            case 'throughputGbps':
                return {
                    label: 'Average Throughput (Gbps)',
                    shortLabel: 'Throughput (Gbps)',
                    axisTitle: 'Throughput (Gbps)',
                    barBg: 'rgba(13, 202, 240, 0.65)',
                    barBorder: 'rgba(13, 202, 240, 1)',
                    decimals: 2
                };
            case 'throughputMbps':
                return {
                    label: 'Average Throughput (Mbps)',
                    shortLabel: 'Throughput (Mbps)',
                    axisTitle: 'Throughput (Mbps)',
                    barBg: 'rgba(25, 135, 84, 0.65)',
                    barBorder: 'rgba(25, 135, 84, 1)',
                    decimals: 0
                };
            case 'latency':
            default:
                return {
                    label: 'Average Latency (µs)',
                    shortLabel: 'Latency (µs)',
                    axisTitle: 'Latency (µs)',
                    barBg: 'rgba(255, 185, 0, 0.65)',
                    barBorder: 'rgba(255, 185, 0, 1)',
                    decimals: 1
                };
        }
    }

    getItemMetricValue(item) {
        if (this.selectedMetric === 'throughputGbps') {
            return item.throughputGbps;
        }
        if (this.selectedMetric === 'throughputMbps') {
            return item.throughputMbps;
        }
        return item.latency;
    }

    setMetric(metric) {
        this.selectedMetric = metric;
        const buttonIds = {
            latency: 'metricLatencyBtn',
            throughputGbps: 'metricThroughputGbpsBtn',
            throughputMbps: 'metricThroughputMbpsBtn'
        };

        Object.entries(buttonIds).forEach(([key, id]) => {
            const btn = document.getElementById(id);
            if (!btn) return;
            if (key === metric) {
                btn.classList.remove('btn-outline-primary');
                btn.classList.add('btn-primary');
            } else {
                btn.classList.remove('btn-primary');
                btn.classList.add('btn-outline-primary');
            }
        });

        const meta = this.getMetricMeta();
        const regionTitle = document.getElementById('regionChartTitle');
        const evolutionTitle = document.getElementById('evolutionChartTitle');
        const azPairsTitle = document.getElementById('azPairsChartTitle');
        if (regionTitle) regionTitle.textContent = `${meta.shortLabel} by Region`;
        if (evolutionTitle) evolutionTitle.textContent = `${meta.shortLabel} Evolution by Region`;
        if (azPairsTitle) azPairsTitle.textContent = `Detailed ${meta.shortLabel} Evolution by AZ Pairs`;

        this.renderCharts();
    }

    setupEventListeners() {
        // Prevent multiple calls
        if (this.eventListenersSetup) {
            return;
        }
        
        // Filters
        ['regionFilter', 'sourceFilter', 'destinationFilter', 'timeFilter'].forEach(filterId => {
            document.getElementById(filterId).addEventListener('change', () => this.applyFilters());
        });

        // Auto refresh every 5 minutes
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
        this.refreshInterval = setInterval(() => this.loadData(), 5 * 60 * 1000);
        
        this.eventListenersSetup = true;
    }

    applyFilters() {
        const regionFilter = document.getElementById('regionFilter');
        const sourceFilter = document.getElementById('sourceFilter');
        const destinationFilter = document.getElementById('destinationFilter');
        const timeFilter = document.getElementById('timeFilter').value;

        // Get selected values for multiple selects
        const selectedRegions = Array.from(regionFilter.selectedOptions).map(option => option.value);
        const selectedSources = Array.from(sourceFilter.selectedOptions).map(option => option.value);
        const selectedDestinations = Array.from(destinationFilter.selectedOptions).map(option => option.value);

        let filtered = [...this.data];

        // Filter by regions
        if (selectedRegions.length > 0) {
            filtered = filtered.filter(item => selectedRegions.includes(item.region));
        }

        // Filter by sources
        if (selectedSources.length > 0) {
            filtered = filtered.filter(item => selectedSources.includes(item.source));
        }

        // Filter by destinations
        if (selectedDestinations.length > 0) {
            filtered = filtered.filter(item => selectedDestinations.includes(item.destination));
        }

        // Filter by time
        if (timeFilter !== 'all') {
            const now = new Date();
            let cutoffTime;
            
            switch (timeFilter) {
                case '72h':
                    cutoffTime = new Date(now.getTime() - 72 * 60 * 60 * 1000);
                    break;
                case '7d':
                    cutoffTime = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
                    break;
                case '30d':
                    cutoffTime = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
                    break;
            }
            
            if (cutoffTime) {
                filtered = filtered.filter(item => item.timestamp >= cutoffTime);
            }
        }

        this.filteredData = filtered;
        this.renderDashboard();
    }

    renderDashboard() {
        this.updateSummaryCards();
        this.renderCharts();
        this.renderAbnormalResultsTable();
        this.renderDataTable();
    }

    renderCharts() {
        // Destroy all existing charts first
        this.destroyAllCharts();
        
        this.renderLatencyChart();
        this.renderLatencyEvolutionChart();
        this.renderLatencyAZPairsChart();
    }

    destroyAllCharts() {
        console.log('Destroying all charts...');
        Object.keys(this.charts).forEach(key => {
            if (this.charts[key]) {
                console.log(`Destroying chart: ${key}`);
                this.charts[key].destroy();
                this.charts[key] = null;
            }
        });
        
        // Force destroy any remaining Chart instances on these canvases
        ['latencyChart', 'latencyEvolutionChart', 'latencyAZPairsChart'].forEach(canvasId => {
            const canvas = document.getElementById(canvasId);
            if (canvas) {
                // Get Chart.js instance if exists
                const chartInstance = Chart.getChart(canvas);
                if (chartInstance) {
                    console.log(`Force destroying Chart.js instance on ${canvasId}`);
                    chartInstance.destroy();
                }
            }
        });
    }

    renderLatencyChart() {
        const canvas = document.getElementById('latencyChart');
        if (!canvas) {
            console.error('Canvas latencyChart not found');
            return;
        }
        
        // Ensure any existing chart is destroyed
        const existingChart = Chart.getChart(canvas);
        if (existingChart) {
            console.log('Destroying existing chart on latencyChart');
            existingChart.destroy();
        }
        
        const data = this.filteredData;
        const meta = this.getMetricMeta();
        const regionStats = this.calculateRegionStats(data);

        // Only include regions that have at least one data point for the active metric
        let sortedRegions = Object.keys(regionStats).filter(region => regionStats[region].avgMetric !== null);
        
        switch (this.latencySortOrder) {
            case 'asc':
                sortedRegions.sort((a, b) => regionStats[a].avgMetric - regionStats[b].avgMetric);
                break;
            case 'desc':
                sortedRegions.sort((a, b) => regionStats[b].avgMetric - regionStats[a].avgMetric);
                break;
            case 'alphabetical':
            default:
                sortedRegions.sort((a, b) => this.formatRegionName(a).localeCompare(this.formatRegionName(b)));
                break;
        }

        this.charts.latency = new Chart(canvas, {
            type: 'bar',
            data: {
                labels: sortedRegions.map(region => this.formatRegionName(region)),
                datasets: [{
                    label: meta.label,
                    data: sortedRegions.map(region => Number(regionStats[region].avgMetric.toFixed(meta.decimals))),
                    backgroundColor: meta.barBg,
                    borderColor: meta.barBorder,
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        display: false
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: meta.axisTitle
                        }
                    }
                }
            }
        });
    }

    renderLatencyEvolutionChart() {
        const canvas = document.getElementById('latencyEvolutionChart');
        if (!canvas) {
            console.error('Canvas latencyEvolutionChart not found');
            return;
        }
        
        const existingChart = Chart.getChart(canvas);
        if (existingChart) {
            existingChart.destroy();
        }
        
        const data = this.filteredData;
        const meta = this.getMetricMeta();
        const latencyEvolution = this.calculateLatencyEvolutionByRegion(data);

        this.charts.latencyEvolution = new Chart(canvas, {
            type: 'line',
            data: {
                labels: latencyEvolution.labels,
                datasets: latencyEvolution.datasets
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    title: {
                        display: true,
                        text: `${meta.shortLabel} Evolution by Region Over Time`
                    },
                    legend: {
                        position: 'top'
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: meta.axisTitle
                        }
                    },
                    x: {
                        type: 'time',
                        time: this.getTimeScaleConfig(),
                        title: {
                            display: true,
                            text: 'Date'
                        }
                    }
                },
                elements: {
                    point: {
                        radius: 3,
                        hoverRadius: 6
                    }
                }
            }
        });
    }

    renderLatencyAZPairsChart() {
        const canvas = document.getElementById('latencyAZPairsChart');
        if (!canvas) {
            console.error('Canvas latencyAZPairsChart not found');
            return;
        }
        
        const existingChart = Chart.getChart(canvas);
        if (existingChart) {
            existingChart.destroy();
        }
        
        const data = this.filteredData;
        const meta = this.getMetricMeta();
        const azPairsEvolution = this.calculateLatencyEvolutionByAZPairs(data);

        this.charts.latencyAZPairs = new Chart(canvas, {
            type: 'line',
            data: {
                labels: azPairsEvolution.labels,
                datasets: azPairsEvolution.datasets
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    title: {
                        display: true,
                        text: `Detailed ${meta.shortLabel} Evolution by AZ Pairs (with Traffic Direction)`
                    },
                    legend: {
                        position: 'top',
                        labels: {
                            boxWidth: 12,
                            fontSize: 11
                        }
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: meta.axisTitle
                        }
                    },
                    x: {
                        type: 'time',
                        time: this.getTimeScaleConfig(),
                        title: {
                            display: true,
                            text: 'Date'
                        }
                    }
                },
                elements: {
                    point: {
                        radius: 2,
                        hoverRadius: 4
                    }
                }
            }
        });
    }

    // New method to get time scale configuration based on time filter
    getTimeScaleConfig() {
        const timeFilter = document.getElementById('timeFilter').value;
        
        switch (timeFilter) {
            case '72h':
                return {
                    unit: 'hour',
                    displayFormats: {
                        hour: 'MMM dd HH:mm'
                    },
                    tooltipFormat: 'MMM dd, yyyy HH:mm'
                };
            case '7d':
                return {
                    unit: 'day',
                    displayFormats: {
                        day: 'MMM dd'
                    },
                    tooltipFormat: 'MMM dd, yyyy'
                };
            case '30d':
                return {
                    unit: 'day',
                    displayFormats: {
                        day: 'MMM dd'
                    },
                    tooltipFormat: 'MMM dd, yyyy'
                };
            default: // 'all'
                return {
                    unit: 'day',
                    displayFormats: {
                        day: 'MMM dd',
                        month: 'MMM yyyy'
                    },
                    tooltipFormat: 'MMM dd, yyyy'
                };
        }
    }

    calculateRegionStats(data) {
        const stats = {};
        
        data.forEach(item => {
            if (!stats[item.region]) {
                stats[item.region] = {
                    totalBandwidth: 0,
                    bandwidthCount: 0,
                    totalLatency: 0,
                    count: 0,
                    totalMetric: 0,
                    metricCount: 0
                };
            }
            
            if (item.throughputGbps !== null) {
                stats[item.region].totalBandwidth += item.throughputGbps;
                stats[item.region].bandwidthCount++;
            }
            stats[item.region].totalLatency += item.latency;
            stats[item.region].count++;

            const metricVal = this.getItemMetricValue(item);
            if (metricVal !== null && Number.isFinite(metricVal)) {
                stats[item.region].totalMetric += metricVal;
                stats[item.region].metricCount++;
            }
        });

        Object.keys(stats).forEach(region => {
            stats[region].avgBandwidth = stats[region].bandwidthCount > 0
                ? stats[region].totalBandwidth / stats[region].bandwidthCount
                : 0;
            stats[region].avgLatency = stats[region].totalLatency / stats[region].count;
            stats[region].avgMetric = stats[region].metricCount > 0
                ? stats[region].totalMetric / stats[region].metricCount
                : null;
        });

        return stats;
    }

    calculateLatencyEvolutionByRegion(data) {
        // Group data by time period and region for the currently selected metric
        const timeRegionStats = {};
        const timeFilter = document.getElementById('timeFilter').value;
        const meta = this.getMetricMeta();
        
        data.forEach(item => {
            const metricVal = this.getItemMetricValue(item);
            if (metricVal === null || !Number.isFinite(metricVal)) {
                return;
            }

            let timeKey;
            if (timeFilter === '72h') {
                const hour = new Date(item.timestamp);
                hour.setMinutes(0, 0, 0);
                timeKey = hour.toISOString();
            } else {
                timeKey = item.timestamp.toISOString().split('T')[0];
            }
            
            const region = item.region;
            
            if (!timeRegionStats[timeKey]) {
                timeRegionStats[timeKey] = {};
            }
            
            if (!timeRegionStats[timeKey][region]) {
                timeRegionStats[timeKey][region] = {
                    total: 0,
                    count: 0
                };
            }
            
            timeRegionStats[timeKey][region].total += metricVal;
            timeRegionStats[timeKey][region].count++;
        });

        const timePeriods = Object.keys(timeRegionStats).sort();
        const regions = [...new Set(data.filter(item => this.getItemMetricValue(item) !== null).map(item => item.region))].sort();
        
        const colors = [
            'rgba(255, 99, 132, 1)',
            'rgba(54, 162, 235, 1)',
            'rgba(255, 205, 86, 1)',
            'rgba(75, 192, 192, 1)',
            'rgba(153, 102, 255, 1)',
            'rgba(255, 159, 64, 1)',
            'rgba(199, 199, 199, 1)',
            'rgba(83, 102, 255, 1)',
        ];

        const datasets = regions.map((region, index) => {
            const regionData = timePeriods.map(timePeriod => {
                const stats = timeRegionStats[timePeriod][region];
                return stats ? {
                    x: new Date(timePeriod),
                    y: Number((stats.total / stats.count).toFixed(meta.decimals))
                } : null;
            }).filter(point => point !== null);

            return {
                label: this.formatRegionName(region),
                data: regionData,
                borderColor: colors[index % colors.length],
                backgroundColor: colors[index % colors.length].replace('1)', '0.1)'),
                fill: false,
                tension: 0.1,
                spanGaps: true,
                pointRadius: 3,
                pointHoverRadius: 6
            };
        });

        return {
            labels: timePeriods.map(timePeriod => new Date(timePeriod)),
            datasets: datasets
        };
    }

    calculateLatencyEvolutionByAZPairs(data) {
        // Group data by time period and AZ pair for the currently selected metric
        const timeStats = {};
        const timeFilter = document.getElementById('timeFilter').value;
        const meta = this.getMetricMeta();
        
        data.forEach(item => {
            const metricVal = this.getItemMetricValue(item);
            if (metricVal === null || !Number.isFinite(metricVal)) {
                return;
            }

            let timeKey;
            if (timeFilter === '72h') {
                const hour = new Date(item.timestamp);
                hour.setMinutes(0, 0, 0);
                timeKey = hour.toISOString();
            } else {
                timeKey = item.timestamp.toISOString().split('T')[0];
            }
            
            const azPair = `${item.source} → ${item.destination}`;
            
            if (!timeStats[timeKey]) {
                timeStats[timeKey] = {};
            }
            
            if (!timeStats[timeKey][azPair]) {
                timeStats[timeKey][azPair] = {
                    values: []
                };
            }
            
            timeStats[timeKey][azPair].values.push(metricVal);
        });

        const allTimePeriods = Object.keys(timeStats).sort();
        const allAZPairs = new Set();
        
        Object.values(timeStats).forEach(timeData => {
            Object.keys(timeData).forEach(azPair => {
                allAZPairs.add(azPair);
            });
        });

        const sortedAZPairs = Array.from(allAZPairs).sort();

        const colors = [
            'rgba(255, 99, 132, 1)',
            'rgba(54, 162, 235, 1)',
            'rgba(255, 206, 86, 1)',
            'rgba(75, 192, 192, 1)',
            'rgba(153, 102, 255, 1)',
            'rgba(255, 159, 64, 1)',
            'rgba(199, 199, 199, 1)',
            'rgba(83, 102, 255, 1)',
            'rgba(255, 99, 255, 1)',
            'rgba(99, 255, 132, 1)',
            'rgba(255, 206, 132, 1)',
            'rgba(132, 99, 255, 1)'
        ];

        const datasets = sortedAZPairs.map((azPair, index) => {
            const azPairData = allTimePeriods.map(timePeriod => {
                const timeData = timeStats[timePeriod];
                if (timeData && timeData[azPair] && timeData[azPair].values.length > 0) {
                    const avgVal = timeData[azPair].values.reduce((sum, val) => sum + val, 0) / timeData[azPair].values.length;
                    return {
                        x: new Date(timePeriod),
                        y: Number(avgVal.toFixed(meta.decimals))
                    };
                }
                return null;
            }).filter(point => point !== null);

            return {
                label: azPair,
                data: azPairData,
                borderColor: colors[index % colors.length],
                backgroundColor: colors[index % colors.length].replace('1)', '0.1)'),
                fill: false,
                tension: 0.1,
                spanGaps: true,
                pointRadius: 2,
                pointHoverRadius: 4
            };
        });

        return {
            labels: allTimePeriods.map(timePeriod => new Date(timePeriod)),
            datasets: datasets
        };
    }

    calculateLatencyDistribution(data) {
        // Define latency ranges in microseconds
        const ranges = [
            { label: '< 100 μs', min: 0, max: 100 },
            { label: '100-500 μs', min: 100, max: 500 },
            { label: '500-1000 μs', min: 500, max: 1000 },
            { label: '1000-5000 μs', min: 1000, max: 5000 },
            { label: '> 5000 μs', min: 5000, max: Infinity }
        ];

        const counts = ranges.map(() => 0);
        
        data.forEach(item => {
            const latency = item.latency;
            for (let i = 0; i < ranges.length; i++) {
                if (latency >= ranges[i].min && latency < ranges[i].max) {
                    counts[i]++;
                    break;
                }
            }
        });

        return {
            labels: ranges.map(r => r.label),
            counts: counts
        };
    }

    calculateTimeSeriesData(data) {
        // Group data by day
        const dailyStats = {};
        
        data.forEach(item => {
            const day = item.timestamp.toISOString().split('T')[0];
            
            if (!dailyStats[day]) {
                dailyStats[day] = {
                    totalBandwidth: 0,
                    totalLatency: 0,
                    count: 0
                };
            }
            
            dailyStats[day].totalBandwidth += item.bandwidth;
            dailyStats[day].totalLatency += item.latency;
            dailyStats[day].count++;
        });

        const sortedDays = Object.keys(dailyStats).sort();
        
        return {
            labels: sortedDays.map(day => new Date(day)),
            bandwidth: sortedDays.map(day => (dailyStats[day].totalBandwidth / dailyStats[day].count).toFixed(2)),
            latency: sortedDays.map(day => {
                return {
                    x: new Date(day),
                    y: Math.round(dailyStats[day].totalLatency / dailyStats[day].count)
                };
            })
        };
    }

    formatThroughputCell(item) {
        if (item.throughputGbps !== null && item.throughputMbps !== null) {
            return `${item.throughputGbps.toFixed(2)} Gbps <small class="text-muted">(${Math.round(item.throughputMbps).toLocaleString()} Mbps)</small>`;
        }
        return '<span class="text-muted" title="Legacy latency-only record">—</span>';
    }

    updateSummaryCards() {
        const data = this.filteredData;
        
        // Total tests
        document.getElementById('totalTests').textContent = data.length;
        
        // Unique regions
        const uniqueRegions = new Set(data.map(item => item.region)).size;
        document.getElementById('uniqueRegions').textContent = uniqueRegions;
        
        // Average latency
        const avgLatency = data.length > 0 
            ? Math.round(data.reduce((sum, item) => sum + item.latency, 0) / data.length)
            : 0;
        document.getElementById('avgLatency').textContent = `${avgLatency} μs`;

        // Average throughput (computed only over rows with throughput data)
        const throughputRows = data.filter(item => item.throughputGbps !== null && item.throughputMbps !== null);
        const avgThroughputEl = document.getElementById('avgThroughput');
        const avgThroughputSubEl = document.getElementById('avgThroughputSub');
        if (avgThroughputEl) {
            if (throughputRows.length > 0) {
                const avgGbps = throughputRows.reduce((sum, item) => sum + item.throughputGbps, 0) / throughputRows.length;
                const avgMbps = throughputRows.reduce((sum, item) => sum + item.throughputMbps, 0) / throughputRows.length;
                avgThroughputEl.textContent = `${avgGbps.toFixed(2)} Gbps`;
                if (avgThroughputSubEl) {
                    avgThroughputSubEl.textContent = `${Math.round(avgMbps).toLocaleString()} Mbps avg`;
                }
            } else {
                avgThroughputEl.textContent = 'N/A';
                if (avgThroughputSubEl) {
                    avgThroughputSubEl.textContent = 'Latency-only rows';
                }
            }
        }
        
        // Abnormal results count for TCP one-way tests (intra-zone > 500 μs, inter-zone > 1000 μs)
        const abnormalCount = data.filter(item => {
            const isIntraZone = item.source === item.destination;
            return isIntraZone ? item.latency > 500 : item.latency > 1000;
        }).length;
        document.getElementById('abnormalCount').textContent = abnormalCount;
    }

    renderDataTable() {
        const tbody = document.getElementById('dataTableBody');
        tbody.innerHTML = '';
        
        // Show latest 100 results
        const latestData = [...this.filteredData]
            .sort((a, b) => b.timestamp - a.timestamp)
            .slice(0, 100);
        
        latestData.forEach(item => {
            const row = tbody.insertRow();
            row.innerHTML = `
                <td>${item.timestamp.toLocaleString()}</td>
                <td>${this.formatRegionName(item.region)}</td>
                <td>${item.source}</td>
                <td>${item.destination}</td>
                <td>${this.formatThroughputCell(item)}</td>
                <td>${Math.round(item.latency)} μs</td>
            `;
        });
    }

    renderAbnormalResultsTable() {
        const tbody = document.getElementById('abnormalResultsTableBody');
        const noResultsAlert = document.getElementById('noAbnormalResults');
        const tableContainer = document.getElementById('abnormalResultsTable');
        
        tbody.innerHTML = '';
        
        const abnormalResults = this.filteredData
            .filter(item => {
                const isIntraZone = item.source === item.destination;
                return isIntraZone ? item.latency > 500 : item.latency > 1000;
            })
            .sort((a, b) => b.timestamp - a.timestamp)
            .slice(0, 50);
        
        if (abnormalResults.length === 0) {
            noResultsAlert.style.display = 'block';
            tableContainer.style.display = 'none';
        } else {
            noResultsAlert.style.display = 'none';
            tableContainer.style.display = 'block';
            
            abnormalResults.forEach(item => {
                const row = tbody.insertRow();
                const latencyClass = item.latency > 5000 ? 'text-danger fw-bold' : 'text-warning fw-bold';
                
                row.innerHTML = `
                    <td>${item.timestamp.toLocaleString()}</td>
                    <td>${this.formatRegionName(item.region)}</td>
                    <td>${item.source}</td>
                    <td>${item.destination}</td>
                    <td>${this.formatThroughputCell(item)}</td>
                    <td class="${latencyClass}">${Math.round(item.latency)} μs</td>
                `;
                
                if (item.latency > 5000) {
                    row.classList.add('table-danger');
                } else {
                    row.classList.add('table-warning');
                }
            });
        }
    }

    populateFilters() {
        const regions = [...new Set(this.data.map(item => item.region))].sort();
        const sources = [...new Set(this.data.map(item => item.source))].sort();
        const destinations = [...new Set(this.data.map(item => item.destination))].sort();

        // Populate region filter
        const regionFilter = document.getElementById('regionFilter');
        regionFilter.innerHTML = '';
        regions.forEach(region => {
            const option = document.createElement('option');
            option.value = region;
            option.textContent = this.formatRegionName(region);
            regionFilter.appendChild(option);
        });

        // Populate source filter
        const sourceFilter = document.getElementById('sourceFilter');
        sourceFilter.innerHTML = '';
        sources.forEach(source => {
            const option = document.createElement('option');
            option.value = source;
            option.textContent = source;
            sourceFilter.appendChild(option);
        });

        // Populate destination filter
        const destinationFilter = document.getElementById('destinationFilter');
        destinationFilter.innerHTML = '';
        destinations.forEach(destination => {
            const option = document.createElement('option');
            option.value = destination;
            option.textContent = destination;
            destinationFilter.appendChild(option);
        });
    }

    formatRegionName(region) {
        const regionNames = {
            // Full region names
            'francecentral': 'France Central',
            'francesouth': 'France South',
            'westeurope': 'West Europe', 
            'northeurope': 'North Europe',
            'centralus': 'Central US',
            'eastus': 'East US',
            'eastus2': 'East US 2',
            'westus': 'West US',
            'westus2': 'West US 2',
            'westus3': 'West US 3',
            'eastasia': 'East Asia',
            'southeastasia': 'Southeast Asia',
            'australiaeast': 'Australia East',
            'australiasoutheast': 'Australia Southeast',
            'australiacentral': 'Australia Central',
            'australiacentral2': 'Australia Central 2',
            'brazilsouth': 'Brazil South',
            'brazilsoutheast': 'Brazil Southeast',
            'canadacentral': 'Canada Central',
            'canadaeast': 'Canada East',
            'chinaeast': 'China East',
            'chinaeast2': 'China East 2',
            'chinanorth': 'China North',
            'chinanorth2': 'China North 2',
            'chinanorth3': 'China North 3',
            'germanywestcentral': 'Germany West Central',
            'germanynorth': 'Germany North',
            'centralindia': 'Central India',
            'indiacentral': 'India Central',
            'indonesiacentral': 'Indonesia Central',
            'indiawest': 'India West',
            'indiasouth': 'India South',
            'japaneast': 'Japan East',
            'japanwest': 'Japan West',
            'koreacentral': 'Korea Central',
            'koreasouth': 'Korea South',
            'malaysiawest': 'Malaysia West',
            'newzealandnorth': 'New Zealand North',
            'norwayeast': 'Norway East',
            'norwaywest': 'Norway West',
            'southafricanorth': 'South Africa North',
            'southafricawest': 'South Africa West',
            'southcentralus': 'South Central US',
            'southindia': 'South India',
            'swedencentral': 'Sweden Central',
            'swedensouth': 'Sweden South',
            'switzerlandnorth': 'Switzerland North',
            'switzerlandwest': 'Switzerland West',
            'uaecentral': 'UAE Central',
            'uaenorth': 'UAE North',
            'uksouth': 'UK South',
            'ukwest': 'UK West',
            'westcentralus': 'West Central US',
            'northcentralus': 'North Central US',
            'eastus2euap': 'East US 2 EUAP',
            'centraluseuap': 'Central US EUAP',
            'austriaeast': 'Austria East',
            'chilecentral': 'Chile Central',
            'italynorth': 'Italy North',
            'israelcentral': 'Israel Central',
            'polandcentral': 'Poland Central',
            'qatarcentral': 'Qatar Central',
            'spaincentral': 'Spain Central',
            'taiwannorth': 'Taiwan North',
            'taiwannorthwest': 'Taiwan Northwest',
            'mexicocentral': 'Mexico Central',
            'belgiumcentral': 'Belgium Central',
            
            // Common Azure region abbreviations
            'ea': 'East Asia',
            'sea': 'Southeast Asia',
            'we': 'West Europe',
            'ne': 'North Europe',
            'frc': 'France Central',
            'frs': 'France South',
            'cus': 'Central US',
            'eus': 'East US',
            'eus2': 'East US 2',
            'wus': 'West US',
            'wus2': 'West US 2',
            'wus3': 'West US 3',
            'scus': 'South Central US',
            'ncus': 'North Central US',
            'wcus': 'West Central US',
            'ae': 'Australia East',
            'ase': 'Australia Southeast',
            'acl': 'Australia Central',
            'acl2': 'Australia Central 2',
            'brs': 'Brazil South',
            'brse': 'Brazil Southeast',
            'cnc': 'Canada Central',
            'cae': 'Canada East',
            'gwc': 'Germany West Central',
            'gn': 'Germany North',
            'inc': 'India Central',
            'inw': 'India West',
            'ins': 'India South',
            'jpe': 'Japan East',
            'jpw': 'Japan West',
            'krc': 'Korea Central',
            'krs': 'Korea South',
            'noe': 'Norway East',
            'now': 'Norway West',
            'san': 'South Africa North',
            'saw': 'South Africa West',
            'sdc': 'Sweden Central',
            'sds': 'Sweden South',
            'szn': 'Switzerland North',
            'szw': 'Switzerland West',
            'uac': 'UAE Central',
            'uan': 'UAE North',
            'uks': 'UK South',
            'ukw': 'UK West',
            'clc': 'Chile Central',
            'itn': 'Italy North',
            'isc': 'Israel Central',
            'plc': 'Poland Central',
            'qac': 'Qatar Central',
            'spc': 'Spain Central',
            'twn': 'Taiwan North',
            'twnw': 'Taiwan Northwest',
            'mxc': 'Mexico Central',
            'nzn': 'New Zealand North',
            'nwe': 'Norway East',
            'idc': 'Indonesia Central',
            'myw': 'Malaysia West',
            'ilc': 'Israel Central',
            'bec': 'Belgium Central',
            
            // Availability zones
            'az1': 'Availability Zone 1',
            'az2': 'Availability Zone 2', 
            'az3': 'Availability Zone 3',
            
            // Add fallback for unknown regions
            'unknown': 'Unknown Region'
        };
        
        return regionNames[region] || region.charAt(0).toUpperCase() + region.slice(1);
    }

    showLoading(show) {
        this.isLoading = show;
        const spinner = document.getElementById('loadingSpinner');
        spinner.style.display = show ? 'block' : 'none';
    }

    showError(message) {
        const errorDiv = document.getElementById('errorMessage');
        const errorText = document.getElementById('errorText');
        errorText.textContent = message;
        errorDiv.style.display = 'block';
    }

    clearFilters() {
        // Clear all multiple selects
        document.getElementById('regionFilter').selectedIndex = -1;
        document.getElementById('sourceFilter').selectedIndex = -1;
        document.getElementById('destinationFilter').selectedIndex = -1;
        
        // Reset time filter to default (7d)
        document.getElementById('timeFilter').value = '7d';
        
        // Apply the cleared filters
        this.applyFilters();
    }

    sortLatencyChart(order) {
        this.latencySortOrder = order;
        // Re-render only the region bar chart with the new sort order
        this.renderLatencyChart();
        
        // Visual feedback: highlight only sort buttons inside #regionSortGroup
        document.querySelectorAll('#regionSortGroup button').forEach(btn => {
            btn.classList.remove('active');
        });
        
        const buttonSelectors = {
            'asc': '#regionSortGroup button[onclick*="sortLatencyChart(\'asc\')"]',
            'desc': '#regionSortGroup button[onclick*="sortLatencyChart(\'desc\')"]',
            'alphabetical': '#regionSortGroup button[onclick*="sortLatencyChart(\'alphabetical\')"]'
        };
        
        const activeButton = document.querySelector(buttonSelectors[order]);
        if (activeButton) {
            activeButton.classList.add('active');
        }
    }

    exportData() {
        const csv = this.convertToCSV(this.filteredData);
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `network-benchmark-${new Date().toISOString().split('T')[0]}.csv`;
        a.click();
        window.URL.revokeObjectURL(url);
    }

    convertToCSV(data) {
        const headers = ['Timestamp', 'Region', 'Source', 'Destination', 'Latency (us)', 'Throughput (Mbps)', 'Throughput (Gbps)'];
        const rows = data.map(item => [
            item.timestamp.toISOString(),
            item.region,
            item.source,
            item.destination,
            Math.round(item.latency),
            item.throughputMbps !== null ? item.throughputMbps.toFixed(2) : '',
            item.throughputGbps !== null ? item.throughputGbps.toFixed(3) : ''
        ]);

        return [headers, ...rows].map(row => row.join(',')).join('\n');
    }
}

// Export functions for global access
window.exportData = () => {
    if (window.dashboard) {
        window.dashboard.exportData();
    }
};

window.clearFilters = () => {
    if (window.dashboard) {
        window.dashboard.clearFilters();
    }
};

// Store dashboard instance globally
document.addEventListener('DOMContentLoaded', () => {
    // Prevent creating multiple instances
    if (window.dashboard) {
        console.log('Dashboard instance already exists, skipping creation');
        return;
    }
    
    console.log('Creating new dashboard instance');
    window.dashboard = new NetworkBenchmarkDashboard();
});
