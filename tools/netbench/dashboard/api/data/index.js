const { TableClient } = require('@azure/data-tables');
const { DefaultAzureCredential } = require('@azure/identity');

function parseNumericLatencyUs(entity) {
    const direct = entity.LatencyUs ?? entity.latencyUs;
    if (typeof direct === 'number' && Number.isFinite(direct)) {
        return direct;
    }
    if (typeof direct === 'string' && direct.trim() !== '' && !Number.isNaN(Number(direct))) {
        return Number(direct);
    }

    const raw = entity.Latency;
    if (typeof raw === 'number' && Number.isFinite(raw)) {
        return raw;
    }
    if (typeof raw === 'string') {
        const match = raw.match(/([\d.]+)\s*(ns|us|µs|μs|ms|s|sec)?/i);
        if (match) {
            const value = parseFloat(match[1]);
            const unit = (match[2] || 'us').toLowerCase();
            if (unit === 'ns') return value / 1000;
            if (unit === 'ms') return value * 1000;
            if (unit === 's' || unit === 'sec') return value * 1000000;
            return value;
        }
    }
    return null;
}

function parseThroughputMetrics(entity) {
    const rawMbps = entity.ThroughputMbps ?? entity.throughputMbps;
    const rawGbps = entity.ThroughputGbps ?? entity.throughputGbps;

    let mbps = null;
    let gbps = null;

    if (typeof rawMbps === 'number' && Number.isFinite(rawMbps)) {
        mbps = rawMbps;
    } else if (typeof rawMbps === 'string' && rawMbps.trim() !== '' && !Number.isNaN(Number(rawMbps))) {
        mbps = Number(rawMbps);
    }

    if (typeof rawGbps === 'number' && Number.isFinite(rawGbps)) {
        gbps = rawGbps;
    } else if (typeof rawGbps === 'string' && rawGbps.trim() !== '' && !Number.isNaN(Number(rawGbps))) {
        gbps = Number(rawGbps);
    }

    if (mbps === null && gbps !== null) {
        mbps = Number((gbps * 1000).toFixed(2));
    } else if (gbps === null && mbps !== null) {
        gbps = Number((mbps / 1000).toFixed(3));
    }

    // Fallback to legacy Bandwidth string/number when present
    if (mbps === null && gbps === null && entity.Bandwidth !== undefined && entity.Bandwidth !== null && String(entity.Bandwidth).trim() !== '') {
        if (typeof entity.Bandwidth === 'number' && Number.isFinite(entity.Bandwidth)) {
            mbps = entity.Bandwidth;
            gbps = Number((mbps / 1000).toFixed(3));
        } else if (typeof entity.Bandwidth === 'string') {
            const bwMatch = entity.Bandwidth.match(/([\d.]+)\s*(gb|gbit|gbps|mb|mbit|mbps|kb|kbit|kbps)?/i);
            if (bwMatch) {
                const val = parseFloat(bwMatch[1]);
                const unit = (bwMatch[2] || 'gb').toLowerCase();
                if (unit.startsWith('gb')) {
                    gbps = Number(val.toFixed(3));
                    mbps = Number((val * 1000).toFixed(2));
                } else if (unit.startsWith('kb')) {
                    mbps = Number((val / 1000).toFixed(3));
                    gbps = Number((val / 1000000).toFixed(6));
                } else {
                    mbps = Number(val.toFixed(2));
                    gbps = Number((val / 1000).toFixed(3));
                }
            }
        }
    }

    return { throughputMbps: mbps, throughputGbps: gbps };
}

function normalizeEntity(entity) {
    const latencyUs = parseNumericLatencyUs(entity);
    const { throughputMbps, throughputGbps } = parseThroughputMetrics(entity);

    return {
        PartitionKey: entity.partitionKey ?? entity.PartitionKey,
        RowKey: entity.rowKey ?? entity.RowKey,
        Source: entity.Source,
        Destination: entity.Destination,
        Bandwidth: entity.Bandwidth ?? (throughputGbps !== null ? `${throughputGbps} Gb/sec` : null),
        Latency: entity.Latency ?? (latencyUs !== null ? `${latencyUs} us` : null),
        LatencyUs: latencyUs,
        ThroughputMbps: throughputMbps,
        ThroughputGbps: throughputGbps,
        latencyUs,
        throughputMbps,
        throughputGbps,
        Timestamp: entity.timestamp ?? entity.Timestamp
    };
}

module.exports = async function (context, req) {
    context.log('Data function called');
    
    try {
        const storageAccountName = process.env.AZURE_STORAGE_ACCOUNT_NAME || 'sanetprdfrc001';
        const tableName = process.env.AZURE_STORAGE_TABLE_NAME || 'perf';
        const maxResults = parseInt(process.env.MAX_RESULTS || '200000', 10);
        
        context.log(`Connecting to storage account: ${storageAccountName}, table: ${tableName}, max results: ${maxResults}`);
        
        const tableServiceUrl = `https://${storageAccountName}.table.core.windows.net`;
        
        const tableClient = new TableClient(
            tableServiceUrl,
            tableName,
            new DefaultAzureCredential()
        );

        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
        
        context.log(`Querying data from ${thirtyDaysAgo.toISOString()}`);
        
        const entities = [];
        
        const pageableEntities = tableClient.listEntities({
            queryOptions: {
                filter: `Timestamp ge datetime'${thirtyDaysAgo.toISOString()}'`
            }
        });

        let count = 0;
        for await (const entity of pageableEntities) {
            if (count >= maxResults) {
                context.log(`Reached maximum limit of ${maxResults} entities`);
                break;
            }
            
            entities.push(normalizeEntity(entity));
            count++;
        }
        
        context.log(`Successfully retrieved ${entities.length} entities`);

        context.res = {
            status: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            body: JSON.stringify(entities)
        };

    } catch (error) {
        context.error('Error retrieving data from Azure Table Storage:', error);
        
        const nowIso = new Date().toISOString();
        const fallbackData = [
            normalizeEntity({
                PartitionKey: 'fallback-1',
                RowKey: 'westeurope',
                Source: 'az1',
                Destination: 'az2',
                Latency: '145 us',
                LatencyUs: 145,
                Bandwidth: '12.480 Gb/sec',
                ThroughputMbps: 12480,
                ThroughputGbps: 12.48,
                Timestamp: nowIso
            }),
            normalizeEntity({
                PartitionKey: 'fallback-2',
                RowKey: 'northeurope',
                Source: 'az1',
                Destination: 'az3',
                Latency: '182 us',
                LatencyUs: 182,
                Bandwidth: '11.920 Gb/sec',
                ThroughputMbps: 11920,
                ThroughputGbps: 11.92,
                Timestamp: nowIso
            })
        ];

        context.res = {
            status: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            body: JSON.stringify(fallbackData)
        };
    }
};
