{ Test driver for the old binary .dsn reader.
    dsnbintest detect <file>              print DETECT 1/0: does the stamp say "old binary design"?
    dsnbintest convert <in> <out.xml> [finder]
                                          load a design (binary or XML) and write it as XML. Prints LEGACY, NOTE and the
                                          sheet / object counts. "finder" installs a stand-in library that knows the symbol
                                          names RES and CAP (any case) (as a library would, for the oldest objects that store a name). }
program dsnbintest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, UDPoint, UDrawTypes, UDrawingObjects, USymbols, UDesign, UDsnBinary;

type
  TStandIn = class
    function Find(const Name: String; Sheet: TDesignSheet): TDesignFileSymbol;
  end;

{ ===========================================================================
  TStandIn.Find  (function)
  Parameters:
    const Name: String - the name
    Sheet: TDesignSheet - the sheet
  Returns:
    TDesignFileSymbol
  Notes:
    Takes the place of the open libraries in the tests.
  =========================================================================== }
function TStandIn.Find(const Name: String; Sheet: TDesignSheet): TDesignFileSymbol;
var
  L: TDrawingList;
  Sq: TDrawSquare;
  Opts: TDocOptions;
begin
  Result := nil;
  Opts := Sheet.Options;
  if not (SameText(Name, 'RES') or SameText(Name, 'CAP')) then Exit;
  Result := TDesignFileSymbol.Create(Opts);
  Result.Name := UpperCase(Name);
  Result.Reference := Copy(UpperCase(Name), 1, 1) + '?';
  Result.Description := 'found ' + UpperCase(Name);
  Result.Ppp := 1;
  L := Result.AddMethod;
  Sq := TDrawSquare.CreateKind(Opts, xSquareEx3);
  Sq.PointA := DPoint(0, 0);
  Sq.PointB := DPoint(10, 4);
  L.Add(Sq);
end;

var
  D: TDesignFile;
  StandIn: TStandIn;
  F: TFileStream;
  i, n: Integer;
begin
  StandIn := TStandIn.Create;
  if ParamCount < 2 then
  begin
    WriteLn('usage: dsnbintest detect <file> | convert <in> <out> [finder]');
    Halt(2);
  end;
  if ParamStr(1) = 'detect' then
  begin
    F := TFileStream.Create(ParamStr(2), fmOpenRead or fmShareDenyNone);
    try
      WriteLn('DETECT ', Ord(IsLegacyDsn(F)));
    finally
      F.Free;
    end;
  end
  else if ParamStr(1) = 'convert' then
  begin
    if (ParamCount >= 4) and (ParamStr(4) = 'finder') then LegacySymbolFinder := @StandIn.Find;
    D := TDesignFile.Create;
    try
      try
        D.LoadFromFile(ParamStr(2));
      except
        on E: Exception do
        begin
          WriteLn('ERROR ', E.ClassName, ': ', E.Message);
          Halt(1);
        end;
      end;
      n := 0;
      for i := 0 to D.SheetCount - 1 do n := n + D.Sheets[i].Drawing.Count;
      WriteLn('LEGACY ', Ord(D.LoadedLegacy), ' sheets=', D.SheetCount, ' objects=', n);
      WriteLn('NOTE ', D.LoadNote);
      D.SaveToFile(ParamStr(3));
    finally
      D.Free;
    end;
  end;
end.
