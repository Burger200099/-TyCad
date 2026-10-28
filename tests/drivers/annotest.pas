{ Test driver for Generate Symbol References (UAnnotate); tests/run_annotate.py checks what it prints against its own statement of Special.cpp.
    annotest dump <in.dsn>
        every other object as "O <sheet> <index> <type> <x> <y>" and every placed symbol as "M <sheet> <index in the drawing> <symbol> <reference> <part> <ax> <ay> <bx> <by> <prefix> <parts> <hetero> <statics>"
        where <statics> is, for each part, the offset from the symbol's point to its first static point and then to the far corner of its box, "x,y,bx,by;" (and "-" when the symbol has no
        definition), so that the test can follow how SetPart moves symbols
    annotest run <in.dsn> <out.dsn> <add 0/1 remove> <which 0 all/1 unnumbered/2 matching> <value 0 default/1 start> <match> <start> <all sheets 0/1> <active sheet>
        runs the command, prints "R <1 if a symbol had no definition>" and the symbols as for dump, and saves the design
    annotest paint <in.dsn> <sheet> <start> <x> <y> <remove 0/1> [<x> <y> <remove 0/1> ...]
        the reference painter: each click is applied in turn; prints "P <changed> <the indexes of the symbols under the click>" for each and then the symbols as for dump }
program annotest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UDrawingObjects, USymbols, UDesign, UAnnotate;

{ ===========================================================================
  Num  (function)
  Parameters:
    X: Double - horizontal position or value
  Returns:
    String - the number
  Notes:
    Converts script text to a number using a dot as the decimal separator.
  =========================================================================== }
function Num(X: Double): String;
begin
  Result := FloatToStrF(X, ffGeneral, 17, 0);
end;

{ ===========================================================================
  Dump  (procedure)
  Parameters:
    D: TDesignFile - the design
  Notes:
    Prints one line for every placed symbol.
  =========================================================================== }
procedure Dump(D: TDesignFile);
var
  I, J, P, Old: Integer;
  M: TDrawMethod;
  Sym: TSymbolInfo;
  A, S, Statics: String;
  Pt: TDPoint;
begin
  for I := 0 to D.SheetCount - 1 do
    for J := 0 to D.Sheets[I].Drawing.Count - 1 do
      if (D.Sheets[I].Drawing[J].GetType <> xMethodEx3) and (D.Sheets[I].Drawing[J].GetType <> xHierarchicalSymbol) then
        WriteLn('O ', I, ' ', J, ' ', Ord(D.Sheets[I].Drawing[J].GetType), ' ', Num(D.Sheets[I].Drawing[J].PointA.x), ' ', Num(D.Sheets[I].Drawing[J].PointA.y))
      else
      begin
        M := D.Sheets[I].Drawing[J] as TDrawMethod;
        Sym := M.GetSymbolData;
        Statics := '';
        if M is TDrawHierarchicalSymbol then
        begin
          { a placed design: the symbol of number 0 gives its prefix; the line ends with 1 and whether it has nothing to draw }
          if (M as TDrawHierarchicalSymbol).IsNoSymbol then
            Statics := '1'
          else
            Statics := '0';
          WriteLn('M ', I, ' ', J, ' ', M.SymbolId, ' ', StringReplace(M.GetRef, ' ', '_', [rfReplaceAll]), ' ', M.Part, ' ', Num(M.PointA.x), ' ', Num(M.PointA.y), ' ',
            Num(M.PointB.x), ' ', Num(M.PointB.y), ' ', StringReplace(Sym.SymbolReference, ' ', '_', [rfReplaceAll]), ' ', Sym.PartsPerPackage, ' ',
            Ord(Sym.IsHeterogeneous), ' - H', Statics);
          Continue;
        end;
        A := Num(M.PointA.x) + ' ' + Num(M.PointA.y) + ' ' + Num(M.PointB.x) + ' ' + Num(M.PointB.y);
        Old := M.Part;
        for P := 0 to Max(Sym.PartsPerPackage, Old + 1) - 1 do
        begin
          M.Part := P;
          Pt := M.GetFirstStaticPoint;
          Statics := Statics + Num(Pt.x - M.PointA.x) + ',' + Num(Pt.y - M.PointA.y) + ',' + Num(M.PointB.x - M.PointA.x) + ',' + Num(M.PointB.y - M.PointA.y) + ';';
        end;
        M.Part := Old;
        M.GetFirstStaticPoint;      // (puts the box back as it was for the part the symbol has)
        if Statics = '' then
          Statics := '-';
        if Sym.IsHeterogeneous then
          S := '1'
        else
          S := '0';
        WriteLn('M ', I, ' ', J, ' ', M.SymbolId, ' ', StringReplace(M.GetRef, ' ', '_', [rfReplaceAll]), ' ', M.Part, ' ', A, ' ',
          StringReplace(Sym.SymbolReference, ' ', '_', [rfReplaceAll]), ' ', Sym.PartsPerPackage, ' ', S, ' ', Statics);
      end;
end;

var
  D: TDesignFile;
  Setup: TAnnotateSetup;
  K, J: Integer;
  Pt: TDPoint;
  Under: String;
begin
  if ParamCount < 2 then
    Halt(2);
  D := TDesignFile.Create;
  try
    D.LoadFromFile(ParamStr(2));
    for K := 0 to D.SheetCount - 1 do D.Sheets[K].UpdateLayout;      // (the view does this after a load: it gives the symbols their boxes)
    if ParamStr(1) = 'dump' then
      Dump(D)
    else if ParamStr(1) = 'run' then
    begin
      Setup := AnnotateDefaults;
      if ParamStr(4) = '1' then
        Setup.Action := aaAdd
      else
        Setup.Action := aaRemove;
      Setup.Reference := TAnnotateWhich(StrToInt(ParamStr(5)));
      Setup.Value := TAnnotateStart(StrToInt(ParamStr(6)));
      Setup.MatchVal := ParamStr(7);
      Setup.StartVal := StrToInt(ParamStr(8));
      Setup.AllSheets := ParamStr(9) = '1';
      if RunAnnotate(D, StrToInt(ParamStr(10)), Setup) then
        WriteLn('R 1')
      else
        WriteLn('R 0');
      Dump(D);
      D.SaveToFile(ParamStr(3));
    end
    else if ParamStr(1) = 'paint' then
    begin
      K := 5;
      while K + 2 <= ParamCount do
      begin
        Pt := DPoint(StrToFloat(ParamStr(K)), StrToFloat(ParamStr(K + 1)));
        Under := '';
        for J := 0 to D.Sheets[StrToInt(ParamStr(3))].Drawing.Count - 1 do
          with D.Sheets[StrToInt(ParamStr(3))].Drawing[J] do
            if IsInside(Pt.x, Pt.x, Pt.y, Pt.y) and (GetType = xMethodEx3) then
              Under := Under + ' ' + IntToStr(J);
        WriteLn('P ', PaintReference(D.Sheets[StrToInt(ParamStr(3))], Pt, StrToInt(ParamStr(4)), ParamStr(K + 2) = '1'), Under);
        Inc(K, 3);
      end;
      Dump(D);
    end;
  finally
    D.Free;
  end;
end.
