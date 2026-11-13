const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const dataHandler = require('./index.js');
const {
    parseNumericLatencyUs,
    parseThroughputMetrics,
    normalizeEntity,
    normalizeRegion,
    getRegionDisplayName,
    buildTimeFilter,
    getAzureCredential,
    SHORT_CODE_TO_REGION,
    REGION_DISPLAY_NAMES
} = dataHandler;

function createMockContext() {
    const logs = [];
    const warnings = [];
    const errors = [];
    const logFn = (...args) => logs.push(args.join(' '));
    logFn.warn = (...args) => warnings.push(args.join(' '));
    logFn.error = (...args) => errors.push(args.join(' '));

    return {
        log: logFn,
        warn: (...args) => warnings.push(args.join(' ')),
        error: (...args) => errors.push(args.join(' ')),
        logs,
        warnings,
        errors,
        res: null
    };
}

test('module.exports preserves Azure Functions HTTP trigger default export and helper properties', () => {
    assert.equal(typeof dataHandler, 'function');
    assert.equal(typeof parseNumericLatencyUs, 'function');
    assert.equal(typeof parseThroughputMetrics, 'function');
    assert.equal(typeof normalizeEntity, 'function');
    assert.equal(typeof buildTimeFilter, 'function');
    assert.strictEqual(getAzureCredential(), getAzureCredential(), 'DefaultAzureCredential should be a lazy singleton');
});

test('parseNumericLatencyUs parses direct numbers, numeric strings, legacy units, and rejects invalid inputs', () => {
    assert.equal(parseNumericLatencyUs({ LatencyUs: 84.5 }), 84.5);
    assert.equal(parseNumericLatencyUs({ latencyUs: 0 }), 0);
    assert.equal(parseNumericLatencyUs({ LatencyUs: '142.30' }), 142.3);
    assert.equal(parseNumericLatencyUs({ Latency: 95.2 }), 95.2);
    assert.equal(parseNumericLatencyUs({ Latency: '84.50 us' }), 84.5);
    assert.equal(parseNumericLatencyUs({ Latency: '84.5 µs' }), 84.5);
    assert.equal(parseNumericLatencyUs({ Latency: '84.5 μs' }), 84.5);
    assert.equal(parseNumericLatencyUs({ Latency: '500 ns' }), 0.5);
    assert.equal(parseNumericLatencyUs({ Latency: '1.25 ms' }), 1250);
    assert.equal(parseNumericLatencyUs({ Latency: '0.002 s' }), 2000);
    assert.equal(parseNumericLatencyUs({ Latency: '0.003 sec' }), 3000);
    assert.equal(parseNumericLatencyUs({ Latency: 'latency = 110.4 us' }), 110.4);
    assert.equal(parseNumericLatencyUs({ Latency: '67.8' }), 67.8);

    assert.equal(parseNumericLatencyUs(null), null);
    assert.equal(parseNumericLatencyUs(undefined), null);
    assert.equal(parseNumericLatencyUs({}), null);
    assert.equal(parseNumericLatencyUs({ Latency: '' }), null);
    assert.equal(parseNumericLatencyUs({ Latency: '...' }), null);
    assert.equal(parseNumericLatencyUs({ Latency: 'N/A' }), null);
    assert.equal(parseNumericLatencyUs({ Latency: '-15 us' }), null);
    assert.equal(parseNumericLatencyUs({ LatencyUs: -5 }), null);
    assert.equal(parseNumericLatencyUs({ LatencyUs: Number.NaN }), null);
    assert.equal(parseNumericLatencyUs({ LatencyUs: Number.POSITIVE_INFINITY }), null);
});

