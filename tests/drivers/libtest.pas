{ Test driver for the library layer.
    libtest dump <lib>                  print every set / name / attribute
    libtest blobs <lib> <outdir>        write each set's raw drawing XML as <SymbolID>.xml
    libtest symbols <lib> <out.dsn>     load every name as a design symbol, place them in a design
    libtest blobrt <lib> <outdir>       load each drawing as a symbol document and save it again
    libtest copylib <src> <dst>         create <dst> and store every set of <src> into it
    libtest restore <lib>               re-store every set of <lib> onto itself (an update)
    libtest delete <lib> <SymbolID>     delete one set
    libtest geom <lib>                  UpdateLayout and probe every object of every drawing
    libtest placed <lib>                place every symbol in all 8 rotations (power pins on and off) and check it }
program libtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UDrawingObjects, USymbols, UDesign, ULibrary,
  UGeomProbe, UPlacedProbe, UGeometry;

{ ===========================================================================
  Esc  (function)
  Parameters:
    const S: String - the text
  Returns:
    String - the escaped text
  Notes:
    Escapes backslash, line feed and | so values can be printed on one line.
  =========================================================================== }
function Esc(const S: String): String;
begin
  Result := StringReplace(StringReplace(StringReplace(S, '\', '\\', [rfReplaceAll]),
            #13, '\r', [rfReplaceAll]), #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, '|', '\p', [rfReplaceAll]);
end;

{ ===========================================================================
  SaveBytes  (procedure)
  Parameters:
    const FileName: String - the file
    const Data: String - the bytes
  Notes:
    Writes text bytes to a file unchanged.
  =========================================================================== }
procedure SaveBytes(const FileName, Data: String);
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Data) > 0 then F.WriteBuffer(Data[1], Length(Data));
  finally
    F.Free;
  end;
end;

{ ===========================================================================
  DoDump  (procedure)
  Parameters:
    const LibName: String - the .TCLib file
  Notes:
    Test mode: prints every set, record and attribute of a library.
  =========================================================================== }
procedure DoDump(const LibName: String);
var
  L: TSymbolLibrary;
  i, j, k: Integer;
  S: TLibrarySymbolSet;
  R: TLibraryRecord;
begin
  L := TSymbolLibrary.Create;
  try
    L.Open(LibName);
    for i := 0 to L.SetCount - 1 do
    begin
      S := L.Sets[i];
      WriteLn('SET ', S.SymbolID, ' ', S.Ppp, ' ', S.Orientation, ' ', S.RecordCount);
      for j := 0 to S.RecordCount - 1 do
      begin
        R := S.Records[j];
        L.LoadFields(R);
        WriteLn('REC ', R.NameID, '|', Esc(R.Name), '|', Esc(R.Reference), '|', Esc(R.Description),
                '|', R.NameType, '|', R.RefType);
        for k := 0 to High(R.Fields) do
          WriteLn('FLD ', Esc(R.Fields[k].Name), '|', Esc(R.Fields[k].Default), '|', R.Fields[k].FieldType);
      end;
    end;
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  DoBlobs  (procedure)
  Parameters:
    const LibName: String - the library
    const OutDir: String - folder for the files
  Notes:
    Test mode: writes each set's stored drawing to a file.
  =========================================================================== }
procedure DoBlobs(const LibName, OutDir: String);
var
  L: TSymbolLibrary;
  i: Integer;
begin
  L := TSymbolLibrary.Create;
  try
    L.Open(LibName);
    for i := 0 to L.SetCount - 1 do
      SaveBytes(IncludeTrailingPathDelimiter(OutDir) + IntToStr(L.Sets[i].SymbolID) + '.xml',
                L.GetSymbolBlob(L.Sets[i]));
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  DoSymbols  (procedure)
  Parameters:
    const LibName: String - the library
    const OutName: String - the design file to write
  Notes:
    Test mode "symbols": loads every named symbol of a library as a design symbol and places
    them all in one design, which it saves.
  =========================================================================== }
