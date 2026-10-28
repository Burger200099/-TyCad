{ The parts check of the design rules check (not in TinyCAD): for every placed part of a parts library, the product chosen for it is judged against what the part requires
  (UPartData.CheckFit, which follows the ProductFit views of parts_schema.sql), and one line and one marker is made for each problem:
    - a requirement the product does not meet (undersized, missing a rated quantity, mismatched): an error
    - no product chosen at all, or one only typed by hand (nothing is known of its ratings): "not chosen", by default a warning (or an error, or left out)
    - a product that beats a requirement (oversized): information, which can be left out
  The lines follow those of the design rules check and are numbered after them, marker k belonging to line k, so the Design Markers window finds the part by double click.
  Hierarchical designs: only the root design is checked, as the ERC does (placed designs are not followed yet). }
unit UPartCheck;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UDPoint, UDrawTypes, UDrawingObjects, USymbols, UDesign, UPartData;

const
  PC_IGNORE = 0;      // unresolved parts are not reported
  PC_WARNING = 1;     // ... reported as a warning
  PC_ERROR = 2;       // ... reported as an error

type
  TPartCheckOptions = record
    Enabled: Boolean;         // the check is run at all
    Unresolved: Integer;      // PC_IGNORE, PC_WARNING or PC_ERROR for a part with no product chosen / only typed
    ShowOversized: Boolean;   // report a product that is larger than needed (information)
  end;

{ the options as the program keeps them: on, unresolved as a warning, oversized shown }
function PartCheckDefaults: TPartCheckOptions;
{ Adds one line to Messages and one marker to the sheets for each problem found; the markers are numbered from FirstNumber (the number of lines the ERC already made).
  Returns how many lines were added. }
function RunPartCheck(Design: TDesignFile; const O: TPartCheckOptions; Messages: TStrings; FirstNumber: Integer): Integer;

implementation


uses UStrings;

{ ===========================================================================
  PartCheckDefaults  (function)
  Returns:
    TPartCheckOptions - the defaults
  Notes:
    The check on, an unresolved part is a warning, oversized products are shown (as information).
  =========================================================================== }
function PartCheckDefaults: TPartCheckOptions;
begin
  Result.Enabled := True;
  Result.Unresolved := PC_WARNING;
  Result.ShowOversized := True;
end;

{ ===========================================================================
  RunPartCheck  (function)
  Parameters:
    Design: TDesignFile - the design
    const O: TPartCheckOptions - which reports are wanted
    Messages: TStrings - the lines of the check (appended to; line k is the marker k)
    FirstNumber: Integer - the number of the first marker made (the number of lines already in Messages)
  Returns:
    Integer - the number of lines (and markers) added
  Notes:
    Walks the placed parts in sheet order. A line reads
      'Part does not fit:  [RefDes=K1, Object="...", Page #1, current (1L1-1T1): missing, need 25, have -]'
    with one line for each requirement that is undersized / missing / mismatched; 'Part has no product chosen' (typed only: 'Product typed by hand, ratings unknown')
    for an unresolved part, with '(warning)' or '(error)'; 'Product is larger than required' (information) for each oversized requirement. The marker sits on the reference
    of the part.
  =========================================================================== }
function RunPartCheck(Design: TDesignFile; const O: TPartCheckOptions; Messages: TStrings; FirstNumber: Integer): Integer;
var
  Number, I, J, K: Integer;
  M: TDrawMethod;
  Sym: TDesignFileSymbol;
  Lines: TFitLineArray;
  Where, Have, Head, Tail: String;

  procedure Mark(SheetIndex: Integer; const Text: String);
  var
    E: TDrawError;
    Sh: TDesignSheet;
    P: TDPoint;
  begin
    Sh := Design.Sheets[SheetIndex];
    P := DPoint(M.PointA.x + M.Fields[FIELD_REF].Position.x, M.PointA.y + M.Fields[FIELD_REF].Position.y);
    E := TDrawError.Create(Sh.Options);
    E.PointA := P;
    E.PointB := P;
    E.ErrorNumber := Number;
    Inc(Number);
    Sh.Drawing.Add(E);
    Messages.Add(Text + #10);
  end;

begin
  Result := 0;
  if not O.Enabled then
    Exit;
  Number := FirstNumber;
  for I := 0 to Design.SheetCount - 1 do
  begin
    K := Design.Sheets[I].Drawing.Count;      // (the markers added below are not looked at)
    for J := 0 to K - 1 do
      if Design.Sheets[I].Drawing[J].GetType = xMethodEx3 then
      begin
        M := Design.Sheets[I].Drawing[J] as TDrawMethod;
        if not (M.GetSymbolData is TDesignFileSymbol) then
          Continue;
        Sym := TDesignFileSymbol(M.GetSymbolData);
        if Sym.PartInfo.IsEmpty then
          Continue;
        Tail := '[RefDes=' + M.GetField(FIELD_REF) + ', Object="' + M.GetName + '", Page #' + IntToStr(I + 1);
        if M.Product.UID = '' then
        begin
          if O.Unresolved = PC_IGNORE then
            Continue;
          if (M.Product.Manufacturer <> '') or (M.Product.MPN <> '') then
            Head := rsProductTypedByHandRatings
          else
            Head := rsPartHasNoProductChosen;
          if O.Unresolved = PC_ERROR then
            Head := Format(rsError, [Head])
          else
            Head := Format(rsWarning, [Head]);
          Mark(I, Head + ':  ' + Tail + ']');
          Continue;
        end;
        Lines := CheckFit(Sym.PartInfo.Needs, M.Product.Haves);
        for K := 0 to High(Lines) do
        begin
          if Lines[K].Status = fsOk then
            Continue;
          if (Lines[K].Status = fsOversized) and not O.ShowOversized then
            Continue;
          Where := Lines[K].Need.Quantity;
          if Lines[K].Need.AppliesTo <> '' then
            Where := Where + ' (' + Lines[K].Need.AppliesTo + ')';
          if Lines[K].HaveFound then
            Have := FloatToStr(Lines[K].HaveValue)
          else
            Have := '-';
          if Lines[K].Status = fsOversized then
            Head := rsProductIsLargerThanRequired
          else
            Head := rsPartDoesNotFit;
          Mark(I, Format(rsNeedHave, [Head, Tail, Where, FitStatusName(Lines[K].Status), FloatToStr(Lines[K].NeedValue), Have]));
        end;
      end;
  end;
  Result := Number - FirstNumber;
end;

end.
