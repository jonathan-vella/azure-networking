import { EncryptionService } from './encryption.service';

describe('EncryptionService', () => {
  let service: EncryptionService;

  beforeEach(() => {
    service = new EncryptionService();
  });

  it('should encrypt and decrypt an Event Hub connection string round-trip', () => {
    const sampleValue = 'Endpoint=sb://fwmon.servicebus.windows.net/;SharedAccessKeyName=fwmonkey;SharedAccessKey=placeholder;EntityPath=fwmonhub';
    const encrypted = service.encrypt(sampleValue);

    expect(encrypted).not.toEqual(sampleValue);
    expect(encrypted.length).toBeGreaterThan(0);
    expect(service.decrypt(encrypted)).toEqual(sampleValue);
  });

  it('should round-trip an empty string cleanly', () => {
    const encrypted = service.encrypt('');
    expect(service.decrypt(encrypted)).toEqual('');
  });
});
