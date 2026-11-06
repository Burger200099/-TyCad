// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Set Scale dialog of the Measure A-B ruler: the length of the ruler that was drawn is known, and so is how long it really is; the scale is the second divided by the
  first. The scale and the actual distance (with its unit, mm or in) follow each other: typing the actual distance or choosing the unit works the scale out, typing the scale
  works out the actual distance.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fmeasurescale;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase;

type

  { TfrmMeasureScale }

  TfrmMeasureScale = class(TfrmBase)
    cbUnits: TComboBox;
    edActual: TEdit;
    edScale: TEdit;
    lblActual: TLabel;
    lblDrawn: TLabel;
    lblHint: TLabel;
    lblScale: TLabel;
    procedure ActualChange(Sender: TObject);
    procedure ScaleChange(Sender: TObject);
  private
    FDrawnMm: Double;
    FBusy: Boolean;
    function UnitMm: Double;
    function GetScale: Double;
  public
    { ADrawnMm: the length of the ruler as drawn, in millimetres; AScale: the scale now }
    procedure Setup(ADrawnMm, AScale: Double);
    property Scale: Double read GetScale;
  end;

implementation

uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmMeasureScale.UnitMm  (function)
  Returns:
    Double - millimetres in one of the chosen unit
  =========================================================================== }
function TfrmMeasureScale.UnitMm: Double;
begin
  if cbUnits.ItemIndex = 1 then
    Result := 25.4
  else
    Result := 1;
end;

{ ===========================================================================
  TfrmMeasureScale.GetScale  (function)
  Returns:
    Double - the scale typed, or 0 when it is not a number above 0
  =========================================================================== }
function TfrmMeasureScale.GetScale: Double;
var
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  if (not TryStrToFloat(Trim(StringReplace(edScale.Text, ',', '.', [])), Result, Fs)) or (Result <= 0) then
    Result := 0;
end;

{ ===========================================================================
  TfrmMeasureScale.Setup  (procedure)
  Parameters:
    ADrawnMm: Double - the length of the ruler as drawn, in millimetres
    AScale: Double - the scale now
  Notes:
    Shows the drawn length, the scale and the actual distance that scale gives (in mm).
  =========================================================================== }
procedure TfrmMeasureScale.Setup(ADrawnMm, AScale: Double);
begin
  FDrawnMm := ADrawnMm;
  FBusy := True;
  try
    lblDrawn.Caption := Format(rsMeasureScaleDrawn, [FormatFloat('0.###', ADrawnMm)]);
    cbUnits.ItemIndex := 0;
    edScale.Text := FormatFloat('0.#####', AScale);
    edActual.Text := FormatFloat('0.###', ADrawnMm * AScale);
  finally
    FBusy := False;
  end;
end;

{ ===========================================================================
  TfrmMeasureScale.ActualChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The actual distance or its unit changed: the scale is the actual distance (in mm) divided by the drawn length.
  =========================================================================== }
procedure TfrmMeasureScale.ActualChange(Sender: TObject);
var
  V: Double;
  Fs: TFormatSettings;
begin
  if FBusy or (FDrawnMm <= 0) then
    Exit;
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  if (not TryStrToFloat(Trim(StringReplace(edActual.Text, ',', '.', [])), V, Fs)) or (V <= 0) then
    Exit;
  FBusy := True;
  try
    edScale.Text := FormatFloat('0.#####', V * UnitMm / FDrawnMm);
  finally
    FBusy := False;
  end;
end;

{ ===========================================================================
  TfrmMeasureScale.ScaleChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The scale was typed: the actual distance is the drawn length times it, in the chosen unit.
  =========================================================================== }
procedure TfrmMeasureScale.ScaleChange(Sender: TObject);
begin
  if FBusy or (GetScale <= 0) then
    Exit;
  FBusy := True;
  try
    edActual.Text := FormatFloat('0.###', FDrawnMm * GetScale / UnitMm);
  finally
    FBusy := False;
  end;
end;

end.
