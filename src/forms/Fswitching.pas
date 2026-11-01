// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Poles and Contacts dialog of the parts library editor: the coil, poles and contacts of a part as rows, with the form (NO, NC ...) and delay (none, on-delay, off-delay and its time) of each
  contact. Poles and contacts are added and removed here; every change goes straight to the parts file (like the other pages of the editor) and OnChanged tells the editor to show it.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fswitching;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Fbase, UPartsDb;

type

  { TfrmSwitching }

  TfrmSwitching = class(TfrmBase)
    btnAddContact: TButton;
    btnAddPole: TButton;
    btnChange: TButton;
    btnDelete: TButton;
    cbDelay: TComboBox;
    cbForm: TComboBox;
    cbPoleForm: TComboBox;
    btnChangePole: TButton;
    edDesignator: TEdit;
    edSecs: TEdit;
    gbContact: TGroupBox;
    gbPole: TGroupBox;
    lblPoleForm: TLabel;
    lblDelay: TLabel;
    lblDesignator: TLabel;
    lblForm: TLabel;
    lblSecs: TLabel;
    lvRows: TListView;
    procedure AddContactClick(Sender: TObject);
    procedure AddPoleClick(Sender: TObject);
    procedure ChangeClick(Sender: TObject);
    procedure ChangePoleClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure RowSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure SwitchActivate(Sender: TObject);
  private
    FLib: TPartsLibrary;
    FPartID: Int64;
    FRows: TSwitchRowArray;
    FSel: Integer;                        // the row chosen (-1 none); kept here too, as a list that is not on screen does not keep a selection
    FOnChanged: TNotifyEvent;
    FLastError: String;
    function SecsValue(out V: Double): Boolean;
    function RowIndexOf(ID: Int64): Integer;
    function SelectedIndex: Integer;
    procedure UpdateButtons;
    procedure ShowBoxes;
    procedure ResetEntries;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    procedure Setup(ALib: TPartsLibrary; APartID: Int64);
    procedure Fill(SelectID: Int64);
    { choose a row (by the script and the list's own click) }
    procedure SelectRow(Index: Integer);
    { the three actions of the buttons, without their message boxes: True when the file took the change, else LastError says why }
    function DoAddPole: Boolean;
    function DoAddContact: Boolean;
    function DoChange: Boolean;
    function DoChangePole: Boolean;
    function DoDelete: Boolean;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property LastError: String read FLastError;
    property Rows: TSwitchRowArray read FRows;
  end;

implementation

uses UStrings, LCLType;

{$R *.lfm}

{ ===========================================================================
  TfrmSwitching.Setup  (procedure)
  Parameters:
    ALib: TPartsLibrary - the open parts library
    APartID: Int64 - the part
  Notes:
    Fills the Form and Delay lists from the Contact kind's fields (Form defaults to NO, Delay to none) and the rows from the part.
  =========================================================================== }
procedure TfrmSwitching.Setup(ALib: TPartsLibrary; APartID: Int64);
var
  L: TStringList;
begin
  FLib := ALib;
  FPartID := APartID;
  SetButtons([fcbOk]);
  FSel := -1;
  L := TStringList.Create;
  try
    L.Delimiter := ',';
    L.StrictDelimiter := True;
    L.DelimitedText := FLib.ContactEnum('Form');
    cbForm.Items.Assign(L);
    L.DelimitedText := FLib.ContactEnum('Delay');
    cbDelay.Items.Assign(L);
    L.DelimitedText := FLib.PoleFormEnum;
    cbPoleForm.Items.Assign(L);
  finally
    L.Free;
  end;
  ResetEntries;
  Fill(0);
end;

function TfrmSwitching.RowIndexOf(ID: Int64): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FRows) do
    if FRows[i].ID = ID then
      Exit(i);
end;

function TfrmSwitching.SelectedIndex: Integer;
begin
  Result := FSel;
  if (Result < 0) or (Result > High(FRows)) then
    Result := -1;
end;

{ ===========================================================================
  TfrmSwitching.SelectRow  (procedure)
  Parameters:
    Index: Integer - the row (0 based), -1 for none
  Notes:
    Chooses a row and shows its entries in the Contact box.
  =========================================================================== }
procedure TfrmSwitching.SelectRow(Index: Integer);
begin
  if (Index < 0) or (Index > High(FRows)) then
    FSel := -1
  else
    FSel := Index;
  if (FSel >= 0) and (lvRows.Items.Count > FSel) then
    begin
      lvRows.Items[FSel].Selected := True;
      lvRows.Items[FSel].MakeVisible(False);
    end;
  ResetEntries;      { (the boxes do not keep what the row chosen before had) }
  if (FSel >= 0) and (FRows[FSel].Kind = 'Contact') then
  begin
    edDesignator.Text := FRows[FSel].Designator;
    cbForm.ItemIndex := cbForm.Items.IndexOf(FRows[FSel].Form);
    cbDelay.ItemIndex := cbDelay.Items.IndexOf(FRows[FSel].Delay);
    if FRows[FSel].Delay = 'none' then
      edSecs.Text := ''
    else
      edSecs.Text := FloatToStr(FRows[FSel].DelaySecs);
  end
  else if (FSel >= 0) and (FRows[FSel].Kind = 'Pole') then
  begin
    cbPoleForm.ItemIndex := cbPoleForm.Items.IndexOf(FRows[FSel].Form);
    if cbPoleForm.ItemIndex < 0 then
      cbPoleForm.ItemIndex := 0;      { (a pole of a file made before the field is standard) }
  end;
  ShowBoxes;
  UpdateButtons;
end;

{ ===========================================================================
  TfrmSwitching.Fill  (procedure)
  Parameters:
    SelectID: Int64 - the object to choose afterwards (0 = keep nothing chosen)
  Notes:
    Lists the rows: a name is indented below its pole.
  =========================================================================== }
procedure TfrmSwitching.Fill(SelectID: Int64);
var
  i: Integer;
  It: TListItem;
  Pre: String;
begin
  FRows := FLib.SwitchRows(FPartID);
  FSel := RowIndexOf(SelectID);
  lvRows.Items.BeginUpdate;
  try
    lvRows.Items.Clear;
    for i := 0 to High(FRows) do
    begin
      Pre := '';
      if (FRows[i].ParentID <> 0) and (RowIndexOf(FRows[i].ParentID) >= 0) then
        Pre := '    ';
      It := lvRows.Items.Add;
      It.Caption := Pre + FRows[i].Name;
      It.SubItems.Add(FRows[i].Kind);
      It.SubItems.Add(FRows[i].Designator);
      It.SubItems.Add(FRows[i].Form);
      It.SubItems.Add(FRows[i].Delay);
      if FRows[i].Delay = 'none' then
        It.SubItems.Add('')
      else if FRows[i].Delay <> '' then
        It.SubItems.Add(FloatToStr(FRows[i].DelaySecs))
      else
        It.SubItems.Add('');
      if FRows[i].ID = SelectID then
        It.Selected := True;
    end;
  finally
    lvRows.Items.EndUpdate;
  end;
  UpdateButtons;
  if FSel >= 0 then
    SelectRow(FSel);      { (the boxes show the row that is chosen) }
end;

{ ===========================================================================
  TfrmSwitching.ResetEntries  (procedure)
  Notes:
    Puts the Contact and Pole boxes to what a new contact or pole starts with: the first Form (NO), no delay, no time, no designator, a standard pole.
  =========================================================================== }
procedure TfrmSwitching.ResetEntries;
begin
  edDesignator.Text := '';
  if cbForm.Items.Count > 0 then
    cbForm.ItemIndex := 0;
  if cbDelay.Items.Count > 0 then
    cbDelay.ItemIndex := 0;
  edSecs.Text := '';
  if cbPoleForm.Items.Count > 0 then
    cbPoleForm.ItemIndex := 0;
end;

{ ===========================================================================
  TfrmSwitching.ShowBoxes  (procedure)
  Notes:
    The Pole box is shown for a pole, the Contact box for a contact and when nothing is chosen (what Add Pole and Add Contact start from); the coil has neither.
  =========================================================================== }
procedure TfrmSwitching.ShowBoxes;
var
  I: Integer;
begin
  I := SelectedIndex;
  gbPole.Visible := (I >= 0) and (FRows[I].Kind = 'Pole');
  gbContact.Visible := (I < 0) or (FRows[I].Kind = 'Contact');
end;

procedure TfrmSwitching.UpdateButtons;
var
  I: Integer;
  IsContact: Boolean;
begin
  I := SelectedIndex;
  IsContact := (I >= 0) and (FRows[I].Kind = 'Contact');
  btnChange.Enabled := IsContact;
  btnChangePole.Enabled := (I >= 0) and (FRows[I].Kind = 'Pole');
  btnDelete.Enabled := (I >= 0) and (FRows[I].Kind <> 'Coil');
  btnAddPole.Enabled := FLib <> nil;
  btnAddContact.Enabled := (I >= 0) and ((FRows[I].Kind = 'Pole') or (FRows[I].Kind = 'Contact'));
  gbContact.Enabled := True;
  ShowBoxes;
end;

{ the base form shows OK and Cancel when it is activated: only Close is wanted here (the changes are in the file already), and Esc closes too }
procedure TfrmSwitching.SwitchActivate(Sender: TObject);
begin
  SetButtons([fcbOk]);
end;

procedure TfrmSwitching.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and (Shift = []) then
  begin
    Key := 0;
    ModalResult := mrOK;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TfrmSwitching.RowSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected and (Item <> nil) then
    SelectRow(Item.Index);
end;

{ the delay time typed: empty = 0; False (LastError set) when it is not a number }
function TfrmSwitching.SecsValue(out V: Double): Boolean;
var
  FS: TFormatSettings;
begin
  V := 0;
  Result := True;
  if Trim(edSecs.Text) = '' then
    Exit;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(StringReplace(Trim(edSecs.Text), ',', '.', []), V, FS) then
  begin
    FLastError := Format(rsIsNotANumber, [Trim(edSecs.Text)]);
    Result := False;
  end;
end;

{ ===========================================================================
  TfrmSwitching.DoAddPole / DoAddContact / DoChange / DoDelete  (functions)
  Returns:
    Boolean - True when the library took the change (the rows are shown again, OnChanged fired); False with LastError when it refused
  Notes:
    Add Pole and Add Contact use the Form, Delay and Time chosen in the Contact box; Add Contact puts the contact in the chosen pole (or the pole of the chosen contact). Change keeps
    the Contact box on the chosen contact. Delete removes the chosen pole (with its contacts) or contact; refused while a symbol shows it.
  =========================================================================== }
function TfrmSwitching.DoAddPole: Boolean;
var
  V: Double;
  Id: Int64;
begin
  Result := False;
  FLastError := '';
  if not SecsValue(V) then
    Exit;
  try
    Id := FLib.AddSwitchPole(FPartID, cbForm.Text, cbDelay.Text, V);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Fill(Id);
  if Assigned(FOnChanged) then
    FOnChanged(Self);
  Result := True;
end;

function TfrmSwitching.DoAddContact: Boolean;
var
  V: Double;
  Id, Pole: Int64;
  I: Integer;
begin
  Result := False;
  FLastError := '';
  I := SelectedIndex;
  if I < 0 then
    Exit;
  if FRows[I].Kind = 'Pole' then
    Pole := FRows[I].ID
  else
    Pole := FRows[I].ParentID;
  if not SecsValue(V) then
    Exit;
  try
    Id := FLib.AddSwitchContact(FPartID, Pole, cbForm.Text, cbDelay.Text, V);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Fill(Id);
  if Assigned(FOnChanged) then
    FOnChanged(Self);
  Result := True;
end;

function TfrmSwitching.DoChange: Boolean;
var
  V: Double;
  I: Integer;
  Id: Int64;
begin
  Result := False;
  FLastError := '';
  I := SelectedIndex;
  if (I < 0) or (FRows[I].Kind <> 'Contact') then
    Exit;
  Id := FRows[I].ID;
  if not SecsValue(V) then
    Exit;
  try
    FLib.SetSwitchContact(Id, edDesignator.Text, cbForm.Text, cbDelay.Text, V);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Fill(Id);
  if Assigned(FOnChanged) then
    FOnChanged(Self);
  Result := True;
end;

function TfrmSwitching.DoChangePole: Boolean;
var
  I: Integer;
  Id: Int64;
begin
  Result := False;
  FLastError := '';
  I := SelectedIndex;
  if (I < 0) or (FRows[I].Kind <> 'Pole') then
    Exit;
  Id := FRows[I].ID;
  try
    FLib.SetPoleForm(Id, cbPoleForm.Text);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Fill(Id);
  if Assigned(FOnChanged) then
    FOnChanged(Self);
  Result := True;
end;

function TfrmSwitching.DoDelete: Boolean;
var
  I: Integer;
begin
  Result := False;
  FLastError := '';
  I := SelectedIndex;
  if (I < 0) or (FRows[I].Kind = 'Coil') then
    Exit;
  try
    FLib.DeleteObject(FRows[I].ID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Fill(0);
  if Assigned(FOnChanged) then
    FOnChanged(Self);
  Result := True;
end;

procedure TfrmSwitching.AddPoleClick(Sender: TObject);
begin
  if not DoAddPole then
    if FLastError <> '' then
      MessageDlg(Caption, FLastError, mtError, [mbOK], 0);
end;

procedure TfrmSwitching.AddContactClick(Sender: TObject);
begin
  if not DoAddContact then
    if FLastError <> '' then
      MessageDlg(Caption, FLastError, mtError, [mbOK], 0);
end;

procedure TfrmSwitching.ChangeClick(Sender: TObject);
begin
  if not DoChange then
    if FLastError <> '' then
      MessageDlg(Caption, FLastError, mtError, [mbOK], 0);
end;

procedure TfrmSwitching.ChangePoleClick(Sender: TObject);
begin
  if not DoChangePole then
    if FLastError <> '' then
      MessageDlg(Caption, FLastError, mtError, [mbOK], 0);
end;

procedure TfrmSwitching.DeleteClick(Sender: TObject);
var
  I: Integer;
begin
  I := SelectedIndex;
  if I < 0 then
    Exit;
  if MessageDlg(rsDeleteObject, Format(rsDeleteTheObject, [FRows[I].Name]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  if not DoDelete then
    if FLastError <> '' then
      MessageDlg(Caption, FLastError, mtError, [mbOK], 0);
end;

end.
