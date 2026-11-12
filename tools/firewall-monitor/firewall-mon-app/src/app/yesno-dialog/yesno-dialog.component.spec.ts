import { ComponentFixture, TestBed } from '@angular/core/testing';
import { MatButtonModule } from '@angular/material/button';
import { MAT_DIALOG_DATA, MatDialogModule, MatDialogRef } from '@angular/material/dialog';
import { vi } from 'vitest';

import { YesnoDialogComponent } from './yesno-dialog.component';

describe('YesnoDialogComponent', () => {
  let component: YesnoDialogComponent;
  let fixture: ComponentFixture<YesnoDialogComponent>;
  let dialogRefMock: { close: ReturnType<typeof vi.fn> };

  beforeEach(async () => {
    dialogRefMock = { close: vi.fn() };

    await TestBed.configureTestingModule({
      imports: [MatDialogModule, MatButtonModule],
      declarations: [YesnoDialogComponent],
      providers: [
        { provide: MatDialogRef, useValue: dialogRefMock },
        {
          provide: MAT_DIALOG_DATA,
          useValue: { title: 'Clear all', description: 'Delete all firewall logs?' }
        }
      ]
    }).compileComponents();

    fixture = TestBed.createComponent(YesnoDialogComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create and display dialog title and description', () => {
    expect(component).toBeTruthy();
    const text = (fixture.nativeElement as HTMLElement).textContent ?? '';
    expect(text).toContain('Clear all');
    expect(text).toContain('Delete all firewall logs?');
  });

  it('should close dialog with boolean decision when button is clicked', () => {
    component.onClickButton(true);
    expect(dialogRefMock.close).toHaveBeenCalledWith(true);

    component.onClickButton(false);
    expect(dialogRefMock.close).toHaveBeenCalledWith(false);
  });
});
