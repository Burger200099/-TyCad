{ Test driver for Find and Replace (UFind). Everything it prints is checked by tests/run_find.py against an
  independent reading of the design's XML.
    findtest hits <design> <needle> <flags>                     every occurrence, in order: HIT sheet objindex slot offset len text
    findtest seq <design> <needle> <flags> <down|up> <steps>    Find Next (or Previous) over and over: SEQ sheet objindex slot offset wrapped
    findtest objects <design> <needle>                          TinyCAD's own Find: OBJ sheet objindex slot x y name|text, one per object
    findtest all <design> <out> <needle> <replacement> <flags>  Replace All, then save: REPLACED count objects
    findtest one <design> <out> <needle> <replacement> <flags>  Find Next and Replace one at a time until it wraps, then save
  flags: letters c (match case) and w (whole word), or - for none }
program findtest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cwstring,{$ENDIF}
  SysUtils, Classes, UDrawingObjects, UDesign, UFind;

{ ===========================================================================
  Flags  (function)
  Parameters:
    const S: String - the letters, or - for none
  Returns:
    TSearchOptions - the options
  Notes:
    Reads the option letters of the driver's command line: c for match case, w for whole word.
  =========================================================================== }
function Flags(const S: String): TSearchOptions;
begin
  Result := [];
  if Pos('c', S) > 0 then Include(Result, foMatchCase);
  if Pos('w', S) > 0 then Include(Result, foWholeWord);
end;

{ ===========================================================================
  Fix  (procedure)
  Parameters:
    var S: String - the text, changed in place
  Notes:
    Makes a text safe to print on one line (line ends shown as \n).
  =========================================================================== }
procedure Fix(var S: String);
begin
  S := StringReplace(StringReplace(S, #10, '\n', [rfReplaceAll]), #13, '', [rfReplaceAll]);
end;

var
  D: TDesignFile;
  Mode, Needle, Repl, Out_: String;
  Opts: TSearchOptions;
  Hits: TFindHitArray;
  OHits: TObjectHitArray;
  Sess: TFindSession;
  i, n, Count, Objs, steps: Integer;
  T: String;
begin
  Mode := ParamStr(1);
  D := TDesignFile.Create;
  try
    D.LoadFromFile(ParamStr(2));
    if Mode = 'hits' then
    begin
      Needle := ParamStr(3);
      Hits := CollectHits(D, Needle, Flags(ParamStr(4)));
      WriteLn('HITS ', Length(Hits));
      for i := 0 to High(Hits) do
      begin
        T := SlotText(Hits[i].Obj, Hits[i].Slot);
        Fix(T);
        WriteLn('HIT ', Hits[i].Sheet, ' ', Hits[i].ObjIndex, ' ', Hits[i].Slot, ' ', Hits[i].Offset, ' ', Hits[i].Len, ' ', T);
      end;
    end
    else if Mode = 'objects' then
    begin
      OHits := FindObjects(D, ParamStr(3));
      WriteLn('OBJECTS ', Length(OHits));
      for i := 0 to High(OHits) do
      begin
        T := OHits[i].Text;
        Fix(T);
        WriteLn('OBJ ', OHits[i].Sheet, ' ', OHits[i].ObjIndex, ' ', OHits[i].Slot, ' ', OHits[i].Point.x:0:3, ' ', OHits[i].Point.y:0:3, ' ', OHits[i].Name, '|', T);
      end;
    end
    else if Mode = 'seq' then
    begin
      Sess := TFindSession.Create;
      try
        Sess.Needle := ParamStr(3);
        Sess.Options := Flags(ParamStr(4));
        steps := StrToInt(ParamStr(6));
        for i := 1 to steps do
          if Sess.FindNext(D, ParamStr(5) = 'down', 0) then
            WriteLn('SEQ ', Sess.Current.Sheet, ' ', Sess.Current.ObjIndex, ' ', Sess.Current.Slot, ' ', Sess.Current.Offset, ' ', Ord(Sess.Wrapped))
          else
            WriteLn('SEQ none');
      finally
        Sess.Free;
      end;
    end
    else if (Mode = 'all') or (Mode = 'one') then
    begin
      Out_ := ParamStr(3); Needle := ParamStr(4); Repl := ParamStr(5);
      Sess := TFindSession.Create;
      try
        Sess.Needle := Needle; Sess.Replacement := Repl; Sess.Options := Flags(ParamStr(6));
        if Mode = 'all' then
        begin
          Count := Sess.ReplaceAll(D, Objs);
          WriteLn('REPLACED ', Count, ' ', Objs);
        end
        else
        begin
          { Find Next, Replace, Find Next ... the way the dialog's Replace button does, until the search wraps }
          Count := 0;
          n := 0;
          while Sess.FindNext(D, True, 0) and (not Sess.Wrapped) and (n < 100000) do
          begin
            if Sess.ReplaceCurrent(D) then Inc(Count);
            Inc(n);
          end;
          for i := 0 to D.SheetCount - 1 do D.Sheets[i].UpdateLayout;
          WriteLn('REPLACED ', Count, ' 0');
        end;
      finally
        Sess.Free;
      end;
      D.SaveToFile(Out_);
    end;
  finally
    D.Free;
  end;
end.