test('parseThroughputMetrics parses direct Mbps/Gbps, cross-derives missing units, and parses legacy Bandwidth strings', () => {
    assert.deepEqual(
        parseThroughputMetrics({ ThroughputMbps: 12485, ThroughputGbps: 12.485 }),
        { throughputMbps: 12485, throughputGbps: 12.485 }
    );
    assert.deepEqual(
        parseThroughputMetrics({ throughputGbps: '9.875' }),
        { throughputMbps: 9875, throughputGbps: 9.875 }
    );
    assert.deepEqual(
        parseThroughputMetrics({ ThroughputMbps: 2500 }),
        { throughputMbps: 2500, throughputGbps: 2.5 }
    );
    assert.deepEqual(
        parseThroughputMetrics({ Bandwidth: '12.485 Gb/sec' }),
        { throughputMbps: 12485, throughputGbps: 12.485 }
    );
    assert.deepEqual(
        parseThroughputMetrics({ Bandwidth: '850 Mb/sec' }),
        { throughputMbps: 850, throughputGbps: 0.85 }
    );
    assert.deepEqual(
        parseThroughputMetrics({ Bandwidth: '500 Kb/sec' }),
        { throughputMbps: 0.5, throughputGbps: 0.0005 }
    );
    assert.deepEqual(
        parseThroughputMetrics({ Bandwidth: 1500 }),
        { throughputMbps: 1500, throughputGbps: 1.5 }
    );

    // Historical latency-only rows and malformed values return nulls cleanly
    assert.deepEqual(
        parseThroughputMetrics({ Latency: '120 us' }),
        { throughputMbps: null, throughputGbps: null }
    );
    assert.deepEqual(
        parseThroughputMetrics({ Bandwidth: '...' }),
        { throughputMbps: null, throughputGbps: null }
    );
    assert.deepEqual(
        parseThroughputMetrics({ Bandwidth: '-10 Gb/sec' }),
        { throughputMbps: null, throughputGbps: null }
    );
    assert.deepEqual(
        parseThroughputMetrics(null),
        { throughputMbps: null, throughputGbps: null }
    );
});

test('normalizeEntity and region mapping cover all 36 regions.json regions and short codes', () => {
    const regionsJsonPath = path.resolve(__dirname, '..', '..', '..', 'regions.json');
    const configuredRegions = Object.keys(JSON.parse(fs.readFileSync(regionsJsonPath, 'utf8')));
    assert.equal(configuredRegions.length, 36);

    const expectedShortCodes = {
        australiaeast: 'ae',
        belgiumcentral: 'bec',
        brazilsouth: 'brs',
        canadacentral: 'cnc',
        centralindia: 'inc',
        centralus: 'cus',
        chilecentral: 'clc',
        eastasia: 'ea',
        eastus: 'eus',
        eastus2: 'eus2',
        francecentral: 'frc',
        germanywestcentral: 'gwc',
        indonesiacentral: 'idc',
        israelcentral: 'ilc',
        italynorth: 'itn',
        japaneast: 'jpe',
        japanwest: 'jpw',
        koreacentral: 'krc',
        malaysiawest: 'myw',
        mexicocentral: 'mxc',
        newzealandnorth: 'nzn',
        northeurope: 'ne',
        norwayeast: 'nwe',
        polandcentral: 'plc',
        qatarcentral: 'qac',
        southafricanorth: 'san',
        southcentralus: 'scus',
        southeastasia: 'sea',
        spaincentral: 'spc',
        swedencentral: 'sdc',
        switzerlandnorth: 'szn',
        uaenorth: 'uan',
        uksouth: 'uks',
        westeurope: 'we',
        westus2: 'wus2',
        westus3: 'wus3'
    };

    for (const regionSlug of configuredRegions) {
        const shortCode = expectedShortCodes[regionSlug];
        assert.ok(shortCode, `Missing expected short code test entry for ${regionSlug}`);
        assert.equal(SHORT_CODE_TO_REGION[shortCode], regionSlug);
        assert.ok(REGION_DISPLAY_NAMES[regionSlug], `Missing display name for ${regionSlug}`);
        assert.equal(normalizeRegion(shortCode), regionSlug);
        assert.equal(normalizeRegion(regionSlug), regionSlug);
        assert.equal(getRegionDisplayName(shortCode), getRegionDisplayName(regionSlug));
    }

    const normalizedShort = normalizeEntity({
        partitionKey: 'pk-1',
        rowKey: 'frc',
        Source: 'az1',
        Destination: 'az2',
        LatencyUs: 92.4,
        ThroughputGbps: 12.345,
        timestamp: '2026-11-10T10:00:00.000Z'
    });

    assert.equal(normalizedShort.PartitionKey, 'pk-1');
    assert.equal(normalizedShort.RowKey, 'frc');
    assert.equal(normalizedShort.Region, 'francecentral');
    assert.equal(normalizedShort.region, 'francecentral');
    assert.equal(normalizedShort.regionDisplayName, 'France Central');
    assert.equal(normalizedShort.latencyUs, 92.4);
    assert.equal(normalizedShort.throughputGbps, 12.345);
    assert.equal(normalizedShort.throughputMbps, 12345);
    assert.equal(normalizedShort.Latency, '92.4 us');
    assert.equal(normalizedShort.Bandwidth, '12.345 Gb/sec');

    const legacyLatencyOnly = normalizeEntity({
        PartitionKey: 'pk-legacy',
        RowKey: 'inc',
        Source: 'az2',
        Destination: 'az3',
        Latency: '188.0 us',
        Timestamp: '2026-10-01T00:00:00.000Z'
    });
    assert.equal(legacyLatencyOnly.region, 'centralindia');
    assert.equal(legacyLatencyOnly.regionDisplayName, 'Central India');
    assert.equal(legacyLatencyOnly.latencyUs, 188);
    assert.equal(legacyLatencyOnly.throughputMbps, null);
    assert.equal(legacyLatencyOnly.throughputGbps, null);
    assert.equal(legacyLatencyOnly.Bandwidth, null);

    // Guard against Object.prototype property collisions (constructor, __proto__, toString)
    for (const protoKey of ['constructor', '__proto__', 'toString']) {
        const entity = normalizeEntity({ PartitionKey: 'pk-proto', RowKey: protoKey, LatencyUs: 50 });
        assert.equal(typeof entity.Region, 'string');
        assert.equal(entity.Region, protoKey.toLowerCase());
        assert.equal(typeof entity.regionDisplayName, 'string');
        assert.equal(entity.regionDisplayName.includes('[native code]'), false);
    }
});