procedure DoSymbols(const LibName, OutName: String);
var
  L: TSymbolLibrary;
  D: TDesignFile;
  Sh: TDesignSheet;
  i, j, Id, N, Failed: Integer;
  Sym: TDesignFileSymbol;
  M: TDrawMethod;
begin
  L := TSymbolLibrary.Create;
  D := TDesignFile.Create;
  try
    L.Open(LibName);
    Sh := D.AddSheet;
    N := 0;
    Failed := 0;
    for i := 0 to L.SetCount - 1 do
      for j := 0 to L.Sets[i].RecordCount - 1 do
      begin
        Sym := L.GetDesignSymbol(Sh, L.Sets[i], j);
        if Sym = nil then begin Inc(Failed); Continue; end;
        Id := Sh.Options.AddSymbol(Sym);
        M := TDrawMethod.Create(Sh.Options);
        M.SymbolId := Id;
        M.PointA := DPoint(N * 10, 0);
        Sh.Drawing.Add(M);
        Inc(N);
      end;
    WriteLn('placed ', N, ' failed ', Failed);
    D.SaveToFile(OutName);
  finally
    D.Free;
    L.Free;
  end;
end;

{ ===========================================================================
  DoBlobRT  (procedure)
  Parameters:
    const LibName: String - the library
    const OutDir: String - folder for the files
  Notes:
    Test mode: reads each stored drawing as a symbol document and writes it back, to test the
    round trip.
  =========================================================================== }
procedure DoBlobRT(const LibName, OutDir: String);
var
  L: TSymbolLibrary;
  Doc: TSymbolDocument;
  i: Integer;
  B1, B2, B3, Dir: String;
begin
  Dir := IncludeTrailingPathDelimiter(OutDir);
  L := TSymbolLibrary.Create;
  try
    L.Open(LibName);
    for i := 0 to L.SetCount - 1 do
    begin
      Doc := TSymbolDocument.Create;
      try
        Doc.LoadFromBlob(L.GetSymbolBlob(L.Sets[i]));
        B1 := Doc.SaveToBlob;
      finally
        Doc.Free;
      end;
      SaveBytes(Dir + IntToStr(L.Sets[i].SymbolID) + '.rt.xml', B1);
      Doc := TSymbolDocument.Create;
      try
        Doc.LoadFromBlob(B1);
        B2 := Doc.SaveToBlob;
      finally
        Doc.Free;
      end;
      SaveBytes(Dir + IntToStr(L.Sets[i].SymbolID) + '.rt2.xml', B2);
      Doc := TSymbolDocument.Create;
      try
        Doc.LoadFromBlob(B2);
        B3 := Doc.SaveToBlob;
      finally
        Doc.Free;
      end;
      SaveBytes(Dir + IntToStr(L.Sets[i].SymbolID) + '.rt3.xml', B3);
    end;
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  DoCopyLib  (procedure)
  Parameters:
    const SrcName: String - library to copy
    const DstName: String - the new file
  Notes:
    Test mode: copies a library by storing every set into a new file, to test the write path.
  =========================================================================== }
procedure DoCopyLib(const SrcName, DstName: String);
var
  Src, Dst: TSymbolLibrary;
  Doc: TSymbolDocument;
  NewSet: TLibrarySymbolSet;
  i, j: Integer;
  SR, DR: TLibraryRecord;
