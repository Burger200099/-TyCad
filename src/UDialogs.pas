// SPDX-License-Identifier: LGPL-2.1-or-later
{ The program's dialogs, built in code: New Document (with every standard paper size) and the
  properties of a ladder rail object.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UDialogs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, Graphics, Math, UDPoint,
  UDrawingObjects, UDesign, UPaper;

type
  { ---- New Document ---- }
{  TNewDocForm = class(TForm)
  private
    FFamily: TComboBox;
    FPapers: TListBox;
    FOrient: TRadioGroup;
    FTitle, FAuthor, FOrg, FDocNo, FMargin: TEdit;
    FBorder, FAuto: TCheckBox;
    FInfo: TLabel;
    FIndexes: array of Integer; // paper table index of each list row
    procedure FamilyChange(Sender: TObject);
    procedure PaperChange(Sender: TObject);
    procedure FillPapers;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    procedure SelectPaper(const AName: String; ALandscape: Boolean);
    { A new design with one sheet set up from the dialog's choices }
    function BuildDesign: TDesignFile;
    function PaperIndex: Integer;
    function Landscape: Boolean;
  end;}

  { ---- ladder rails ---- }
  TLadderForm = class(TForm)
  private
    FLeft, FRight, FWidth: TEdit;
    FX1, FX2, FY1, FY2: TEdit;
    FLadder: TDrawLadder;
    function NumField(E: TEdit; Default: Integer): Integer;
    function MmField(E: TEdit; Default: Double): Double;
  public
    constructor CreateFor(AOwner: TComponent; ALadder: TDrawLadder);
    { Copy the dialog's values into the ladder; False when something is not a number }
    function Apply: Boolean;
  end;

function EditLadder(AOwner: TComponent; ALadder: TDrawLadder): Boolean;

implementation

{ ===========================================================================
  MakeLabel  (function)
  Parameters:
    AParent: TWinControl - where it goes
    const ACaption: String - its text
    ALeft: Integer - x position
    ATop: Integer - y position
  Returns:
    TLabel - the label
  Notes:
    Creates a label on a parent control at a position.
  =========================================================================== }
function MakeLabel(AParent: TWinControl; const ACaption: String; ALeft, ATop: Integer): TLabel;
begin
  Result := TLabel.Create(AParent);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := ATop;
end;

{ ===========================================================================
  MakeEdit  (function)
  Parameters:
    AParent: TWinControl - where it goes
    ALeft: Integer - x
    ATop: Integer - y
    AWidth: Integer - width
    const AText: String - initial text
  Returns:
    TEdit - the edit box
  Notes:
    Creates a single-line edit box.
  =========================================================================== }
function MakeEdit(AParent: TWinControl; ALeft, ATop, AWidth: Integer; const AText: String): TEdit;
begin
  Result := TEdit.Create(AParent);
  Result.Parent := AParent;
  Result.SetBounds(ALeft, ATop, AWidth, 24);
  Result.Text := AText;
end;

{ ===========================================================================
  MakeButton  (function)
  Parameters:
    AParent: TWinControl - where it goes
    const ACaption: String - its text
    ALeft: Integer - x
    ATop: Integer - y
    AResult: Integer - modal result such as mrOK or mrCancel
  Returns:
    TButton - the button
  Notes:
    Creates a button that closes a dialog with the given result.
  =========================================================================== }
function MakeButton(AParent: TWinControl; const ACaption: String; ALeft, ATop, AResult: Integer): TButton;
begin
  Result := TButton.Create(AParent);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.SetBounds(ALeft, ATop, 90, 28);
  Result.ModalResult := AResult;
end;

{ ---------------------------------------------------------------- New Document }

{ ===========================================================================
  TNewDocForm.CreateNew  (constructor)
  Parameters:
    AOwner: TComponent - owner of the dialog
    Num: Integer - unused (form number)
  Notes:
    Builds the New Document dialog in code: paper family and size lists, orientation, border and
    automatic sheet numbering options, and title-block fields. Starts with ISO A4 landscape
    selected.
  =========================================================================== }
{constructor TNewDocForm.CreateNew(AOwner: TComponent; Num: Integer);
var
  i: Integer;
  Fam: String;
  Seen: TStringList;
  Btn: TButton;
begin
  inherited CreateNew(AOwner, Num);
  Caption := 'New Document';
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  ClientWidth := 700;
  ClientHeight := 540;

  MakeLabel(Self, 'Paper family:', 16, 16);
  FFamily := TComboBox.Create(Self);
  FFamily.Parent := Self;
  FFamily.SetBounds(16, 36, 200, 24);
  FFamily.Style := csDropDownList;
  FFamily.Items.Add('All sizes');
  Seen := TStringList.Create;
  try
    for i := 0 to PaperCount - 1 do
    begin
      Fam := PaperInfo(i).Family;
      if Seen.IndexOf(Fam) < 0 then begin Seen.Add(Fam); FFamily.Items.Add(Fam); end;
    end;
  finally
    Seen.Free;
  end;
  FFamily.ItemIndex := 0;
  FFamily.OnChange := @FamilyChange;

  MakeLabel(Self, 'Paper size:', 16, 70);
  FPapers := TListBox.Create(Self);
  FPapers.Parent := Self;
  FPapers.SetBounds(16, 90, 450, 300);
  FPapers.OnClick := @PaperChange;

  FOrient := TRadioGroup.Create(Self);
  FOrient.Parent := Self;
  FOrient.SetBounds(484, 90, 200, 76);
  FOrient.Caption := 'Orientation';
  FOrient.Items.Add('Landscape');
  FOrient.Items.Add('Portrait');
  FOrient.ItemIndex := 0;
  FOrient.OnClick := @PaperChange;

  Btn := MakeButton(Self, 'OK', 330, 214, mrOK);
  Btn.Default := True;
  MakeButton(Self, 'Cancel', 434, 214, mrCancel);
end;

{ ===========================================================================
  TNewDocForm.FillPapers  (procedure)
  Parameters:  none
  Notes:
    Fills the size list with the papers of the chosen family (or all sizes) and selects the
    first.
  =========================================================================== }
procedure TNewDocForm.FillPapers;
var
  i: Integer;
  Fam: String;
begin
  FPapers.Items.Clear;
  SetLength(FIndexes, 0);
  if FFamily.ItemIndex <= 0 then
    Fam := ''
  else
    Fam := FFamily.Items[FFamily.ItemIndex];
  for i := 0 to PaperCount - 1 do
    if (Fam = '') or (PaperInfo(i).Family = Fam) then
    begin
      FPapers.Items.Add(PaperDescription(i));
      SetLength(FIndexes, Length(FIndexes) + 1);
      FIndexes[High(FIndexes)] := i;
    end;
  if FPapers.Count > 0 then
    FPapers.ItemIndex := 0;
  PaperChange(nil);
end;

{ ===========================================================================
  TNewDocForm.FamilyChange  (procedure)
  Parameters:
    Sender: TObject - the family combo box
  Notes:
    Event handler: the family changed, so refill the size list.
  =========================================================================== }
procedure TNewDocForm.FamilyChange(Sender: TObject);
begin
  FillPapers;
end;

{ ===========================================================================
  TNewDocForm.PaperIndex  (function)
  Parameters:  none
  Returns:
    Integer - index in the paper table
  Notes:
    The paper table index of the selected size (ISO A4 when nothing is selected).
  =========================================================================== }
function TNewDocForm.PaperIndex: Integer;
begin
  if (FPapers.ItemIndex >= 0) and (FPapers.ItemIndex <= High(FIndexes)) then
    Result := FIndexes[FPapers.ItemIndex]
  else
    Result := PaperIndexByName('ISO A4');
end;

{ ===========================================================================
  TNewDocForm.Landscape  (function)
  Parameters:  none
  Returns:
    Boolean - True for landscape, False for portrait
  Notes:
    Whether landscape is chosen.
  =========================================================================== }
function TNewDocForm.Landscape: Boolean;
begin
  Result := FOrient.ItemIndex <> 1;
end;

{ ===========================================================================
  TNewDocForm.PaperChange  (procedure)
  Parameters:
    Sender: TObject - the list or orientation control
  Notes:
    Event handler: shows the selected paper's name and page size in internal units.
  =========================================================================== }
procedure TNewDocForm.PaperChange(Sender: TObject);
var
  W, H: Integer;
begin
  PaperUnits(PaperIndex, Landscape, W, H);
  FInfo.Caption := Format('%s'#10#10'Page: %d x %d units'#10'(0.2 mm per unit)', [PaperInfo(PaperIndex).Name, W, H]);
end;

{ ===========================================================================
  TNewDocForm.SelectPaper  (procedure)
  Parameters:
    const AName: String - paper name
    ALandscape: Boolean - True for landscape
  Notes:
    Selects a paper and orientation in the dialog (used for defaults and by scripts).
  =========================================================================== }
procedure TNewDocForm.SelectPaper(const AName: String; ALandscape: Boolean);
var
  Idx, k: Integer;
begin
  FFamily.ItemIndex := 0;
  FillPapers;
  Idx := PaperIndexByName(AName);
  for k := 0 to High(FIndexes) do
    if FIndexes[k] = Idx then
      FPapers.ItemIndex := k;
  if ALandscape then
    FOrient.ItemIndex := 0
  else
    FOrient.ItemIndex := 1;
  PaperChange(nil);
end;

{ ===========================================================================
  TNewDocForm.BuildDesign  (function)
  Parameters:  none
  Returns:
    TDesignFile - the new design; the caller owns it
  Notes:
    Creates the new design from the dialog's choices: one sheet with the paper size and
    orientation, title-block text, automatic sheet numbers, border with margin, and a first
    revision "A - Initial issue".
  =========================================================================== }
function TNewDocForm.BuildDesign: TDesignFile;
var
  S: TDesignSheet;
  W, H: Integer;
  Fs: TFormatSettings;
  M: Double;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Result := TDesignFile.Create;
  S := Result.AddSheet;
  PaperUnits(PaperIndex, Landscape, W, H);
  S.Details.PageWidth := W;
  S.Details.PageHeight := H;
  S.Details.Title := FTitle.Text;
  S.Details.Author := FAuthor.Text;
  S.Details.Org := FOrg.Text;
  S.Details.DocNo := FDocNo.Text;
  S.Details.AutoSheets := FAuto.Checked;
  S.Details.ShowBorder := FBorder.Checked;
  if not TryStrToFloat(StringReplace(FMargin.Text, ',', '.', []), M, Fs) then
    M := 6.35;
  S.Details.BorderMargin := Max(0, M) * UNITS_PER_MM;
  S.Details.AddRevision('A', '', S.Details.Author, '', 'Initial issue');
end;
}

{ ---------------------------------------------------------------- Ladder properties }

{ ===========================================================================
  TLadderForm.CreateFor  (constructor)
  Parameters:
    AOwner: TComponent - owner
    ALadder: TDrawLadder - the ladder to edit
  Notes:
    Builds the ladder properties dialog (kept for forms that still use a dialog; the ribbon now
    edits these properties).
  =========================================================================== }
constructor TLadderForm.CreateFor(AOwner: TComponent; ALadder: TDrawLadder);
var
  Btn: TButton;
  Fs: TFormatSettings;
begin
  inherited CreateNew(AOwner);
  FLadder := ALadder;
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Caption := 'Ladder Rails';
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  ClientWidth := 540;
  ClientHeight := 256;

  MakeLabel(Self, 'Left bus wire number:', 16, 20);
  FLeft := MakeEdit(Self, 190, 16, 100, ALadder.LeftWire);
  MakeLabel(Self, 'Right bus wire number:', 16, 54);
  FRight := MakeEdit(Self, 190, 50, 100, ALadder.RightWire);

  MakeLabel(Self, 'Rail line width:', 16, 96);
  FWidth := MakeEdit(Self, 190, 92, 100, IntToStr(ALadder.LineWidth));

  MakeLabel(Self, 'Left rail X (mm):', 16, 138);
  FX1 := MakeEdit(Self, 150, 134, 90, FormatFloat('0.##', ALadder.RailLeft / UNITS_PER_MM, Fs));
  MakeLabel(Self, 'Right rail X (mm):', 280, 138);
  FX2 := MakeEdit(Self, 420, 134, 90, FormatFloat('0.##', ALadder.RailRight / UNITS_PER_MM, Fs));
  MakeLabel(Self, 'Top Y (mm):', 16, 172);
  FY1 := MakeEdit(Self, 150, 168, 90, FormatFloat('0.##', ALadder.RailTop / UNITS_PER_MM, Fs));
  MakeLabel(Self, 'Bottom Y (mm):', 280, 172);
  FY2 := MakeEdit(Self, 420, 168, 90, FormatFloat('0.##', ALadder.RailBottom / UNITS_PER_MM, Fs));

  Btn := MakeButton(Self, 'OK', 330, 214, mrOK);
  Btn.Default := True;
  MakeButton(Self, 'Cancel', 434, 214, mrCancel);
end;

{ ===========================================================================
  TLadderForm.NumField  (function)
  Parameters:
    E: TEdit - the edit box
    Default: Integer - value to use on bad text
  Returns:
    Integer - the number, or Default if the text is not a number
  Notes:
    Reads a whole number from an edit box.
  =========================================================================== }
function TLadderForm.NumField(E: TEdit; Default: Integer): Integer;
begin
  if not TryStrToInt(Trim(E.Text), Result) then
    Result := Default;
end;

{ ===========================================================================
  TLadderForm.MmField  (function)
  Parameters:
    E: TEdit - the edit box
    Default: Double - value to use on bad text
  Returns:
    Double - the number, or Default on bad text
  Notes:
    Reads a number of millimetres from an edit box (comma accepted as decimal point).
  =========================================================================== }
function TLadderForm.MmField(E: TEdit; Default: Double): Double;
var
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  if not TryStrToFloat(StringReplace(Trim(E.Text), ',', '.', []), Result, Fs) then
    Result := Default;
end;

{ ===========================================================================
  TLadderForm.Apply  (function)
  Parameters:  none
  Returns:
    Boolean - False if the line numbers are not whole numbers
  Notes:
    Copies the dialog's values into the ladder: wire numbers, first / last line, line count (at
    least 1), number side, rail width and rectangle.
  =========================================================================== }
function TLadderForm.Apply: Boolean;
var
  A, B, C, D: Double;
  W: Integer;
begin
  Result := False;
  if (not TryStrToInt(Trim(FWidth.Text), W)) or (W < 1) then
    Exit;
  FLadder.LineWidth := Min(50, W);
  FLadder.LeftWire := FLeft.Text;
  FLadder.RightWire := FRight.Text;
  A := MmField(FX1, FLadder.RailLeft / UNITS_PER_MM) * UNITS_PER_MM;
  B := MmField(FY1, FLadder.RailTop / UNITS_PER_MM) * UNITS_PER_MM;
  C := MmField(FX2, FLadder.RailRight / UNITS_PER_MM) * UNITS_PER_MM;
  D := MmField(FY2, FLadder.RailBottom / UNITS_PER_MM) * UNITS_PER_MM;
  FLadder.PointA := DPoint(Min(A, C), Min(B, D));
  FLadder.PointB := DPoint(Max(A, C), Max(B, D));
  Result := True;
end;

{ ===========================================================================
  EditLadder  (function)
  Parameters:
    AOwner: TComponent - owner of the dialog
    ALadder: TDrawLadder - the ladder to edit
  Returns:
    Boolean - True if the ladder was changed
  Notes:
    Shows the ladder properties dialog modally and applies it on OK.
  =========================================================================== }
function EditLadder(AOwner: TComponent; ALadder: TDrawLadder): Boolean;
var
  F: TLadderForm;
begin
  Result := False;
  F := TLadderForm.CreateFor(AOwner, ALadder);
  try
    if F.ShowModal = mrOK then
    begin
      Result := F.Apply;
      if not Result then
        MessageDlg('Ladder Rails', 'The rail line width must be a whole number of 1 or more.', mtError, [mbOK], 0);
    end;
  finally
    F.Free;
  end;
end;

end.
