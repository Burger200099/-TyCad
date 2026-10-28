// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Generate Symbol References dialog (TinyCAD's CDlgAnnotateBox, IDD_ANNOTATE): the action (add or remove references), which references (all,
  un-numbered, or those of symbols with a given reference prefix, typed in a box), whether all sheets are covered, where the numbers start (a default
  of 1, or a typed value) and a button that, instead of numbering at once, hands out numbers one click at a time (the reference painter). OK, Cancel,
  and the painter button end the dialog; the painter's result is mrYes.

  When the dialog starts, the choice of references and of all sheets come from the program settings (TinyCAD's registry values Annotate.type and
  Annotate.allsheets), whatever the caller passed in; everything else comes from the caller. OK keeps those two choices in the settings. Typing in the
  start box chooses "Start at value". The start box is read as GetDlgItemInt does: an optional minus and digits; anything else, or a number that does not
  fit, gives 0.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fannotate;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UAnnotate, USettings, consts;

type

  { TfrmAnnotate }

  TfrmAnnotate = class(TfrmBase)
    btnPainter: TButton;
    cbAllSheets: TCheckBox;
    edMatch: TEdit;
    edStart: TEdit;
    gbAction: TGroupBox;
    gbPainter: TGroupBox;
    gbRefs: TGroupBox;
    gbValue: TGroupBox;
    rbAdd: TRadioButton;
    rbAll: TRadioButton;
    rbDefault: TRadioButton;
    rbMatch: TRadioButton;
    rbRemove: TRadioButton;
    rbStart: TRadioButton;
    rbUnnum: TRadioButton;
    procedure edStartChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FStarting: Boolean;
    procedure AnnotateActivate(Sender: TObject);
  public
    { CDlgAnnotateBox::OnInitDialog }
    procedure SetSetup(const S: TAnnotateSetup);
    { CDlgAnnotateBox::ReadData }
    function GetSetup: TAnnotateSetup;
    { CDlgAnnotateBox::OnOK: keeps the choice of references and of all sheets in the program settings }
    procedure KeepInSettings;
  end;

var
  frmAnnotate: TfrmAnnotate;

{ GetDlgItemInt: the number in the text, 0 when it is not one }
function DlgItemInt(const S: String): Integer;

implementation

{$R *.lfm}

{ ===========================================================================
  DlgItemInt  (function)
  Parameters:
    const S: String - the text of a box
  Returns:
    Integer - the number, or 0
  Notes:
    Windows' GetDlgItemInt as TinyCAD calls it (signed): an optional minus and then only digits;
    spaces, a plus sign, other characters, an empty text or a number outside the range of an
    Integer give 0.
  =========================================================================== }
function DlgItemInt(const S: String): Integer;
var
  I: Integer;
  V: Int64;
  Neg: Boolean;
begin
  Result := 0;
  I := 1;
  Neg := False;
  if (Length(S) > 0) and (S[1] = '-') then
  begin
    Neg := True;
    Inc(I);
  end;
  if I > Length(S) then
    Exit;
  V := 0;
  while I <= Length(S) do
  begin
    if not (S[I] in ['0'..'9']) then
      Exit;
    V := V * 10 + (Ord(S[I]) - 48);
    if V > 2147483648 then
      Exit;
    Inc(I);
  end;
  if Neg then
    V := -V;
  if (V > 2147483647) or (V < -2147483648) then
    Exit;
  Result := V;
end;

{ ===========================================================================
  TfrmAnnotate.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Shows the OK and Cancel buttons and puts the painter button where the dialog's own button
    row is not.
  =========================================================================== }
procedure TfrmAnnotate.FormCreate(Sender: TObject);
begin
  OnActivate := @AnnotateActivate;
end;

{ ===========================================================================
  TfrmAnnotate.AnnotateActivate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Shows the OK and Cancel buttons.
  =========================================================================== }
procedure TfrmAnnotate.AnnotateActivate(Sender: TObject);
begin
  SetButtons([fcbOK, fcbCancel]);
end;

{ ===========================================================================
  TfrmAnnotate.edStartChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    CDlgAnnotateBox::OnChangeStart: typing a start value chooses "Start at value".
  =========================================================================== }
procedure TfrmAnnotate.edStartChange(Sender: TObject);
begin
  if not FStarting then
    rbStart.Checked := True;
end;

{ ===========================================================================
  TfrmAnnotate.SetSetup  (procedure)
  Parameters:
    const S: TAnnotateSetup - the choices kept from the last time
  Notes:
    CDlgAnnotateBox::OnInitDialog: the choice of references and of all sheets are read from the
    program settings in place of the ones given; the rest are shown as given.
  =========================================================================== }
procedure TfrmAnnotate.SetSetup(const S: TAnnotateSetup);
begin
  FStarting := True;
  try
    edMatch.Text := S.MatchVal;
    edStart.Text := IntToStr(S.StartVal);
    rbAdd.Checked := S.Action = aaAdd;
    rbRemove.Checked := S.Action = aaRemove;
    rbAll.Checked := ProgramSettings.AnnotateType = 0;
    rbUnnum.Checked := ProgramSettings.AnnotateType = 1;
    rbMatch.Checked := ProgramSettings.AnnotateType = 2;
    rbDefault.Checked := S.Value = asDefault;
    rbStart.Checked := S.Value = asSpecified;
    cbAllSheets.Checked := ProgramSettings.AnnotateAllSheets;
  finally
    FStarting := False;
  end;
end;

{ ===========================================================================
  TfrmAnnotate.GetSetup  (function)
  Parameters:  none
  Returns:
    TAnnotateSetup - the choices shown
  Notes:
    CDlgAnnotateBox::ReadData.
  =========================================================================== }
function TfrmAnnotate.GetSetup: TAnnotateSetup;
begin
  Result := AnnotateDefaults;
  if rbAdd.Checked then
    Result.Action := aaAdd
  else if rbRemove.Checked then
    Result.Action := aaRemove;
  if rbAll.Checked then
    Result.Reference := awAll
  else if rbUnnum.Checked then
    Result.Reference := awUnnumbered
  else if rbMatch.Checked then
    Result.Reference := awMatching;
  if rbDefault.Checked then
    Result.Value := asDefault
  else if rbStart.Checked then
    Result.Value := asSpecified;
  Result.AllSheets := cbAllSheets.Checked;
  Result.MatchVal := edMatch.Text;
  Result.StartVal := DlgItemInt(edStart.Text);
end;

{ ===========================================================================
  TfrmAnnotate.KeepInSettings  (procedure)
  Parameters:  none
  Notes:
    CDlgAnnotateBox::OnOK: the choice of references and of all sheets go to the program settings
    (the caller saves them).
  =========================================================================== }
procedure TfrmAnnotate.KeepInSettings;
begin
  ProgramSettings.AnnotateType := Ord(GetSetup.Reference);
  ProgramSettings.AnnotateAllSheets := cbAllSheets.Checked;
end;

end.
