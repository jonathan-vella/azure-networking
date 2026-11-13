const { TableClient } = require('@azure/data-tables');
const { DefaultAzureCredential } = require('@azure/identity');

const DEFAULT_MAX_RESULTS = 200000;
const DEFAULT_WINDOW_DAYS = 30;
const MIN_WINDOW_HOURS = 1;
const MAX_WINDOW_DAYS = 3650;
const MAX_WINDOW_HOURS = MAX_WINDOW_DAYS * 24;

const CORS_HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET',
    'Access-Control-Allow-Headers': 'Content-Type'
};

// Official Azure region display names covering all 36 regions.json entries plus common Azure regions
const REGION_DISPLAY_NAMES = Object.freeze(Object.assign(Object.create(null), {
    australiaeast: 'Australia East',
    australiasoutheast: 'Australia Southeast',
    australiacentral: 'Australia Central',
    australiacentral2: 'Australia Central 2',
    austriaeast: 'Austria East',
    belgiumcentral: 'Belgium Central',
    brazilsouth: 'Brazil South',
    brazilsoutheast: 'Brazil Southeast',
    canadacentral: 'Canada Central',
    canadaeast: 'Canada East',
    centralindia: 'Central India',
    centralus: 'Central US',
    centraluseuap: 'Central US EUAP',
    chilecentral: 'Chile Central',
    eastasia: 'East Asia',
    eastus: 'East US',
    eastus2: 'East US 2',
    eastus2euap: 'East US 2 EUAP',
    francecentral: 'France Central',
    francesouth: 'France South',
    germanynorth: 'Germany North',
    germanywestcentral: 'Germany West Central',
    indonesiacentral: 'Indonesia Central',
    israelcentral: 'Israel Central',
    italynorth: 'Italy North',
    japaneast: 'Japan East',
    japanwest: 'Japan West',
    koreacentral: 'Korea Central',
    koreasouth: 'Korea South',
    malaysiawest: 'Malaysia West',
    mexicocentral: 'Mexico Central',
    newzealandnorth: 'New Zealand North',
    northcentralus: 'North Central US',
    northeurope: 'North Europe',
    norwayeast: 'Norway East',
    norwaywest: 'Norway West',
    polandcentral: 'Poland Central',
    qatarcentral: 'Qatar Central',
    southafricanorth: 'South Africa North',
    southafricawest: 'South Africa West',
    southcentralus: 'South Central US',
    southeastasia: 'Southeast Asia',
    southindia: 'South India',
    spaincentral: 'Spain Central',
    swedencentral: 'Sweden Central',
    swedensouth: 'Sweden South',
    switzerlandnorth: 'Switzerland North',
    switzerlandwest: 'Switzerland West',
    taiwannorth: 'Taiwan North',
    taiwannorthwest: 'Taiwan Northwest',
    uaecentral: 'UAE Central',
    uaenorth: 'UAE North',
    uksouth: 'UK South',
    ukwest: 'UK West',
    westcentralus: 'West Central US',
    westeurope: 'West Europe',
    westindia: 'West India',
    westus: 'West US',
    westus2: 'West US 2',
    westus3: 'West US 3'
}));

