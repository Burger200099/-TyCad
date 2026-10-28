// SPDX-License-Identifier: LGPL-2.1-or-later
unit FPropTester;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Fbase, QPropWire,
  QPropText, QPowerSym, QRectCircle, QCloudNote, QLibPanel, QMeasure, QPropNote,
  Types, StdCtrls;

type

  { TfrmPropertyTester }

  TfrmPropertyTester = class(TFrmBase)
    fmCloudRect1: TfmCloudRect;
    fmMeasure1: TfmMeasure;
    fmPower1: TfmPower;
    fmPropNote1: TfmPropNote;
    fmPropRibbonWire1: TfmPropRibbonWire;
    fmPropText1: TfmPropText;
    fmRectCircle1: TfmRectCircle;
    procedure FormActivate(Sender: TObject);
  private

  public

  end;

var
  frmPropertyTester: TfrmPropertyTester;

implementation

{$R *.lfm}

{ ===========================================================================
  TfrmPropertyTester.FormActivate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TfrmPropertyTester
  =========================================================================== }
procedure TfrmPropertyTester.FormActivate(Sender: TObject);
begin
  fmPropText1.AfterCreate;
  fmMeasure1.AfterCreate;
  fmPropNote1.AfterCreate;
end;


end.