test('buildTimeFilter builds safe ISO OData filters, supports all, clamps large days, and rejects injection strings', () => {
    const fixedNow = new Date('2026-11-13T12:00:00.000Z');

    // Default 30d when omitted
    assert.equal(
        buildTimeFilter({}, fixedNow),
        "Timestamp ge datetime'2026-10-14T12:00:00.000Z'"
    );
    assert.equal(
        buildTimeFilter(undefined, fixedNow),
        "Timestamp ge datetime'2026-10-14T12:00:00.000Z'"
    );

    // Preset windows
    assert.equal(
        buildTimeFilter({ window: '72h' }, fixedNow),
        "Timestamp ge datetime'2026-11-10T12:00:00.000Z'"
    );
    assert.equal(
        buildTimeFilter({ window: '7d' }, fixedNow),
        "Timestamp ge datetime'2026-11-06T12:00:00.000Z'"
    );
    assert.equal(
        buildTimeFilter({ window: '30d' }, fixedNow),
        "Timestamp ge datetime'2026-10-14T12:00:00.000Z'"
    );
    assert.equal(
        buildTimeFilter({ days: '14' }, fixedNow),
        "Timestamp ge datetime'2026-10-30T12:00:00.000Z'"
    );
    assert.equal(buildTimeFilter({ window: 'all' }, fixedNow), null);
    assert.equal(buildTimeFilter({ window: 'ALL' }, fixedNow), null);
    assert.equal(buildTimeFilter({ days: 'all' }, fixedNow), null);

    // Clamping extreme positive values to 3650 days
    assert.equal(
        buildTimeFilter({ days: '999999' }, fixedNow),
        `Timestamp ge datetime'${new Date(fixedNow.getTime() - 3650 * 86400 * 1000).toISOString()}'`
    );

    // Reject OData injection strings and invalid values
    const maliciousInputs = [
        { window: "30d' or '1' eq '1" },
        { window: "7d' or PartitionKey ne ''" },
        { days: "30' or RowKey eq 'we'" },
        { days: '10; DROP TABLE perf' },
        { window: '-7d' },
        { window: '0d' },
        { days: '0' },
        { days: -5 },
        { window: 'forever' }
    ];

    for (const badQuery of maliciousInputs) {
        assert.throws(
            () => buildTimeFilter(badQuery, fixedNow),
            (err) => err instanceof RangeError && err.statusCode === 400,
            `Expected ${JSON.stringify(badQuery)} to be rejected with HTTP 400 RangeError`
        );
    }
});

