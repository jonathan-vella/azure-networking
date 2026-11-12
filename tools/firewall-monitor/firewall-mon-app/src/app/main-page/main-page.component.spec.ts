import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { FormsModule } from '@angular/forms';
import { NoopAnimationsModule } from '@angular/platform-browser/animations';
import { RouterModule } from '@angular/router';
import { ScrollingModule } from '@angular/cdk/scrolling';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatChipsModule } from '@angular/material/chips';
import { MatDialogModule } from '@angular/material/dialog';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatSnackBarModule } from '@angular/material/snack-bar';
import { MatTableModule } from '@angular/material/table';
import { MatToolbarModule } from '@angular/material/toolbar';
import { MatTooltipModule } from '@angular/material/tooltip';
import { TableVirtualScrollModule } from 'ng-table-virtual-scroll';
import { vi } from 'vitest';

import { MainPageComponent } from './main-page.component';
import { ResizeColumnDirective } from '../directives/resize-column.directive';
import { DemoSourceService } from '../services/demo-source.service';
import { EventHubSourceService } from '../services/event-hub-source.service';
import { FlagsService } from '../services/flags.service';
import { LoggingService } from '../services/logging.service';
import { FirewallDataRow, IFirewallSource, ModelService } from '../services/model.service';
import { SearchFieldService } from '../services/search-field.service';

describe('MainPageComponent', () => {
  let component: MainPageComponent;
  let fixture: ComponentFixture<MainPageComponent>;
  let mockSource: IFirewallSource;
  let searchFieldService: SearchFieldService;

  beforeEach(async () => {
    mockSource = {
      skippedRows: 0,
      start: vi.fn(),
      pause: vi.fn(),
      stop: vi.fn(),
      clear: vi.fn()
    };

    const loggingStub = {
      logTrace: vi.fn(),
      logEvent: vi.fn(),
      logException: vi.fn(),
      logMetric: vi.fn(),
      logPageView: vi.fn()
    };

    await TestBed.configureTestingModule({
      schemas: [CUSTOM_ELEMENTS_SCHEMA],
      imports: [
        FormsModule,
        NoopAnimationsModule,
        RouterModule.forRoot([]),
        ScrollingModule,
        TableVirtualScrollModule,
        MatButtonModule,
        MatCardModule,
        MatChipsModule,
        MatDialogModule,
        MatFormFieldModule,
        MatInputModule,
        MatSnackBarModule,
        MatTableModule,
        MatToolbarModule,
        MatTooltipModule
      ],
      declarations: [MainPageComponent, ResizeColumnDirective],
      providers: [
        SearchFieldService,
        { provide: LoggingService, useValue: loggingStub },
        { provide: ModelService, useValue: { demoMode: true, eventHubConnection: '', eventHubConsumerGroup: '$Default' } },
        { provide: DemoSourceService, useValue: mockSource },
        { provide: EventHubSourceService, useValue: mockSource },
        { provide: FlagsService, useValue: { getFlagFromIP: vi.fn().mockReturnValue(undefined) } }
      ]
    }).compileComponents();

    searchFieldService = TestBed.inject(SearchFieldService);
    fixture = TestBed.createComponent(MainPageComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create and start the configured firewall source', () => {
    expect(component).toBeTruthy();
    expect(mockSource.start).toHaveBeenCalledTimes(1);
  });

  it('should classify RFC1918 internal vs external IPv4 addresses and non-IP FQDNs', () => {
    expect(component.isInternalIP('10.13.1.4')).toBe(true);
    expect(component.isInternalIP('172.16.0.10')).toBe(true);
    expect(component.isInternalIP('172.32.0.10')).toBe(false);
    expect(component.isInternalIP('192.168.1.50')).toBe(true);
    expect(component.isExternalIP('20.31.19.13')).toBe(true);
    expect(component.isExternalIP('10.0.0.4')).toBe(false);
    expect(component.isIP('winatp-gw-cus3.microsoft.com')).toBe(false);
  });

  it('should filter incoming firewall rows according to SearchFieldService parameters', () => {
    const rows: FirewallDataRow[] = [
      {
        rowid: '1',
        time: new Date().toISOString(),
        category: 'NetworkRule',
        protocol: 'TCP',
        sourceip: '10.0.1.4',
        srcport: '51234',
        targetip: '20.50.1.10',
        targetport: '443',
        moreInfo: '',
        action: 'Allow',
        policy: 'corp-policy»net-rcg»allow-https',
        dataRow: {}
      },
      {
        rowid: '2',
        time: new Date().toISOString(),
        category: 'ApplicationRule',
        protocol: 'HTTPS',
        sourceip: '10.0.2.8',
        srcport: '54321',
        targetip: 'malicious.example.com',
        targetport: '443',
        moreInfo: '',
        action: 'Deny',
        policy: 'Default Action',
        dataRow: {}
      }
    ];

    searchFieldService.setPrompt('deny malicious');
    mockSource.onDataArrived?.(rows);

    expect(component.totalRows).toBe(2);
    expect(component.visibleRows).toBe(1);
    expect(component.dataSource.filteredData[0].rowid).toBe('2');
  });
});
