{ Test driver for the revision ordering and the extended-block fields of a sheet's details (core only). run_revisions.py checks everything it prints against its own
  statement of the rules.
    revtest date <file>              the date key of each line of the file
    revtest cmp <file>               -1, 0 or 1 for each line "labelA<TAB>labelB"
    revtest newest <file>            groups separated by a blank line: first line "date|rev <count> <legacy revision> <legacy date>", then "rev<TAB>date<TAB>author" lines;
                                     for each group the rows chosen, newest first, as "ROW rev<TAB>date<TAB>author"
    revtest dump <design.dsn>        the extended fields of the first sheet's details
    revtest resave <in.dsn> <out.dsn>  load and save again }
program revtest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, UDesign, URevisions;

var
  Mode: String;
  L, G: TStringList;
  i, j, k, Cnt, p1, p2: Integer;
  Line, A, B: String;
  D: TDesignFile;
  Det: TDetails;
  Rv: TRevisionArray;
  Parts: TStringList;
  Fake: TDetails;
begin
  Mode := ParamStr(1);
  L := TStringList.Create;
  try
    if Mode = 'date' then
    begin
      L.LoadFromFile(ParamStr(2));
      for i := 0 to L.Count - 1 do WriteLn(RevisionDateKey(L[i]));
    end
    else if Mode = 'cmp' then
    begin
      L.LoadFromFile(ParamStr(2));
      for i := 0 to L.Count - 1 do
      begin
        p1 := Pos(#9, L[i]);
        WriteLn(CompareRevisionLabels(Copy(L[i], 1, p1 - 1), Copy(L[i], p1 + 1, MaxInt)));
      end;
    end
    else if Mode = 'newest' then
    begin
      L.LoadFromFile(ParamStr(2));
      i := 0;
      Fake := TDetails.Create;
      try
        while i < L.Count do
        begin
          Parts := TStringList.Create;
          try
            Parts.Delimiter := ' '; Parts.StrictDelimiter := True; Parts.DelimitedText := L[i];
            Inc(i);
            SetLength(Fake.Revisions, 0);
            Fake.Revision := ''; Fake.LastChange := '';
            if Parts.Count > 2 then Fake.Revision := StringReplace(Parts[2], '~', ' ', [rfReplaceAll]);
            if Parts.Count > 3 then Fake.LastChange := StringReplace(Parts[3], '~', ' ', [rfReplaceAll]);
            Cnt := StrToInt(Parts[1]);
            while (i < L.Count) and (L[i] <> '') do
            begin
              p1 := Pos(#9, L[i]); p2 := Pos(#9, Copy(L[i], p1 + 1, MaxInt)) + p1;
              Fake.AddRevision(Copy(L[i], 1, p1 - 1), Copy(L[i], p1 + 1, p2 - p1 - 1), Copy(L[i], p2 + 1, MaxInt), '', '');
              Inc(i);
            end;
            Inc(i);                    // the blank line
            Rv := NewestRevisions(Fake.Revisions, Fake.Revision, Fake.LastChange, Parts[0] = 'rev', Cnt);
            WriteLn('GROUP ', Length(Rv));
            for k := 0 to High(Rv) do WriteLn('ROW ', Rv[k].Rev, #9, Rv[k].Date, #9, Rv[k].Author);
          finally
            Parts.Free;
          end;
        end;
      finally
        Fake.Free;
      end;
    end
    else if (Mode = 'dump') or (Mode = 'resave') then
    begin
      D := TDesignFile.Create;
      try
        D.LoadFromFile(ParamStr(2));
        Det := D.Sheets[0].Details;
        WriteLn('EXT ', Ord(Det.ExtendedInfo), ' sort=', Ord(Det.SortByRevision));
        WriteLn('NOTES ', StringReplace(Det.Notes, #10, '\n', [rfReplaceAll]));
        WriteLn('REFERENCE ', StringReplace(Det.Reference, #10, '\n', [rfReplaceAll]));
        WriteLn('REVISION ', Det.Revision, ' effective=', Det.EffectiveRevision, ' date=', Det.EffectiveRevisionDate, ' revs=', Length(Det.Revisions));
        if Mode = 'resave' then D.SaveToFile(ParamStr(3));
      finally
        D.Free;
      end;
    end;
  finally
    L.Free;
  end;
end.
