// SPDX-License-Identifier: LGPL-2.1-or-later
unit FBusDropDown;

{$mode ObjFPC}{$H+}

{ The panel that drops down from the Phases button of the Bus property panel: 1 phase or 3 phase, a separator, and the distance between the wires of a 3-phase bus as 1 to 5
  times the grid, a whole number of grids of its own, or a width of its own in millimetres typed in the box at the foot.

  Unlike the Fill menu it stays open when something is chosen (the choice is applied at once, through OnPick) and closes when something else is clicked, or on Esc.
  The button tells it the bus it is for with SetBus; spacings are in millimetres.

  Licence: LGPL 2.1 or later, as the rest of this port. }

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, LCLType, Math, FDropDownBase, UOptions, consts;

type
  { a choice was made: how many phases (1 or 3) and the distance between the wires in millimetres }
  TBusPickEvent = procedure(Sender: TObject; APhases: Integer; ASpacingMm: Double) of object;

  { TfrmBusDropDown }

  TfrmBusDropDown = class(TfrmDropDownBase)
    edMult: TEdit;
    edSpacing: TEdit;
    lbSpacing: TLabel;
    lbSpacingUnit: TLabel;
    plBack: TPanel;
    plPhases: TPanel;
    plSeparator: TPanel;
    plSpacing: TPanel;
    rbPhase1: TRadioButton;
    rbPhase3: TRadioButton;
    rbSpace1: TRadioButton;
    rbSpace2: TRadioButton;
    rbSpace3: TRadioButton;
    rbSpace4: TRadioButton;
    rbSpace5: TRadioButton;
    rbSpaceMult: TRadioButton;
    rbSpaceCustom: TRadioButton;
    procedure edSpacingKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure edSpacingExit(Sender: TObject);
    procedure edSpacingChange(Sender: TObject);
    procedure PhaseClick(Sender: TObject);
    procedure edMultChange(Sender: TObject);
    procedure edMultExit(Sender: TObject);
    procedure edMultKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SpaceClick(Sender: TObject);
  private
    FPhases: Integer;               // 1 or 3
    FSpacingMm: Double;             // the distance between the wires
    FGridMm: Double;                // the grid, for the multiples
    FUnits: Integer;                // the units of the sheet (not used: the box at the foot is in millimetres)
    FUpdating: Boolean;             // the form is showing a value: the controls' events are not choices
    FOnPick: TBusPickEvent;
    procedure ShowValues;
    procedure Pick;
    function SpaceRadio(AIndex: Integer): TRadioButton;
    function MmOfText(const S: String; out Mm: Double): Boolean;
    function MultOfText(const S: String; out N: Integer): Boolean;
    procedure ApplyMult;
    function TextOfMm(Mm: Double): String;
  public
    procedure SetBus(APhases: Integer; ASpacingMm, AGridMm: Double; AUnits: Integer);
    { the same as the person's clicks, for the self-test script: 'phase 1|3', 'space 1..5', 'mult <whole number>', 'custom <millimetres>' }
    function Act(const AAct: String): String;
    property Phases: Integer read FPhases;
    property SpacingMm: Double read FSpacingMm;
    property OnPick: TBusPickEvent read FOnPick write FOnPick;
  end;

var
  frmBusDropDown: TfrmBusDropDown;

implementation


uses UStrings;

{$R *.lfm}

const
  Multiples = 5;       // the radio buttons for 1 to 5 grids

{ ===========================================================================
  TfrmBusDropDown.SpaceRadio  (function)
  Parameters:
    AIndex: Integer - whole number
  Returns:
    TRadioButton
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmBusDropDown.SpaceRadio(AIndex: Integer): TRadioButton;
begin
  case AIndex of
    1: Result := rbSpace1;
    2: Result := rbSpace2;
    3: Result := rbSpace3;
    4: Result := rbSpace4;
  else
    Result := rbSpace5;
  end;
end;

{ ===========================================================================
  TfrmBusDropDown.MmOfText  (function)
  Parameters:
    const S: String - text
    out Mm: Double - number (out: set by the call)
  Returns:
    Boolean
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmBusDropDown.MmOfText(const S: String; out Mm: Double): Boolean;
begin
  Result := ParseNumber(S, Mm) and (Mm > 0);
end;

{ ===========================================================================
  TfrmBusDropDown.MultOfText  (function)
  Parameters:
    const S: String - text
    out N: Integer - whole number (out: set by the call)
  Returns:
    Boolean
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmBusDropDown.MultOfText(const S: String; out N: Integer): Boolean;
begin
  N := StrToIntDef(Trim(S), 0);
  Result := (N >= 1) and (N <= 1000);
end;

{ ===========================================================================
  TfrmBusDropDown.TextOfMm  (function)
  Parameters:
    Mm: Double - number
  Returns:
    String
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmBusDropDown.TextOfMm(Mm: Double): String;
begin
  Result := NumberText(Mm);
end;

{ ===========================================================================
  TfrmBusDropDown.SetBus  (procedure)
  Parameters:
    APhases: Integer - whole number
    ASpacingMm: Double - number
    AGridMm: Double - number
    AUnits: Integer - whole number
  Notes:
    Tell the panel before it is shown. A whole number of grids that equals the spacing is ticked
    (1 to 5 on its own radio button, a larger one as the custom multiplier); when it is not a
    whole number of grids, Custom spacing is.
  =========================================================================== }
procedure TfrmBusDropDown.SetBus(APhases: Integer; ASpacingMm, AGridMm: Double; AUnits: Integer);
begin
  if APhases = 3 then
    FPhases := 3
  else
    FPhases := 1;
  FSpacingMm := ASpacingMm;
  FGridMm := AGridMm;
  FUnits := AUnits;
  ShowValues;
end;

{ ===========================================================================
  TfrmBusDropDown.ShowValues  (procedure)
  Parameters:  none
  Notes:
    Shows the phases, the multiples of the grid (with the one that matches ticked) and the box
    at the foot.
  =========================================================================== }
procedure TfrmBusDropDown.ShowValues;
var
  i, M: Integer;
begin
  FUpdating := True;
  try
    rbPhase1.Checked := FPhases = 1;
    rbPhase3.Checked := FPhases = 3;
    M := 0;      { (the whole number of grids the spacing is, 0 when it is not one) }
    if FGridMm > 0 then
    begin
      i := Round(FSpacingMm / FGridMm);
      if (i >= 1) and (i <= 1000) and (Abs(FSpacingMm - i * FGridMm) < 0.001) then
        M := i;
    end;
    for i := 1 to Multiples do
    begin
      SpaceRadio(i).Caption := Format(rsXGrid, [i]);
      SpaceRadio(i).Checked := M = i;
    end;
    rbSpaceMult.Checked := M > Multiples;
    rbSpaceCustom.Checked := M = 0;
    if M > Multiples then
      edMult.Text := IntToStr(M);
    edSpacing.Text := TextOfMm(FSpacingMm);
  finally
    FUpdating := False;
  end;
end;

{ ===========================================================================
  TfrmBusDropDown.Pick  (procedure)
  Parameters:  none
  Notes:
    Hands the phases and the spacing as they stand to OnPick. The panel stays open.
  =========================================================================== }
procedure TfrmBusDropDown.Pick;
begin
  if Assigned(FOnPick) then
    FOnPick(Self, FPhases, FSpacingMm);
end;

{ ===========================================================================
  TfrmBusDropDown.PhaseClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfrmBusDropDown.PhaseClick(Sender: TObject);
begin
  if FUpdating then
    Exit;
  if Sender = rbPhase3 then
    FPhases := 3
  else
    FPhases := 1;
  Pick;
end;

{ ===========================================================================
  TfrmBusDropDown.SpaceClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    A multiple of the grid gives that distance and shows it in the box at the foot; the custom
    multiplier and Custom spacing take what is in their boxes (when it is a number).
  =========================================================================== }
procedure TfrmBusDropDown.SpaceClick(Sender: TObject);
var
  i: Integer;
  Mm: Double;
begin
  if FUpdating then
    Exit;
  if Sender = rbSpaceMult then
  begin
    ApplyMult;
    edMult.SetFocus;
    Exit;
  end;
  if Sender = rbSpaceCustom then
  begin
    if MmOfText(edSpacing.Text, Mm) then
    begin
      FSpacingMm := Mm;
      Pick;
    end;
    edSpacing.SetFocus;
    Exit;
  end;
  for i := 1 to Multiples do
    if Sender = SpaceRadio(i) then
    begin
      FSpacingMm := i * FGridMm;
      FUpdating := True;
      try
        edSpacing.Text := TextOfMm(FSpacingMm);
      finally
        FUpdating := False;
      end;
      Pick;
    end;
end;

{ ===========================================================================
  TfrmBusDropDown.ApplyMult  (procedure)
  Parameters:  none
  Notes:
    Takes the whole number of grids in the multiplier box as the spacing (when it is a whole
    number from 1 to 1000), shows it in the box at the foot and tells OnPick.
  =========================================================================== }
procedure TfrmBusDropDown.ApplyMult;
var
  N: Integer;
begin
  if (FGridMm > 0) and MultOfText(edMult.Text, N) then
  begin
    FSpacingMm := N * FGridMm;
    FUpdating := True;
    try
      edSpacing.Text := TextOfMm(FSpacingMm);
    finally
      FUpdating := False;
    end;
    Pick;
  end;
end;

{ ===========================================================================
  TfrmBusDropDown.edMultChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Typing in the box makes the custom multiplier the ticked one (the number is applied by Enter
    or by leaving the box).
  =========================================================================== }
procedure TfrmBusDropDown.edMultChange(Sender: TObject);
var
  i: Integer;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    for i := 1 to Multiples do
      SpaceRadio(i).Checked := False;
    rbSpaceMult.Checked := True;
  finally
    FUpdating := False;
  end;
end;

{ ===========================================================================
  TfrmBusDropDown.edMultExit  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Applies the number typed when it is a whole number of grids that is not the spacing already;
    otherwise the panel shows the spacing the bus has again.
  =========================================================================== }
procedure TfrmBusDropDown.edMultExit(Sender: TObject);
var
  N: Integer;
begin
  if FUpdating then
    Exit;
  if (FGridMm > 0) and MultOfText(edMult.Text, N) and (Abs(N * FGridMm - FSpacingMm) > 0.0005) then
    ApplyMult;
  ShowValues;
end;

{ ===========================================================================
  TfrmBusDropDown.edMultKeyDown  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    var Key: Word - key code (in/out: changed by the call)
    Shift: TShiftState - modifier keys held down
  Notes:
    Enter applies the number typed.
  =========================================================================== }
procedure TfrmBusDropDown.edMultKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    edMultExit(Sender);
    Key := 0;
  end;
end;

{ ===========================================================================
  TfrmBusDropDown.edSpacingChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Typing in the box makes Custom the ticked one (the width is applied by Enter or by leaving
    the box).
  =========================================================================== }
procedure TfrmBusDropDown.edSpacingChange(Sender: TObject);
var
  i: Integer;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    for i := 1 to Multiples do
      SpaceRadio(i).Checked := False;
    rbSpaceMult.Checked := False;
    rbSpaceCustom.Checked := True;
  finally
    FUpdating := False;
  end;
end;

{ ===========================================================================
  TfrmBusDropDown.edSpacingKeyDown  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    var Key: Word - key code (in/out: changed by the call)
    Shift: TShiftState - modifier keys held down
  Notes:
    Enter applies what was typed (when it is a number above zero).
  =========================================================================== }
procedure TfrmBusDropDown.edSpacingKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    edSpacingExit(Sender);
    Key := 0;
  end;
end;

{ ===========================================================================
  TfrmBusDropDown.edSpacingExit  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Applies the width typed, when it is a number above zero and not what the bus has already;
    otherwise the box goes back to the spacing the bus has.
  =========================================================================== }
procedure TfrmBusDropDown.edSpacingExit(Sender: TObject);
var
  Mm: Double;
begin
  if FUpdating then
    Exit;
  if MmOfText(edSpacing.Text, Mm) then
  begin
    if Abs(Mm - FSpacingMm) > 0.0005 then
    begin
      FSpacingMm := Mm;
      Pick;
    end;
  end;
  ShowValues;
end;

{ ===========================================================================
  TfrmBusDropDown.Act  (function)
  Parameters:
    const AAct: String - text
  Returns:
    String
  Notes:
    For the self-test script: does what a click on the radio button, or typing in the box and
    Enter, does.
  =========================================================================== }
function TfrmBusDropDown.Act(const AAct: String): String;
var
  Key: Word;
  K: Integer;
begin
  if Copy(AAct, 1, 6) = 'phase ' then
  begin
    if Trim(Copy(AAct, 7, 9)) = '3' then
    begin
      rbPhase3.Checked := True; PhaseClick(rbPhase3);
    end
    else
    begin
      rbPhase1.Checked := True; PhaseClick(rbPhase1);
    end;
  end
  else if Copy(AAct, 1, 6) = 'space ' then
  begin
    K := StrToIntDef(Trim(Copy(AAct, 7, 9)), 1);
    SpaceRadio(Max(1, Min(Multiples, K))).Checked := True;
    SpaceClick(SpaceRadio(Max(1, Min(Multiples, K))));
  end
  else if Copy(AAct, 1, 5) = 'mult ' then
  begin
    edMult.Text := Trim(Copy(AAct, 6, MaxInt));
    Key := VK_RETURN;
    edMultKeyDown(edMult, Key, []);
  end
  else if Copy(AAct, 1, 7) = 'custom ' then
  begin
    edSpacing.Text := Trim(Copy(AAct, 8, MaxInt));
    Key := VK_RETURN;
    edSpacingKeyDown(edSpacing, Key, []);
  end;
  Result := Format('visible=%d phases=%d spacing=%s radios=%d%d%d%d%d%d%d%d%d mult=[%s] edit=[%s]', [Ord(Visible), FPhases, NumberText(FSpacingMm), Ord(rbPhase1.Checked), Ord(rbPhase3.Checked),
    Ord(rbSpace1.Checked), Ord(rbSpace2.Checked), Ord(rbSpace3.Checked), Ord(rbSpace4.Checked), Ord(rbSpace5.Checked), Ord(rbSpaceMult.Checked), Ord(rbSpaceCustom.Checked), edMult.Text, edSpacing.Text]);
end;

end.