begin
  Src := TSymbolLibrary.Create;
  Dst := TSymbolLibrary.Create;
  try
    Src.Open(SrcName);
    if FileExists(DstName) then DeleteFile(DstName);
    Dst.CreateNew(DstName);
    for i := 0 to Src.SetCount - 1 do
    begin
      Doc := TSymbolDocument.Create;
      NewSet := TLibrarySymbolSet.Create;
      try
        Doc.LoadFromBlob(Src.GetSymbolBlob(Src.Sets[i]));
        NewSet.Ppp := Src.Sets[i].Ppp;
        NewSet.Orientation := Src.Sets[i].Orientation;
        for j := 0 to Src.Sets[i].RecordCount - 1 do
        begin
          SR := Src.Sets[i].Records[j];
          Src.LoadFields(SR);
          DR := NewSet.AddRecord;
          DR.Name := SR.Name; DR.Reference := SR.Reference; DR.Description := SR.Description;
          DR.NameType := SR.NameType; DR.RefType := SR.RefType;
          DR.Fields := Copy(SR.Fields, 0, Length(SR.Fields));
          DR.FieldsLoaded := True;
        end;
        Dst.StoreSet(NewSet, Doc);
      finally
        NewSet.Free;
        Doc.Free;
      end;
    end;
    WriteLn('copied ', Src.SetCount, ' sets');
  finally
    Dst.Free;
    Src.Free;
  end;
end;

{ ===========================================================================
  DoRestore  (procedure)
  Parameters:
    const LibName: String - the library (a copy)
  Notes:
    Test mode "restore": stores every set of a library back onto itself (an update), to test the
    write path in place.
  =========================================================================== }
procedure DoRestore(const LibName: String);
var
  L: TSymbolLibrary;
  Doc: TSymbolDocument;
  Detached: TLibrarySymbolSet;
  Ids: array of Int64;
  i, j: Integer;
  SR, DR: TLibraryRecord;
  S: TLibrarySymbolSet;
begin
  L := TSymbolLibrary.Create;
  try
    L.Open(LibName);
    SetLength(Ids, L.SetCount);
    for i := 0 to L.SetCount - 1 do Ids[i] := L.Sets[i].SymbolID;
    for i := 0 to High(Ids) do
    begin
      S := L.FindSet(Ids[i]);
      Doc := TSymbolDocument.Create;
      Detached := TLibrarySymbolSet.Create;
      try
        Doc.LoadFromBlob(L.GetSymbolBlob(S));
        Detached.SymbolID := S.SymbolID;   // an update of the existing set
        Detached.Ppp := S.Ppp;
        Detached.Orientation := S.Orientation;
        for j := 0 to S.RecordCount - 1 do
        begin
          SR := S.Records[j];
          L.LoadFields(SR);
          DR := Detached.AddRecord;
          DR.Name := SR.Name; DR.Reference := SR.Reference; DR.Description := SR.Description;
          DR.NameType := SR.NameType; DR.RefType := SR.RefType;
          DR.Fields := Copy(SR.Fields, 0, Length(SR.Fields));
          DR.FieldsLoaded := True;
        end;
        L.StoreSet(Detached, Doc);   // library re-reads: S is invalid from here
      finally
        Detached.Free;
        Doc.Free;
      end;
    end;
    WriteLn('restored ', Length(Ids), ' sets');
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  DoGeom  (procedure)
  Parameters:
    const LibName: String - the library
  Notes:
    Test mode: probes the geometry of every object in every symbol of a library.
  =========================================================================== }
procedure DoGeom(const LibName: String);
var
  L: TSymbolLibrary;
  Doc: TSymbolDocument;
  i, j, k: Integer;
  Sh: TDesignSheet;
  Stats: TProbeStats;
begin
  Stats.Tested := 0; Stats.Failed := 0; Stats.BadBox := 0; Stats.Skipped := 0; Stats.OutsideBox := 0;
  L := TSymbolLibrary.Create;
  try
    L.Open(LibName);
    for i := 0 to L.SetCount - 1 do
    begin
      Doc := TSymbolDocument.Create;
      try
        Doc.LoadFromBlob(L.GetSymbolBlob(L.Sets[i]));
        for k := 0 to Doc.SheetCount - 1 do
        begin
          Sh := Doc.Sheets[k];
          Sh.UpdateLayout;
          for j := 0 to Sh.Drawing.Count - 1 do
            ProbeObject(Sh.Drawing[j], Stats, ExtractFileName(LibName) + '#' + IntToStr(L.Sets[i].SymbolID));
        end;
      finally
        Doc.Free;
      end;
    end;
    WriteLn('geom ', Stats.Tested, ' ', Stats.Failed, ' ', Stats.BadBox, ' ', Stats.Skipped, ' ', Stats.OutsideBox);
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  DoPlaced  (procedure)
  Parameters:
    const LibName: String - the library
  Notes:
    Test mode: places every library symbol in all rotations with power pins on and off and runs
    the placed-symbol checks.
  =========================================================================== }
