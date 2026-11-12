import { vi } from 'vitest';
import { PromptType, SearchFieldService } from './search-field.service';
import { LoggingService } from './logging.service';
import { ModelService } from './model.service';

describe('SearchFieldService', () => {
  let service: SearchFieldService;
  let loggingStub: Pick<LoggingService, 'logTrace'>;

  beforeEach(() => {
    loggingStub = { logTrace: vi.fn() };
    service = new SearchFieldService(
      loggingStub as LoggingService,
      {} as ModelService
    );
  });

  it('should split classic prompts into lowercase fulltext tokens and ignore extra spaces', () => {
    service.setPrompt('  AZFWNetworkRule   Deny  10.13.1.4 ');

    expect(service.getPrompt()).toBe('  AZFWNetworkRule   Deny  10.13.1.4 ');
    expect(service.searchParams.fulltext).toEqual(['azfwnetworkrule', 'deny', '10.13.1.4']);
  });

  it('should preserve time filters on default resetParams and clear them when includeTimeFilter is true', () => {
    service.setLastMinutes(15);
    service.setPrompt('tcp');
    expect(service.searchParams.lastminutes).toBe(15);

    service.resetParams();
    expect(service.searchParams.fulltext).toEqual([]);
    expect(service.searchParams.lastminutes).toBe(15);

    service.resetParams({ includeTimeFilter: true });
    expect(service.searchParams.lastminutes).toBe(0);
    expect(service.searchParams.startdate).toBe('');
    expect(service.searchParams.enddate).toBe('');
  });

  it('should filter timestamps accurately using setLastMinutes', () => {
    service.setLastMinutes(10);

    const twoMinutesAgo = new Date(Date.now() - 2 * 60_000).toISOString();
    const thirtyMinutesAgo = new Date(Date.now() - 30 * 60_000).toISOString();

    expect(service.isTimestampWithinFilter(twoMinutesAgo)).toBe(true);
    expect(service.isTimestampWithinFilter(thirtyMinutesAgo)).toBe(false);
    expect(service.isTimestampWithinFilter('')).toBe(false);
  });

  it('should parse ChatGPT JSON filter responses from /api/chat', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      status: 200,
      text: async () => JSON.stringify({
        json: JSON.stringify({
          fulltext: [],
          startdate: '',
          enddate: '',
          lastminutes: 5,
          category: ['networkrule'],
          protocol: ['tcp'],
          source: [],
          target: [],
          action: ['deny'],
          policy: [],
          moreinfo: []
        }),
        message: 'I am currently showing denied TCP NetworkRule events from the last 5 minutes.'
      })
    } as Response);

    try {
      service.promptType = PromptType.Chatgpt;
      service.setPrompt('show denied tcp network rules from last 5 minutes');
      await service.parsePrompt();

      expect(service.isThinking).toBe(false);
      expect(service.searchParams.lastminutes).toBe(5);
      expect(service.searchParams.category).toEqual(['networkrule']);
      expect(service.searchParams.protocol).toEqual(['tcp']);
      expect(service.searchParams.action).toEqual(['deny']);
      expect(service.getPromptAnswer()).toContain('denied TCP NetworkRule');
    } finally {
      fetchSpy.mockRestore();
    }
  });
});
