{ Test driver for hierarchical designs.
    hiertest convert <in> <out> [rename|clone]   load a design and save it again (rename: the first sheet is given the name Other before the save)
                                    (the output may be in another folder: file names inside are
                                    written relative to it). Prints SHEET lines (index, hierarchical flag, name, objects) and
                                    one OBJ line per hierarchical symbol (type code, file name in memory, rotate, name field).
    hiertest unformat <design> <name>   UnformatXMLFilename with XMLPathName = <design>
    hiertest format <design> <name>     FormatXMLFilename with XMLPathName = <design>
    hiertest display <name>             FormatDisplayFilename }
program hiertest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, UDPoint, UDrawTypes, UDrawingObjects, USymbols, UDesign, UXMLPath;

var
  D: TDesignFile;
  i, j: Integer;
  O: TDrawingObject;
  H, Fresh: TDrawHierarchicalSymbol;
  Raw: TDrawingList;
  Err: String;
  k: Integer;
  Tr: TDPoint;
  Objs: TDrawingList;
  Ok: Boolean;
  Pts: TDPointArray;

  function Pt(const P: TDPoint): String;
  begin Result := FloatToStrF(P.x, ffFixed, 15, 5) + ',' + FloatToStrF(P.y, ffFixed, 15, 5); end;

  function Describe(L: TDrawingList): String;
  var
    q: Integer;
    Inv: String;
  begin
    Result := '';
    for q := 0 to L.Count - 1 do
    begin
      Inv := '';
      if (L[q] is TDrawPin) and (L[q] as TDrawPin).IsInvisible then Inv := 'i';
      Result := Result + IntToStr(Ord(L[q].GetType)) + Inv + ':' + Pt(L[q].PointA) + ':' + Pt(L[q].PointB) + ';';
    end;
  end;

begin
  if ParamCount < 2 then
  begin
    WriteLn('usage: hiertest convert <in> <out> | unformat <design> <name> | format <design> <name> | display <name>');
    Halt(2);
  end;
  if ParamStr(1) = 'unformat' then
  begin
    XMLPathName := ParamStr(2);
    if XMLPathName = '-' then XMLPathName := '';
    WriteLn('RESULT [', UnformatXMLFilename(ParamStr(3)), ']');
  end
  else if ParamStr(1) = 'format' then
  begin
    XMLPathName := ParamStr(2);
    if XMLPathName = '-' then XMLPathName := '';
    WriteLn('RESULT [', FormatXMLFilename(ParamStr(3)), ']');
  end
  else if ParamStr(1) = 'display' then
    WriteLn('RESULT [', FormatDisplayFilename(ParamStr(2)), ']')
  else if ParamStr(1) = 'child' then
  begin
    { child <design>: for each placed design, the objects the loader reads (RAW), then what the symbol makes of them }
    D := TDesignFile.Create;
    try
      D.AllowEmptySheets := True;
      D.LoadFromFile(ParamStr(2));
      for i := 0 to D.SheetCount - 1 do
        for j := 0 to D.Sheets[i].Drawing.Count - 1 do
          if D.Sheets[i].Drawing[j] is TDrawHierarchicalSymbol then
          begin
            H := D.Sheets[i].Drawing[j] as TDrawHierarchicalSymbol;
            Raw := TDrawingList.Create;
            try
              Ok := HierarchicalLoader(H.FileName, D.Sheets[i].Options, Raw, Err);
              for k := 0 to Raw.Count - 1 do Raw[k].UpdateLayout;      // (the symbol does this before it measures the objects)
              WriteLn('RAW ok=', Ord(Ok), ' err=[', Err, '] count=', Raw.Count, ' objs=', Describe(Raw));
              WriteLn('GRID ', FloatToStrF(D.Sheets[i].Options.Snap.Grid, ffFixed, 15, 5), ' snap=', D.Sheets[i].Options.Snap.GridSnap);
            finally
              Raw.Free;
            end;
            Ok := H.ExtractSymbol(Tr, Objs);
            Pts := H.ActivePoints;
            WriteLn('SYM ok=', Ord(Ok), ' err=[', H.LoadError, '] nosymbol=', Ord(H.IsNoSymbol), ' tr=', Pt(Tr), ' A=', Pt(H.PointA), ' B=', Pt(H.PointB),
              ' file=[', H.FileName, '] name=[', H.Fields[1].Value, '] desc=[', H.Fields[1].Description, '] show=', H.Fields[1].Show, ' objs=', Describe(Objs));
            Write('PINS');
            for k := 0 to High(Pts) do Write(' ', Pt(Pts[k]));
            WriteLn;
            { a copy that has not been read yet: asking it anything reads the design }
            Fresh := H.Clone as TDrawHierarchicalSymbol;
            WriteLn('FRESHTR ', Pt(Fresh.GetTr));
            Fresh.Free;
            Fresh := H.Clone as TDrawHierarchicalSymbol;
            WriteLn('FRESHNOSYM ', Ord(Fresh.IsNoSymbol), ' has=', Ord(Fresh.HasSymbol));
            Fresh.Free;
          end;
    finally
      D.Free;
    end;
  end
  else if ParamStr(1) = 'convert' then
  begin
    D := TDesignFile.Create;
    try
      D.AllowEmptySheets := True;
      try
        D.LoadFromFile(ParamStr(2));
      except
        on E: Exception do
        begin
          WriteLn('ERROR ', E.ClassName, ': ', E.Message);
          Halt(1);
        end;
      end;
      for i := 0 to D.SheetCount - 1 do
      begin
        WriteLn('SHEET ', i, ' hier=', Ord(D.Sheets[i].IsHierarchicalSymbol), ' name=[', D.Sheets[i].SheetName, '] objects=', D.Sheets[i].Drawing.Count);
        for j := 0 to D.Sheets[i].Drawing.Count - 1 do
        begin
          O := D.Sheets[i].Drawing[j];
          if O is TDrawHierarchicalSymbol then
          begin
            H := O as TDrawHierarchicalSymbol;
            WriteLn('OBJ ', Ord(H.GetType), ' file=[', H.FileName, '] rotate=', H.Rotate, ' fields=', Length(H.Fields),
              ' name=[', H.Fields[1].Value, '] A=', H.PointA.x:0:3, ',', H.PointA.y:0:3, ' B=', H.PointB.x:0:3, ',', H.PointB.y:0:3);
          end;
        end;
      end;
      if ParamStr(4) = 'clone' then
        for i := 0 to D.SheetCount - 1 do
          for j := 0 to D.Sheets[i].Drawing.Count - 1 do
            if D.Sheets[i].Drawing[j] is TDrawHierarchicalSymbol then
            begin
              H := D.Sheets[i].Drawing[j].Clone as TDrawHierarchicalSymbol;
              WriteLn('CLONE file=[', H.FileName, '] rotate=', H.Rotate, ' fields=', Length(H.Fields), ' name=[', H.Fields[1].Value,
                '] A=', H.PointA.x:0:3, ',', H.PointA.y:0:3, ' B=', H.PointB.x:0:3, ',', H.PointB.y:0:3, ' scale=', H.ScalingX:0:3, ',', H.ScalingY:0:3, ' can_scale=', Ord(H.CanScale));
              H.Free;
            end;
      if ParamStr(4) = 'rename' then D.Sheets[0].SheetName := 'Other';       // (as if something had given the first sheet another name)
      D.SaveToFile(ParamStr(3));
    finally
      D.Free;
    end;
  end;
end.