// Maps azurerm/locations/azure short_name codes (written to RowKey by cloud-init-client.txt) to canonical Azure region names
const SHORT_CODE_TO_REGION = Object.freeze(Object.assign(Object.create(null), {
    ae: 'australiaeast',
    ase: 'australiasoutheast',
    acl: 'australiacentral',
    acl2: 'australiacentral2',
    bec: 'belgiumcentral',
    brs: 'brazilsouth',
    brse: 'brazilsoutheast',
    cnc: 'canadacentral',
    cae: 'canadaeast',
    inc: 'centralindia',
    ci: 'centralindia',
    cus: 'centralus',
    clc: 'chilecentral',
    ea: 'eastasia',
    eus: 'eastus',
    eus2: 'eastus2',
    frc: 'francecentral',
    frs: 'francesouth',
    gn: 'germanynorth',
    gwc: 'germanywestcentral',
    idc: 'indonesiacentral',
    ilc: 'israelcentral',
    isc: 'israelcentral',
    itn: 'italynorth',
    jpe: 'japaneast',
    jpw: 'japanwest',
    krc: 'koreacentral',
    krs: 'koreasouth',
    myw: 'malaysiawest',
    mxc: 'mexicocentral',
    nzn: 'newzealandnorth',
    ncus: 'northcentralus',
    ne: 'northeurope',
    nwe: 'norwayeast',
    noe: 'norwayeast',
    now: 'norwaywest',
    plc: 'polandcentral',
    qac: 'qatarcentral',
    san: 'southafricanorth',
    saw: 'southafricawest',
    scus: 'southcentralus',
    sea: 'southeastasia',
    ins: 'southindia',
    spc: 'spaincentral',
    sdc: 'swedencentral',
    sds: 'swedensouth',
    szn: 'switzerlandnorth',
    szw: 'switzerlandwest',
    twn: 'taiwannorth',
    twnw: 'taiwannorthwest',
    uac: 'uaecentral',
    uan: 'uaenorth',
    uks: 'uksouth',
    ukw: 'ukwest',
    wcus: 'westcentralus',
    we: 'westeurope',
    inw: 'westindia',
    wus: 'westus',
    wus2: 'westus2',
    wus3: 'westus3'
}));

const DISPLAY_NAME_TO_REGION = Object.freeze(
    Object.assign(
        Object.create(null),
        Object.fromEntries(
            Object.entries(REGION_DISPLAY_NAMES).map(([slug, display]) => [
                display.toLowerCase().replace(/[\s_-]+/g, ''),
                slug
            ])
        )
    )
);

let sharedCredential = null;

function getAzureCredential() {
    if (!sharedCredential) {
        sharedCredential = new DefaultAzureCredential();
    }
    return sharedCredential;
}

function normalizeRegion(rawRegion) {
    if (rawRegion === undefined || rawRegion === null) {
        return 'unknown';
    }
    const trimmed = String(rawRegion).trim();
    if (!trimmed) {
        return 'unknown';
    }
    const lower = trimmed.toLowerCase();
    if (Object.hasOwn(SHORT_CODE_TO_REGION, lower)) {
        return SHORT_CODE_TO_REGION[lower];
    }
    if (Object.hasOwn(REGION_DISPLAY_NAMES, lower)) {
        return lower;
    }
    const compact = lower.replace(/[\s_-]+/g, '');
    if (Object.hasOwn(SHORT_CODE_TO_REGION, compact)) {
        return SHORT_CODE_TO_REGION[compact];
    }
    if (Object.hasOwn(REGION_DISPLAY_NAMES, compact)) {
        return compact;
    }
    if (Object.hasOwn(DISPLAY_NAME_TO_REGION, compact)) {
        return DISPLAY_NAME_TO_REGION[compact];
    }
    return lower;
}

function getRegionDisplayName(rawRegion) {
    const canonical = normalizeRegion(rawRegion);
    if (canonical === 'unknown') {
        return 'Unknown Region';
    }
    return Object.hasOwn(REGION_DISPLAY_NAMES, canonical)
        ? REGION_DISPLAY_NAMES[canonical]
        : canonical.charAt(0).toUpperCase() + canonical.slice(1);
}

function parseNumericLatencyUs(entity) {
    if (!entity || typeof entity !== 'object') {
        return null;
    }

    const direct = entity.LatencyUs ?? entity.latencyUs;
    if (typeof direct === 'number' && Number.isFinite(direct) && direct >= 0) {
        return direct;
    }
    if (typeof direct === 'string' && direct.trim() !== '') {
        const parsedDirect = Number(direct.trim());
        if (Number.isFinite(parsedDirect) && parsedDirect >= 0) {
            return parsedDirect;
        }
    }

    const raw = entity.Latency;
    if (typeof raw === 'number' && Number.isFinite(raw) && raw >= 0) {
        return raw;
    }
    if (typeof raw === 'string') {
        const trimmed = raw.trim();
        if (!trimmed) {
            return null;
        }
        const bareNumber = trimmed.match(/^(\d+(?:\.\d+)?)$/);
        if (bareNumber) {
            return parseFloat(bareNumber[1]);
        }
        if (/-\s*\d/.test(trimmed)) {
            return null;
        }
        const match = trimmed.match(/(?:^|\s|=)(\d+(?:\.\d+)?)\s*(ns|us|µs|μs|ms|s|sec)\b/i);
        if (match) {
            const value = parseFloat(match[1]);
            if (!Number.isFinite(value) || value < 0) {
                return null;
            }
            const unit = match[2].toLowerCase();
            if (unit === 'ns') return value / 1000;
            if (unit === 'ms') return value * 1000;
            if (unit === 's' || unit === 'sec') return value * 1000000;
            return value;
        }
    }
    return null;
}

