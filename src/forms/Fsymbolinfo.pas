// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Symbol Properties dialog of the parts library editor: drawing standard, purpose and name of one symbol of a part. What is allowed is checked by the library
  (TPartsLibrary.AddSymbol / UpdateSymbolInfo), which explains a refusal.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fsymbolinfo;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UPartsDb;

type

  { TfrmSymbolInfo }

  TfrmSymbolInfo = class(TfrmBase)
    cbPurpose: TComboBox;
    cbStandard: TComboBox;
    edName: TEdit;
    cbShows: TComboBox;
    lblName: TLabel;
    lblShows: TLabel;
    lblPurpose: TLabel;
    lblStandard: TLabel;
  private
    FShowsIds: array of Int64;     // cbShows.Items[i + 1] is the object FShowsIds[i]; item 0 is the whole device
    function GetShowsID: Int64;
    function GetStandard: String;
    function GetPurpose: String;
    function GetSymName: String;
  public
    { fills the dialog (a new symbol passes IEC, schematic and the part's name) }
    procedure Setup(const AStandard, APurpose, AName: String); overload;
    procedure Setup(const AStandard, APurpose, AName: String; const Choices: TObjectRefArray; AShowsID: Int64); overload;
    property Standard: String read GetStandard;
    property Purpose: String read GetPurpose;
    property SymName: String read GetSymName;
    { the object of the part the symbol draws (0 = the whole device) }
    property ShowsID: Int64 read GetShowsID;
  end;

implementation

{$R *.lfm}

uses UStrings;

{ ===========================================================================
  TfrmSymbolInfo.Setup  (procedure)
  Parameters:
    const AStandard, APurpose, AName: String - the values now
    const Choices: TObjectRefArray - the coil, pole and contact objects of the part (TPartsLibrary.FunctionObjects)
    AShowsID: Int64 - the one the symbol draws now (0 = the whole device)
  Notes:
    The standard can be typed (IEC, ANSI, JIC ... are offered); the purpose is one of schematic, oneline, panel, block. Shows lists the whole device and then each choice by name.
  =========================================================================== }
{ ===========================================================================
  TfrmSymbolInfo.Setup  (procedure)
  Parameters:
    const AStandard, APurpose, AName: String - the values now
  Notes:
    For a new or imported symbol: what it shows is set afterwards (Symbols page > Properties), so the Shows line is hidden.
  =========================================================================== }
procedure TfrmSymbolInfo.Setup(const AStandard, APurpose, AName: String);
begin
  Setup(AStandard, APurpose, AName, nil, 0);
  lblShows.Visible := False;
  cbShows.Visible := False;
end;

procedure TfrmSymbolInfo.Setup(const AStandard, APurpose, AName: String; const Choices: TObjectRefArray; AShowsID: Int64);
var
  i: Integer;
begin
  cbShows.Items.Clear;
  cbShows.Items.Add(rsWholeDevice);
  SetLength(FShowsIds, Length(Choices));
  for i := 0 to High(Choices) do
  begin
    FShowsIds[i] := Choices[i].ID;
    cbShows.Items.Add(Choices[i].Name + ' (' + Choices[i].Kind + ')');
    if Choices[i].ID = AShowsID then
      cbShows.ItemIndex := i + 1;
  end;
  if (cbShows.ItemIndex < 0) or (AShowsID = 0) then
    cbShows.ItemIndex := 0;
  cbStandard.Text := AStandard;
  cbPurpose.ItemIndex := cbPurpose.Items.IndexOf(APurpose);
  if cbPurpose.ItemIndex < 0 then
    cbPurpose.ItemIndex := 0;
  edName.Text := AName;
end;

function TfrmSymbolInfo.GetShowsID: Int64;
begin
  Result := 0;
  if (cbShows.ItemIndex > 0) and (cbShows.ItemIndex - 1 <= High(FShowsIds)) then
    Result := FShowsIds[cbShows.ItemIndex - 1];
end;

function TfrmSymbolInfo.GetStandard: String;
begin
  Result := Trim(cbStandard.Text);
end;

function TfrmSymbolInfo.GetPurpose: String;
begin
  Result := cbPurpose.Text;
end;

function TfrmSymbolInfo.GetSymName: String;
begin
  Result := Trim(edName.Text);
end;

end.