test('HTTP handler returns sample fallback dataset with warning when AZURE_STORAGE_ACCOUNT_NAME is unset', async () => {
    const prevEnv = process.env.AZURE_STORAGE_ACCOUNT_NAME;
    delete process.env.AZURE_STORAGE_ACCOUNT_NAME;

    try {
        const ctx = createMockContext();
        await dataHandler(ctx, { query: {} });

        assert.equal(ctx.res.status, 200);
        assert.ok(ctx.warnings.some((msg) => msg.includes('AZURE_STORAGE_ACCOUNT_NAME is not configured')));
        const body = JSON.parse(ctx.res.body);
        assert.equal(Array.isArray(body), true);
        assert.equal(body.length, 2);
        assert.equal(body[0].region, 'westeurope');
        assert.equal(body[1].region, 'northeurope');
    } finally {
        if (prevEnv !== undefined) {
            process.env.AZURE_STORAGE_ACCOUNT_NAME = prevEnv;
        }
    }
});

test('HTTP handler returns 400 on OData injection attempt without querying Table Storage', async () => {
    let clientCalled = false;
    const mockTableClient = {
        listEntities() {
            clientCalled = true;
            throw new Error('Should not be called');
        }
    };

    const ctx = createMockContext();
    await dataHandler(
        ctx,
        { query: { window: "30d' or PartitionKey gt ''" } },
        { tableClient: mockTableClient }
    );

    assert.equal(clientCalled, false);
    assert.equal(ctx.res.status, 400);
    const payload = JSON.parse(ctx.res.body);
    assert.match(payload.error, /Invalid "window" parameter/);
});

test('HTTP handler streams paginated entities from mocked tableClient, honors window=all, and enforces MAX_RESULTS cap', async () => {
    const capturedOptions = [];
    const mockRows = [
        { partitionKey: 'run-1', rowKey: 'we', Source: 'az1', Destination: 'az1', LatencyUs: 64.2, ThroughputGbps: 12.4, timestamp: '2026-08-01T00:00:00.000Z' },
        { partitionKey: 'run-2', rowKey: 'jpe', Source: 'az1', Destination: 'az2', Latency: '155 us', Bandwidth: '11.200 Gb/sec', timestamp: '2026-09-01T00:00:00.000Z' },
        { partitionKey: 'run-3', rowKey: 'eus2', Source: 'az2', Destination: 'az3', LatencyUs: 210.5, ThroughputMbps: 10500, timestamp: '2026-10-01T00:00:00.000Z' }
    ];

    const mockTableClient = {
        listEntities(options) {
            capturedOptions.push(options);
            return (async function* () {
                for (const row of mockRows) {
                    yield row;
                }
            })();
        }
    };

    // 1. window=all omits Timestamp filter and enforces maxResults=2
    const ctxAll = createMockContext();
    await dataHandler(
        ctxAll,
        { query: { window: 'all' } },
        { tableClient: mockTableClient, maxResults: 2 }
    );

    assert.equal(ctxAll.res.status, 200);
    assert.deepEqual(capturedOptions[0], {});
    const parsedAll = JSON.parse(ctxAll.res.body);
    assert.equal(parsedAll.length, 2);
    assert.equal(parsedAll[0].region, 'westeurope');
    assert.equal(parsedAll[1].region, 'japaneast');
    assert.equal(parsedAll[1].regionDisplayName, 'Japan East');

    // 2. window=72h passes exact Timestamp filter
    const fixedNow = new Date('2026-11-13T00:00:00.000Z');
    const ctx72h = createMockContext();
    await dataHandler(
        ctx72h,
        { query: { window: '72h' } },
        { tableClient: mockTableClient, now: fixedNow }
    );

    assert.equal(ctx72h.res.status, 200);
    assert.deepEqual(capturedOptions[1], {
        queryOptions: {
            filter: "Timestamp ge datetime'2026-11-10T00:00:00.000Z'"
        }
    });
    const parsed72h = JSON.parse(ctx72h.res.body);
    assert.equal(parsed72h.length, 3);
    assert.equal(parsed72h[2].region, 'eastus2');
});