function parseThroughputMetrics(entity) {
    if (!entity || typeof entity !== 'object') {
        return { throughputMbps: null, throughputGbps: null };
    }

    const rawMbps = entity.ThroughputMbps ?? entity.throughputMbps;
    const rawGbps = entity.ThroughputGbps ?? entity.throughputGbps;

    let mbps = null;
    let gbps = null;

    if (typeof rawMbps === 'number' && Number.isFinite(rawMbps) && rawMbps >= 0) {
        mbps = rawMbps;
    } else if (typeof rawMbps === 'string' && rawMbps.trim() !== '') {
        const parsedMbps = Number(rawMbps.trim());
        if (Number.isFinite(parsedMbps) && parsedMbps >= 0) {
            mbps = parsedMbps;
        }
    }

    if (typeof rawGbps === 'number' && Number.isFinite(rawGbps) && rawGbps >= 0) {
        gbps = rawGbps;
    } else if (typeof rawGbps === 'string' && rawGbps.trim() !== '') {
        const parsedGbps = Number(rawGbps.trim());
        if (Number.isFinite(parsedGbps) && parsedGbps >= 0) {
            gbps = parsedGbps;
        }
    }

    if (mbps === null && gbps !== null) {
        mbps = Number((gbps * 1000).toFixed(2));
    } else if (gbps === null && mbps !== null) {
        gbps = Number((mbps / 1000).toFixed(3));
    }

    // Fallback to legacy Bandwidth string/number when present
    if (mbps === null && gbps === null && entity.Bandwidth !== undefined && entity.Bandwidth !== null && String(entity.Bandwidth).trim() !== '') {
        if (typeof entity.Bandwidth === 'number' && Number.isFinite(entity.Bandwidth) && entity.Bandwidth >= 0) {
            mbps = entity.Bandwidth;
            gbps = Number((mbps / 1000).toFixed(3));
        } else if (typeof entity.Bandwidth === 'string') {
            const trimmedBw = entity.Bandwidth.trim();
            if (/-\s*\d/.test(trimmedBw)) {
                return { throughputMbps: null, throughputGbps: null };
            }
            const bareBw = trimmedBw.match(/^(\d+(?:\.\d+)?)$/);
            const bwMatch = bareBw
                ? [bareBw[0], bareBw[1], 'gb']
                : trimmedBw.match(/(?:^|\s|=)(\d+(?:\.\d+)?)\s*(gb|gbit|gbps|mb|mbit|mbps|kb|kbit|kbps)(?:\/s(?:ec)?)?\b/i);
            if (bwMatch) {
                const val = parseFloat(bwMatch[1]);
                if (Number.isFinite(val) && val >= 0) {
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
    }

    return { throughputMbps: mbps, throughputGbps: gbps };
}

function normalizeEntity(entity) {
    const safeEntity = entity && typeof entity === 'object' ? entity : {};
    const latencyUs = parseNumericLatencyUs(safeEntity);
    const { throughputMbps, throughputGbps } = parseThroughputMetrics(safeEntity);
    const rawRowKey = safeEntity.rowKey ?? safeEntity.RowKey ?? null;
    const canonicalRegion = normalizeRegion(safeEntity.region ?? safeEntity.Region ?? rawRowKey);
    const regionDisplayName = getRegionDisplayName(canonicalRegion);

    return {
        PartitionKey: safeEntity.partitionKey ?? safeEntity.PartitionKey,
        RowKey: rawRowKey !== null && String(rawRowKey).trim() !== '' ? String(rawRowKey).trim() : canonicalRegion,
        Region: canonicalRegion,
        region: canonicalRegion,
        regionDisplayName,
        Source: safeEntity.Source,
        Destination: safeEntity.Destination,
        Bandwidth: safeEntity.Bandwidth ?? (throughputGbps !== null ? `${throughputGbps} Gb/sec` : null),
        Latency: safeEntity.Latency ?? (latencyUs !== null ? `${latencyUs} us` : null),
        LatencyUs: latencyUs,
        ThroughputMbps: throughputMbps,
        ThroughputGbps: throughputGbps,
        latencyUs,
        throughputMbps,
        throughputGbps,
        Timestamp: safeEntity.timestamp ?? safeEntity.Timestamp
    };
}

function createInvalidQueryError(message) {
    const err = new RangeError(message);
    err.statusCode = 400;
    return err;
}

function buildTimeFilter(query = {}, now = new Date()) {
    const refDate = now instanceof Date && !Number.isNaN(now.getTime()) ? now : new Date();
    const params = typeof query === 'string' ? { window: query } : (query && typeof query === 'object' ? query : {});

    const hasWindow = params.window !== undefined && params.window !== null && String(params.window).trim() !== '';
    const hasDays = params.days !== undefined && params.days !== null && String(params.days).trim() !== '';

    let durationMs = DEFAULT_WINDOW_DAYS * 24 * 60 * 60 * 1000;

    if (hasWindow) {
        const rawWindow = String(params.window).trim();
        if (rawWindow.toLowerCase() === 'all') {
            return null;
        }
        const hourMatch = rawWindow.match(/^(\d+(?:\.\d+)?)h$/i);
        const dayMatch = rawWindow.match(/^(\d+(?:\.\d+)?)d?$/i);
        if (hourMatch) {
            const parsedHours = Number(hourMatch[1]);
            if (!Number.isFinite(parsedHours) || parsedHours <= 0) {
                throw createInvalidQueryError('Query parameter "window" must be a positive duration (e.g., 72h, 7d, 30d, or all).');
            }
            const clampedHours = Math.min(Math.max(parsedHours, MIN_WINDOW_HOURS), MAX_WINDOW_HOURS);
            durationMs = clampedHours * 60 * 60 * 1000;
        } else if (dayMatch) {
            const parsedDays = Number(dayMatch[1]);
            if (!Number.isFinite(parsedDays) || parsedDays <= 0) {
                throw createInvalidQueryError('Query parameter "window" must be a positive duration (e.g., 72h, 7d, 30d, or all).');
            }
            const clampedDays = Math.min(Math.max(parsedDays, 1), MAX_WINDOW_DAYS);
            durationMs = clampedDays * 24 * 60 * 60 * 1000;
        } else {
            throw createInvalidQueryError('Invalid "window" parameter. Supported values: 72h, 7d, 30d, <N>h, <N>d, or all.');
        }
    }

    if (hasDays) {
        const rawDays = params.days;
        if (typeof rawDays === 'string' && rawDays.trim().toLowerCase() === 'all') {
            return null;
        }
        let parsedDays;
        if (typeof rawDays === 'number') {
            parsedDays = rawDays;
        } else if (typeof rawDays === 'string' && /^\d+(?:\.\d+)?$/.test(rawDays.trim())) {
            parsedDays = Number(rawDays.trim());
        } else {
            throw createInvalidQueryError('Invalid "days" parameter. Expected a positive number or "all".');
        }
        if (!Number.isFinite(parsedDays) || parsedDays <= 0) {
            throw createInvalidQueryError('Query parameter "days" must be greater than zero.');
        }
        if (!hasWindow) {
            const clampedDays = Math.min(Math.max(parsedDays, 1), MAX_WINDOW_DAYS);
            durationMs = clampedDays * 24 * 60 * 60 * 1000;
        }
    }

    const cutoffIso = new Date(refDate.getTime() - durationMs).toISOString();
    return `Timestamp ge datetime'${cutoffIso}'`;
}

function buildFallbackData(nowIso = new Date().toISOString()) {
    return [
        normalizeEntity({
            PartitionKey: 'fallback-1',
            RowKey: 'we',
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
            RowKey: 'ne',
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
}

async function dataHandler(context, req = {}, deps = {}) {
    const logInfo = typeof context?.log === 'function' ? context.log.bind(context) : () => {};
    const logWarn = typeof context?.log?.warn === 'function'
        ? context.log.warn.bind(context.log)
        : (typeof context?.warn === 'function' ? context.warn.bind(context) : logInfo);
    const logError = typeof context?.log?.error === 'function'
        ? context.log.error.bind(context.log)
        : (typeof context?.error === 'function' ? context.error.bind(context) : logInfo);

    logInfo('Data function called');

    let filter;
    try {
        filter = buildTimeFilter(req?.query, deps.now);
    } catch (validationError) {
        logWarn(`Rejected invalid query parameters: ${validationError.message}`);
        context.res = {
            status: validationError.statusCode || 400,
            headers: CORS_HEADERS,
            body: JSON.stringify({ error: validationError.message })
        };
        return;
    }

    try {
        const parsedMax = parseInt(deps.maxResults ?? process.env.MAX_RESULTS ?? String(DEFAULT_MAX_RESULTS), 10);
        const maxResults = Number.isFinite(parsedMax) && parsedMax > 0 ? parsedMax : DEFAULT_MAX_RESULTS;
        const tableName = (deps.tableName ?? process.env.AZURE_STORAGE_TABLE_NAME ?? 'perf').trim() || 'perf';

        let tableClient = deps.tableClient || null;
        if (!tableClient) {
            const storageAccountName = (deps.storageAccountName ?? process.env.AZURE_STORAGE_ACCOUNT_NAME ?? '').trim();
            if (!storageAccountName) {
                logWarn('AZURE_STORAGE_ACCOUNT_NAME is not configured; returning sample fallback dataset.');
                context.res = {
                    status: 200,
                    headers: CORS_HEADERS,
                    body: JSON.stringify(buildFallbackData())
                };
                return;
            }
            if (!/^[a-z0-9]{3,24}$/.test(storageAccountName)) {
                throw new Error(`Invalid AZURE_STORAGE_ACCOUNT_NAME format: "${storageAccountName}"`);
            }

            logInfo(`Connecting to storage account: ${storageAccountName}, table: ${tableName}, max results: ${maxResults}`);
            const tableServiceUrl = `https://${storageAccountName}.table.core.windows.net`;
            tableClient = new TableClient(
                tableServiceUrl,
                tableName,
                deps.credential || getAzureCredential()
            );
        }

        logInfo(filter ? `Querying data with filter: ${filter}` : 'Querying all historical data (no Timestamp filter)');

        const entities = [];
        const listOptions = filter ? { queryOptions: { filter } } : {};
        const pageableEntities = tableClient.listEntities(listOptions);

        let count = 0;
        for await (const entity of pageableEntities) {
            if (count >= maxResults) {
                logInfo(`Reached maximum limit of ${maxResults} entities`);
                break;
            }

            entities.push(normalizeEntity(entity));
            count++;
        }

        logInfo(`Successfully retrieved ${entities.length} entities`);

        context.res = {
            status: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify(entities)
        };
    } catch (error) {
        logError('Error retrieving data from Azure Table Storage:', error);

        context.res = {
            status: 200,
            headers: CORS_HEADERS,
            body: JSON.stringify(buildFallbackData())
        };
    }
}

dataHandler.parseNumericLatencyUs = parseNumericLatencyUs;
dataHandler.parseThroughputMetrics = parseThroughputMetrics;
dataHandler.normalizeEntity = normalizeEntity;
dataHandler.normalizeRegion = normalizeRegion;
dataHandler.getRegionDisplayName = getRegionDisplayName;
dataHandler.buildTimeFilter = buildTimeFilter;
dataHandler.getAzureCredential = getAzureCredential;
dataHandler.REGION_DISPLAY_NAMES = REGION_DISPLAY_NAMES;
dataHandler.SHORT_CODE_TO_REGION = SHORT_CODE_TO_REGION;

module.exports = dataHandler;