procedure DoPlaced(const LibName: String);
var
  L: TSymbolLibrary;
  D: TDesignFile;
  Sh: TDesignSheet;
  Sym: TDesignFileSymbol;
  i, j, Rot, Id, Pw: Integer;
  M: TDrawMethod;
  St: TPlacedStats;
begin
  FillChar(St, SizeOf(St), 0);
  L := TSymbolLibrary.Create;
  D := TDesignFile.Create;
  try
    L.Open(LibName);
    Sh := D.AddSheet;
    for i := 0 to L.SetCount - 1 do
      for j := 0 to L.Sets[i].RecordCount - 1 do
      begin
        Sym := L.GetDesignSymbol(Sh, L.Sets[i], j);
        if Sym = nil then Continue;
        Id := Sh.Options.AddSymbol(Sym);
        for Pw := 0 to 1 do
          for Rot := 0 to 7 do
          begin
            M := TDrawMethod.CreateFromSymbol(Sh.Options, Id, Rot);
            try
              M.PointA := DPoint(300, 400);          // a placement somewhere on the sheet
              M.ShowPower := Pw;
              M.NewRotation;
              ProbePlaced(M, St, ExtractFileName(LibName) + ':' + Sym.Name);
            finally
              M.Free;
            end;
          end;
      end;
    WriteLn('placed ', St.Placements, ' ', St.PinPoints, ' ', St.DrawBad, ' ', St.RotateBad, ' ', St.HitBad, ' ', St.BoxBad, ' ', St.ReplaceBad, ' ', St.Inconsistent);
  finally
    D.Free;
    L.Free;
  end;
end;

{ ===========================================================================
  DoDelete  (procedure)
  Parameters:
    const LibName: String - the library (a copy)
    SymbolID: Int64 - database id of the set
  Notes:
    Test mode: deletes one set from a library.
  =========================================================================== }
procedure DoDelete(const LibName: String; SymbolID: Int64);
var
  L: TSymbolLibrary;
begin
  L := TSymbolLibrary.Create;
  try
    L.Open(LibName);
    L.DeleteSet(SymbolID);
    WriteLn('sets left ', L.SetCount);
  finally
    L.Free;
  end;
end;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultSystemCodePage := CP_UTF8;
  if ParamCount < 2 then begin WriteLn('usage: see header'); Halt(2); end;
  try
    if ParamStr(1) = 'dump' then DoDump(ParamStr(2))
    else if ParamStr(1) = 'blobs' then DoBlobs(ParamStr(2), ParamStr(3))
    else if ParamStr(1) = 'symbols' then DoSymbols(ParamStr(2), ParamStr(3))
    else if ParamStr(1) = 'blobrt' then DoBlobRT(ParamStr(2), ParamStr(3))
    else if ParamStr(1) = 'copylib' then DoCopyLib(ParamStr(2), ParamStr(3))
    else if ParamStr(1) = 'restore' then DoRestore(ParamStr(2))
    else if ParamStr(1) = 'delete' then DoDelete(ParamStr(2), StrToInt64(ParamStr(3)))
    else if ParamStr(1) = 'geom' then DoGeom(ParamStr(2))
    else if ParamStr(1) = 'placed' then DoPlaced(ParamStr(2));
  except
    on E: Exception do begin WriteLn('ERROR ', E.ClassName, ': ', E.Message); Halt(3); end;
  end;
end.
