{ The Symbol Properties dialog of the parts library editor: drawing standard, purpose and name of one symbol of a part. What is allowed is checked by the library
  (TPartsLibrary.AddSymbol / UpdateSymbolInfo), which explains a refusal.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fsymbolinfo;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase;

type

  { TfrmSymbolInfo }

  TfrmSymbolInfo = class(TfrmBase)
    cbPurpose: TComboBox;
    cbStandard: TComboBox;
    edName: TEdit;
    lblName: TLabel;
    lblPurpose: TLabel;
    lblStandard: TLabel;
  private
    function GetStandard: String;
    function GetPurpose: String;
    function GetSymName: String;
  public
    { fills the dialog (a new symbol passes IEC, schematic and the part's name) }
    procedure Setup(const AStandard, APurpose, AName: String);
    property Standard: String read GetStandard;
    property Purpose: String read GetPurpose;
    property SymName: String read GetSymName;
  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfrmSymbolInfo.Setup  (procedure)
  Parameters:
    const AStandard, APurpose, AName: String - the values now
  Notes:
    The standard can be typed (IEC, ANSI, JIC ... are offered); the purpose is one of schematic, oneline, panel, block.
  =========================================================================== }
procedure TfrmSymbolInfo.Setup(const AStandard, APurpose, AName: String);
begin
  cbStandard.Text := AStandard;
  cbPurpose.ItemIndex := cbPurpose.Items.IndexOf(APurpose);
  if cbPurpose.ItemIndex < 0 then
    cbPurpose.ItemIndex := 0;
  edName.Text := AName;
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
