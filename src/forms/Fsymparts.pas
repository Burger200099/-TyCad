// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Parts per Package dialog of the symbol editor (TinyCAD's Library > Set parts per package and Homogeneous / Heterogeneous Symbol, put in one window): how many parts
  the package has (1 to 26) and whether every part has a drawing of its own (heterogeneous) or all share one drawing whose pins are told apart by their part.

  As in TinyCAD the kind of symbol can only be changed while the package has one part: the check box is dimmed when the symbol has several parts and the count stays above 1.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fsymparts;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Spin, Fbase;

type

  { TfrmSymbolParts }

  TfrmSymbolParts = class(TfrmBase)
    cbHetero: TCheckBox;
    lblParts: TLabel;
    lblNote: TLabel;
    seParts: TSpinEdit;
    procedure PartsChange(Sender: TObject);
  private
    FOldParts: Integer;
  public
    { start with the symbol's present number of parts and kind }
    procedure Load(AParts: Integer; AHetero: Boolean);
    function Parts: Integer;
    function Hetero: Boolean;
    { what a person does with the controls, for tests: type a count, tick the box }
    procedure SetParts(N: Integer);
    procedure SetHetero(Value: Boolean);
    function HeteroEnabled: Boolean;
  end;

var
  frmSymbolParts: TfrmSymbolParts;

implementation

{$R *.lfm}

{ ===========================================================================
  TfrmSymbolParts.Load  (procedure)
  Parameters:
    AParts: Integer - the symbol's number of parts per package
    AHetero: Boolean - True if every part has its own drawing
  Notes:
    Shows the symbol's present number of parts and kind of symbol.
  =========================================================================== }
procedure TfrmSymbolParts.Load(AParts: Integer; AHetero: Boolean);
begin
  FOldParts := AParts;
  seParts.Value := AParts;
  cbHetero.Checked := AHetero;
  PartsChange(nil);
end;

{ ===========================================================================
  TfrmSymbolParts.PartsChange  (procedure)
  Parameters:
    Sender: TObject - the count
  Notes:
    The kind of symbol can be changed while the package has one part (before or after this
    change); with several parts the box is dimmed.
  =========================================================================== }
procedure TfrmSymbolParts.PartsChange(Sender: TObject);
begin
  cbHetero.Enabled := (FOldParts = 1) or (seParts.Value = 1);
end;

{ ===========================================================================
  TfrmSymbolParts.Parts  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    The number of parts typed.
  =========================================================================== }
function TfrmSymbolParts.Parts: Integer;
begin
  Result := seParts.Value;
end;

{ ===========================================================================
  TfrmSymbolParts.Hetero  (function)
  Parameters:  none
  Returns:
    Boolean - True if ticked
  Notes:
    Whether every part has a drawing of its own.
  =========================================================================== }
function TfrmSymbolParts.Hetero: Boolean;
begin
  Result := cbHetero.Checked;
end;

{ ===========================================================================
  TfrmSymbolParts.SetParts  (procedure)
  Parameters:
    N: Integer - the count
  Notes:
    Types a number of parts (the box limits it to 1 to 26).
  =========================================================================== }
procedure TfrmSymbolParts.SetParts(N: Integer);
begin
  seParts.Value := N;
  PartsChange(nil);
end;

{ ===========================================================================
  TfrmSymbolParts.SetHetero  (procedure)
  Parameters:
    Value: Boolean - ticked or not
  Notes:
    Ticks or clears the box when it is enabled.
  =========================================================================== }
procedure TfrmSymbolParts.SetHetero(Value: Boolean);
begin
  if cbHetero.Enabled then
    cbHetero.Checked := Value;
end;

{ ===========================================================================
  TfrmSymbolParts.HeteroEnabled  (function)
  Parameters:  none
  Returns:
    Boolean - True if it can be changed
  Notes:
    Whether the box can be changed now.
  =========================================================================== }
function TfrmSymbolParts.HeteroEnabled: Boolean;
begin
  Result := cbHetero.Enabled;
end;

end.
