{ Test driver for copy and paste.
    cliptest copy <in.dsn> <out.xml> all|class:<TClass,...>|index:<i,j,...>
        load a design, select objects of its first sheet and write them as clipboard data
    cliptest paste <clip> <target.dsn|NEW> <out.dsn>
        read clipboard data (or any .dsn) into the first sheet of the target (NEW = an empty A4 design) and save
    cliptest block <clip> <target.dsn|NEW>
        paste, then print the block reference point and the number of objects }
program cliptest;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, UDPoint, UDrawTypes, UDrawingObjects, UDesign, UClip;

{ ===========================================================================
  LoadDesign  (function)
  Parameters:
    const Name: String - a .dsn file, or NEW
  Returns:
    TDesignFile - the design; the caller owns it
  Notes:
    Loads a design (or makes an empty one for the name NEW) with the ids assigned.
  =========================================================================== }
function LoadDesign(const Name: String): TDesignFile;
begin
  Result := TDesignFile.Create;
  Result.AllowEmptySheets := True;
  if Name = 'NEW' then
    Result.AddSheet
  else
  begin
    Result.LoadFromFile(Name);
    Result.AssignIds;
  end;
end;

{ ===========================================================================
  DoCopy  (procedure)
  Parameters:
    const InName: String - the design
    const OutName: String - where to write the data
    const Spec: String - all, class:<names> or index:<numbers>
  Notes:
    Test mode: loads a design, selects objects of its first sheet (all, by class or by position)
    and writes them as clipboard data.
  =========================================================================== }
procedure DoCopy(const InName, OutName, Spec: String);
var
  D: TDesignFile;
  Sel: TList;
  Sl: TStringList;
  i, k: Integer;
  FS: TFileStream;
  O: TDrawingObject;
  Take: Boolean;
begin
  D := LoadDesign(InName);
  Sel := TList.Create;
  Sl := TStringList.Create;
  try
    if Copy(Spec, 1, 6) = 'class:' then begin Sl.CommaText := Copy(Spec, 7, MaxInt); end
    else if Copy(Spec, 1, 6) = 'index:' then begin Sl.CommaText := Copy(Spec, 7, MaxInt); end;
    for i := 0 to D.Sheets[0].Drawing.Count - 1 do
    begin
      O := D.Sheets[0].Drawing[i];
      Take := Spec = 'all';
      if Copy(Spec, 1, 6) = 'class:' then
        for k := 0 to Sl.Count - 1 do if SameText(O.ClassName, Sl[k]) then Take := True;
      if Copy(Spec, 1, 6) = 'index:' then
        for k := 0 to Sl.Count - 1 do if StrToIntDef(Sl[k], -1) = i then Take := True;
      if Take then Sel.Add(O);
    end;
    FS := TFileStream.Create(OutName, fmCreate);
    try
      WriteLn('COPIED ', CopySelection(D.Sheets[0], Sel, FS));
    finally
      FS.Free;
    end;
  finally
    Sl.Free; Sel.Free; D.Free;
  end;
end;

{ ===========================================================================
  DoPaste  (procedure)
  Parameters:
    const ClipName: String - the clipboard data
    const TargetName: String - a design, or NEW
    const OutName: String - where to save
    BlockOnly: Boolean - True to skip saving
  Notes:
    Test mode: pastes clipboard data (or a .dsn) into the first sheet of a design, prints how
    many objects came in and where the block reference is, and saves the result.
  =========================================================================== }
procedure DoPaste(const ClipName, TargetName, OutName: String; BlockOnly: Boolean);
var
  D: TDesignFile;
  Imp: TList;
  FS: TFileStream;
  Before: Integer;
  Ref: TDPoint;
  Ok: Boolean;
begin
  D := LoadDesign(TargetName);
  Imp := TList.Create;
  try
    Before := D.Sheets[0].Drawing.Count;
    FS := TFileStream.Create(ClipName, fmOpenRead);
    try
      Ok := PasteStream(D, D.Sheets[0], FS, Imp);
    finally
      FS.Free;
    end;
    WriteLn('PASTED ', Ord(Ok), ' ', Imp.Count, ' before=', Before, ' after=', D.Sheets[0].Drawing.Count);
    if Ok then
    begin
      Ref := BlockReference(D.Sheets[0], Imp);
      WriteLn('BLOCK ', Ref.x:0:3, ' ', Ref.y:0:3);
    end;
    if not BlockOnly then D.SaveToFile(OutName);
  finally
    Imp.Free; D.Free;
  end;
end;

begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  DefaultSystemCodePage := CP_UTF8;
  if ParamCount < 1 then Halt(2);
  if ParamStr(1) = 'copy' then DoCopy(ParamStr(2), ParamStr(3), ParamStr(4))
  else if ParamStr(1) = 'paste' then DoPaste(ParamStr(2), ParamStr(3), ParamStr(4), False)
  else if ParamStr(1) = 'block' then DoPaste(ParamStr(2), ParamStr(3), '', True);
end.
