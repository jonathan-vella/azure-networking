import { vi } from 'vitest';
import { EventHubSourceService } from './event-hub-source.service';
import { LoggingService } from './logging.service';
import { AzureFirewallRecord, FirewallDataRow, ModelService } from './model.service';

describe('EventHubSourceService structured log parsing', () => {
  let service: EventHubSourceService;

  beforeEach(() => {
    const loggingStub = {
      logEvent: vi.fn(),
      logException: vi.fn(),
      logTrace: vi.fn()
    } as unknown as LoggingService;

    const modelStub = {
      demoMode: false,
      eventHubConnection: '',
      eventHubConsumerGroup: '$Default'
    } as unknown as ModelService;

    service = new EventHubSourceService(loggingStub, modelStub);
  });

  it('should parse resource-specific AZFWNetworkRule structured logs', () => {
    const record: AzureFirewallRecord = {
      category: 'AZFWNetworkRule',
      time: new Date('2026-11-12T18:00:00.000Z'),
      resourceId: '/SUBSCRIPTIONS/00000000-0000-0000-0000-000000000000/RESOURCEGROUPS/RG-HUB/PROVIDERS/MICROSOFT.NETWORK/AZUREFIREWALLS/AFW-HUB',
      operationName: 'AzureFirewallNetworkRuleLog',
      properties: {
        msg: '',
        Protocol: 'TCP',
        SourceIp: '10.1.0.4',
        SourcePort: '52100',
        DestinationIp: '10.2.0.10',
        DestinationPort: '443',
        Action: 'Allow',
        Policy: 'afw-policy',
        RuleCollectionGroup: 'CoreConnectivity',
        RuleCollection: 'SpokeToSpoke',
        Rule: 'AllowHttps',
        ActionReason: ''
      }
    };

    const row: FirewallDataRow = (service as any).parseAzureFirewallRule(record);

    expect(row.category).toBe('NetworkRule');
    expect(row.protocol).toBe('TCP');
    expect(row.sourceip).toBe('10.1.0.4');
    expect(row.srcport).toBe('52100');
    expect(row.targetip).toBe('10.2.0.10');
    expect(row.targetport).toBe('443');
    expect(row.action).toBe('Allow');
    expect(row.policy).toBe('afw-policy»CoreConnectivity»SpokeToSpoke»AllowHttps');
  });

  it('should parse AZFWIdpsSignature and AZFWDnsQuery structured logs', () => {
    const idpsRecord: AzureFirewallRecord = {
      category: 'AZFWIdpsSignature',
      time: new Date('2026-11-12T18:01:00.000Z'),
      resourceId: '/SUBSCRIPTIONS/00000000-0000-0000-0000-000000000000/RESOURCEGROUPS/RG-HUB/PROVIDERS/MICROSOFT.NETWORK/AZUREFIREWALLS/AFW-HUB',
      operationName: 'AzureFirewallIdpsLog',
      properties: {
        msg: '',
        Protocol: 'TCP',
        SourceIp: '10.12.3.6',
        SourcePort: '44592',
        DestinationIp: '198.51.100.25',
        DestinationPort: '80',
        Action: 'Deny',
        SignatureId: '2008989',
        Category: 'Attempted Information Leak',
        Description: 'Suspicious HTTP Host',
        Severity: '1'
      }
    };

    const idpsRow: FirewallDataRow = (service as any).parseAzureFirewallRule(idpsRecord);
    expect(idpsRow.category).toBe('IdpsSignature');
    expect(idpsRow.action).toBe('Deny');
    expect(idpsRow.moreInfo).toContain('SEV:1');
    expect(idpsRow.moreInfo).toContain('2008989');

    const dnsRecord: AzureFirewallRecord = {
      category: 'AZFWDnsQuery',
      time: new Date('2026-11-12T18:02:00.000Z'),
      resourceId: '/SUBSCRIPTIONS/00000000-0000-0000-0000-000000000000/RESOURCEGROUPS/RG-HUB/PROVIDERS/MICROSOFT.NETWORK/AZUREFIREWALLS/AFW-HUB',
      operationName: 'AzureFirewallDnsQueryLog',
      properties: {
        msg: '',
        SourceIp: '10.12.3.6',
        SourcePort: '17312',
        QueryId: '10433',
        QueryType: 'A',
        QueryClass: 'IN',
        QueryName: 'learn.microsoft.com.',
        Protocol: 'udp',
        ResponseCode: 'NOERROR',
        ResponseFlags: 'qr,rd,ra',
        ErrorNumber: '0',
        ErrorMessage: ''
      }
    };

    const dnsRow: FirewallDataRow = (service as any).parseAzureFirewallRule(dnsRecord);
    expect(dnsRow.category).toBe('AzDnsQuery');
    expect(dnsRow.protocol).toBe('udp');
    expect(dnsRow.moreInfo).toContain('learn.microsoft.com.');
    expect(dnsRow.moreInfo).toContain('NOERROR');
  });
});
