// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Add Part wizard of the parts library editor (parts plan step 7): the person picks what kind of part it is from a list of presets (a relay with coil and contacts, a contactor with
  main poles and auxiliary contacts, a timer relay, a breaker, a terminal block, any other part), and only the entries that kind needs are shown: the numbers of poles and contacts,
  the coil, the delay. The name is made from the entries until the person types one of their own. UPartPresets makes the part.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fpartwizard;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Spin, Fbase, UPartsDb, UPartPresets;

type

  { TfrmPartWizard }

  TfrmPartWizard = class(TfrmBase)
    cbClass: TComboBox;
    cbCoil: TCheckBox;
    cbDelay: TComboBox;
    edDescription: TEdit;
    edName: TEdit;
    edRef: TEdit;
    edSecs: TEdit;
    lblClass: TLabel;
    lblDelay: TLabel;
    lblDescription: TLabel;
    lblHint: TLabel;
    lblName: TLabel;
    lblNC: TLabel;
    lblNO: TLabel;
    lblPoles: TLabel;
    lblRef: TLabel;
    lblSecs: TLabel;
    lblSummary: TLabel;
    lbPresets: TListBox;
    seNC: TSpinEdit;
    seNO: TSpinEdit;
    sePoles: TSpinEdit;
    procedure EntryChange(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure NameChange(Sender: TObject);
    procedure PresetClick(Sender: TObject);
  private
    FLib: TPartsLibrary;
    FPresets: TPartPresetArray;
    FNameTyped: Boolean;       // the person typed the name: it is not made from the entries any more
    FLoading: Boolean;
    function GetPreset: TPartPreset;
    function GetParams: TPresetParams;
    function GetClassID: Int64;
    procedure ShowEntries;
    procedure UpdateName;
  public
    procedure Setup(ALib: TPartsLibrary);
    { the same as clicking a preset, for the self-test script }
    procedure ChoosePreset(const AKey: String);
    procedure SetEntries(APoles, ANO, ANC: Integer; ACoil: Boolean; const ADelay: String; ASecs: Double);
    property Preset: TPartPreset read GetPreset;
    property Params: TPresetParams read GetParams;
    property ClassID: Int64 read GetClassID;
    function PartName: String;
    function RefPrefix: String;
    function Description: String;
    function SummaryText: String;
  end;

implementation

uses UStrings;

{$R *.lfm}

procedure TfrmPartWizard.Setup(ALib: TPartsLibrary);
var
  i, k: Integer;
  List: TStringList;
begin
  FLib := ALib;
  FPresets := PartPresets;
  lbPresets.Items.Clear;
  for i := 0 to High(FPresets) do
    lbPresets.Items.Add(FPresets[i].Title);
  List := TStringList.Create;
  try
    for i := 0 to ALib.ClassCount - 1 do
      if not ALib.Classes[i].Abstract then
        List.AddObject(ALib.Classes[i].Name, TObject(PtrInt(ALib.Classes[i].ID)));
    List.Sort;
    cbClass.Items.Clear;
    for k := 0 to List.Count - 1 do
      cbClass.Items.AddObject(List[k], List.Objects[k]);
  finally
    List.Free;
  end;
  if cbClass.Items.Count > 0 then
    cbClass.ItemIndex := 0;
  cbDelay.Items.Clear;
  cbDelay.Items.Add('none'); cbDelay.Items.Add('on-delay'); cbDelay.Items.Add('off-delay');
  Caption := rsAddPart;
  ChoosePreset(FPresets[0].Key);
end;

procedure TfrmPartWizard.ChoosePreset(const AKey: String);
var
  i: Integer;
begin
  for i := 0 to High(FPresets) do
    if SameText(FPresets[i].Key, AKey) then
      lbPresets.ItemIndex := i;
  PresetClick(nil);
end;

function TfrmPartWizard.GetPreset: TPartPreset;
begin
  if (lbPresets.ItemIndex >= 0) and (lbPresets.ItemIndex <= High(FPresets)) then
    Result := FPresets[lbPresets.ItemIndex]
  else
    Result := FPresets[High(FPresets)];
end;

function TfrmPartWizard.GetParams: TPresetParams;
begin
  Result.Poles := sePoles.Value; Result.NO := seNO.Value; Result.NC := seNC.Value;
  Result.Coil := cbCoil.Checked;
  Result.Delay := cbDelay.Text;
  if Result.Delay = '' then
    Result.Delay := 'none';
  Result.DelaySecs := StrToFloatDef(StringReplace(Trim(edSecs.Text), ',', '.', []), 0, DefaultFormatSettings);
end;

function TfrmPartWizard.GetClassID: Int64;
begin
  if cbClass.ItemIndex >= 0 then
    Result := PtrInt(cbClass.Items.Objects[cbClass.ItemIndex])
  else
    Result := 0;
end;

{ the entries of the chosen preset: its defaults are loaded and only what it uses is shown }
procedure TfrmPartWizard.PresetClick(Sender: TObject);
var
  P: TPartPreset;
begin
  P := GetPreset;
  FLoading := True;
  try
    sePoles.Value := P.Defaults.Poles; seNO.Value := P.Defaults.NO; seNC.Value := P.Defaults.NC;
    cbCoil.Checked := P.Defaults.Coil;
    cbDelay.ItemIndex := cbDelay.Items.IndexOf(P.Defaults.Delay);
    if cbDelay.ItemIndex < 0 then
      cbDelay.ItemIndex := 0;
    edSecs.Text := FloatToStr(P.Defaults.DelaySecs);
    edRef.Text := P.RefPrefix;
    lblHint.Caption := P.Hint;
    FNameTyped := False;
  finally
    FLoading := False;
  end;
  ShowEntries;
  UpdateName;
end;

procedure TfrmPartWizard.ShowEntries;
var
  P: TPartPreset;
begin
  P := GetPreset;
  lblPoles.Visible := P.AskPoles; sePoles.Visible := P.AskPoles;
  lblNO.Visible := P.AskNO; seNO.Visible := P.AskNO;
  lblNC.Visible := P.AskNC; seNC.Visible := P.AskNC;
  cbCoil.Visible := P.AskCoil;
  lblDelay.Visible := P.AskDelay; cbDelay.Visible := P.AskDelay;
  lblSecs.Visible := P.AskDelay; edSecs.Visible := P.AskDelay;
  lblClass.Visible := P.ClassName = ''; cbClass.Visible := P.ClassName = '';
end;

procedure TfrmPartWizard.UpdateName;
var
  P: TPartPreset;
begin
  P := GetPreset;
  if not FNameTyped then
  begin
    FLoading := True;
    try
      edName.Text := PresetName(P, GetParams);
    finally
      FLoading := False;
    end;
  end;
  lblSummary.Caption := SummaryText;
end;

procedure TfrmPartWizard.EntryChange(Sender: TObject);
begin
  if not FLoading then
    UpdateName;
end;

procedure TfrmPartWizard.NameChange(Sender: TObject);
begin
  if not FLoading then
    FNameTyped := True;
end;

procedure TfrmPartWizard.SetEntries(APoles, ANO, ANC: Integer; ACoil: Boolean; const ADelay: String; ASecs: Double);
begin
  FLoading := True;
  try
    sePoles.Value := APoles; seNO.Value := ANO; seNC.Value := ANC; cbCoil.Checked := ACoil;
    cbDelay.ItemIndex := cbDelay.Items.IndexOf(ADelay);
    edSecs.Text := FloatToStr(ASecs);
  finally
    FLoading := False;
  end;
  UpdateName;
end;

function TfrmPartWizard.PartName: String;
begin
  Result := Trim(edName.Text);
end;

function TfrmPartWizard.RefPrefix: String;
begin
  Result := Trim(edRef.Text);
end;

function TfrmPartWizard.Description: String;
begin
  Result := edDescription.Text;
end;

function TfrmPartWizard.SummaryText: String;
begin
  Result := Format(rsThisMakes, [PresetSummary(GetPreset, GetParams)]);
end;

procedure TfrmPartWizard.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if ModalResult <> mrOK then
    Exit;
  if Trim(edName.Text) = '' then
  begin
    MessageDlg(rsPart, rsThePartNeedsAName, mtWarning, [mbOK], 0);
    CanClose := False;
    edName.SetFocus;
  end
  else if (GetPreset.ClassName = '') and (cbClass.ItemIndex < 0) then
  begin
    MessageDlg(rsPart, rsChooseAClassForThe3, mtWarning, [mbOK], 0);
    CanClose := False;
  end;
end;

end.
