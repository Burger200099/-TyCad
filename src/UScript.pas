// SPDX-License-Identifier: LGPL-2.1-or-later
{ A scripting hook for testing the user interface without a person: "schematic --script file"
  runs the commands in the file against the real window, using the same code paths as the mouse and
  the menus, and writes results to standard output and screenshots to files.

    open <file.dsn>                     newdoc "<paper name>" landscape|portrait
    lib <file.TCLib>                    libfilter <text>              libplace <row> <x mm> <y mm>
    ladder <x1> <y1> <x2> <y2>          (mm; also selects it and remembers it for setladder)
    setladder <left> <right> [<width> [<rrggbb>]]
    ladderinfo                          (corners of the ladder made by the ladder command, mm, width, colour)
    rungs                               (the rung numbers function: makes or selects the sheet's rung grid, prints it)
    setrungs <rows> <start> <margin mm> <pages 1|2> [<continue 0|1> [<showheight 0|1> [<aboveblock 0|1>]]]
    rungat <x mm> <y mm>                (prints the rung number there, or none)
    click <px> <py>                     clickmm <x> <y>               selclear   delete   sel
    zoomfit                             zoom <factor>                 info       echo <text>
    save <file.dsn>
    hitmap <file> <x1> <y1> <x2> <y2> <step>   sweep a grid (mm) through the view's hit test; write the hits to <file>
    tool <select|wire|line|polygon|rect|circle|arc|note|cloud|label|junction|rulerh|rulerv|measure|ladder|rungs|xrefline|xrefcontacts>
    mouse <down|move|up|dbl|rdown> <x mm> <y mm>   real mouse events at a design position
    ribbon <button caption>      ribbontab <title>      ribbonstate     setprop <name> <value>     props
    undo   redo   undoinfo       snap on|off     gridmm <v>     gridinfo
    pinsof   (list every connection point of the placed symbols, in design units)
    mousepin <down|move|up|dbl|rdown> <symbol no.> <pin no.> <dx mm> <dy mm>   mouse event near a pin
    objects   (list wires, junctions, etc.)     selectclass <ClassName ...>     addtext <x> <y> <text>     xrefs
    shot <file>          the drawing area            formshot <file>  the whole window
    dialognew <file> "<paper>" landscape|portrait    dialogladder <file>

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UScript;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TypInfo, UStrings, QPropFrame, LMessages, Math, Menus, LCLProc, StdCtrls, ExtCtrls, Dialogs, Forms, Controls, LCLType, Graphics, StrUtils, UDPoint, UDrawTypes, UGeometry, UResources, UDrawingObjects, UDesign, UPaper,
  UView, UPainter, MainForm, UDialogs, Fnewdoc, Fdetails, Fpagesetup, Finput, Fbase, USettings, UProps, UUndo, UEdit, Foptions, Fpartslist, UPartsList, Fnetlist, UNetWriters, USpiceVhdl, Fercopts, UErc, UAnnotate, Fannotate, Fprint, Fpreview, Fexport, Flibraries, ULibManager, USymEdit, Fsymprops, Fsymparts, ULibrary, QLibPanel, UDocs, UTextMetrics, UViewRulers, UPrintRun, UOptions, URepeat, UOrient, FSharedCtls, QPropFrameList, QDemoWireProps, QDemoBadProps, consts, UDocTabs, UPartsDb, UPartData, Fproductpick, USymbols, CFontNameCombo, ComCtrls, crc, QPartsEditor, Fpartedit, Fclassedit, Ffieldedit, Fratingedit, Fobjectedit, Fproductedit, Fvalueedit, Fsymbolinfo;

procedure RunScript(Form: TfrmMain; const FileName: String);

implementation

{ ===========================================================================
  FindDeepComponent  (function)
  Parameters:
    Root: TComponent
    const AName: String - the name
  Returns:
    TComponent - nil when there is none
  Notes:
    A component of the window, or of a frame or form it owns, by its name.
  =========================================================================== }
function FindDeepComponent(Root: TComponent; const AName: String): TComponent;
var
  i: Integer;
  C: TComponent;
begin
  Result := Root.FindComponent(AName);
  if Result <> nil then
    Exit;
  for i := 0 to Root.ComponentCount - 1 do
  begin
    C := Root.Components[i];
    if (C is TFrame) or (C is TCustomForm) then
    begin
      Result := FindDeepComponent(C, AName);
      if Result <> nil then
        Exit;
    end;
  end;
end;

{ ===========================================================================
  ComponentText  (function)
  Parameters:
    Root: TComponent
    const AName: String - component name
    const AProp: String - property name
  Returns:
    String - TEXT <name> <property>=[value], line breaks as \n
  Notes:
    Used by the translation test: the Caption, Hint or Text a component has been given.
  =========================================================================== }
function ComponentText(Root: TComponent; const AName, AProp: String): String;
var
  C: TComponent;
  V: String;
begin
  C := FindDeepComponent(Root, AName);
  if C = nil then
    Exit('TEXT ' + AName + ' ' + AProp + ' none');
  if GetPropInfo(C, AProp) = nil then
    Exit('TEXT ' + AName + ' ' + AProp + ' noproperty');
  V := GetStrProp(C, AProp);
  Result := 'TEXT ' + AName + ' ' + AProp + '=[' + StringReplace(V, #10, '\n', [rfReplaceAll]) + ']';
end;


var
  ScriptParts: TPartsLibrary = nil;      // the parts file the partsopen command opened

{ ===========================================================================
  Tokenize  (procedure)
  Parameters:
    const Line: String - the script line
    Dest: TStringList - receives the words
  Notes:
    Splits a script line into words on spaces; a double-quoted run counts as one word.
  =========================================================================== }
procedure Tokenize(const Line: String; Dest: TStringList);
var
  i: Integer;
  InQ: Boolean;
  Cur: String;
begin
  Dest.Clear;
  Cur := '';
  InQ := False;
  for i := 1 to Length(Line) do
  begin
    if Line[i] = '"' then
      InQ := not InQ
    else if (Line[i] = ' ') and not InQ then
    begin
      if Cur <> '' then
        Dest.Add(Cur);
      Cur := '';
    end
    else
      Cur := Cur + Line[i];
  end;
  if Cur <> '' then
    Dest.Add(Cur);
end;

{ ===========================================================================
  Num  (function)
  Parameters:
    const S: String - the text
  Returns:
    Double - the number
  Notes:
    Converts script text to a number using a dot as the decimal separator.
  =========================================================================== }
function Num(const S: String): Double;
var
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Result := StrToFloat(S, Fs);
end;

{ ===========================================================================
  SaveForm  (procedure)
  Parameters:
    AForm: TCustomForm - the form
    const FileName: String - where to save it
  Notes:
    Saves a picture of a whole form as a bitmap file.
  =========================================================================== }
procedure SaveForm(AForm: TCustomForm; const FileName: String);
var
  B: TBitmap;
begin
  B := AForm.GetFormImage;
  try
    B.SaveToFile(FileName);
  finally
    B.Free;
  end;
end;

{ ===========================================================================
  Settle  (procedure)
  Parameters:  none
  Notes:
    Lets the program process pending events (painting, timers) so the next script step sees a
    settled window.
  =========================================================================== }
procedure Settle;
var
  i: Integer;
begin
  for i := 1 to 4 do Application.ProcessMessages;
end;

{ ===========================================================================
  RunScript  (procedure)
  Parameters:
    Form: TfrmMain - the main window
    const FileName: String - path of the script file
  Notes:
    Runs a self-test script against the real window: each line is a command (open, tool, mouse,
    ribbon, setprop, undo, shot ...) that goes through the same handlers as a person's actions;
    results are written to standard output.
  =========================================================================== }

{ ===========================================================================
  PartCommand  (procedure)
  Parameters:
    Form: TfrmMain - the main form
    T: TStringList - the tokens of the command (pdbchoose, pdbtype, pdbclear, pdbinfo or pdbfit)
  Notes:
    For the self-test script, the part data of placed parts.
      pdbchoose <manufacturer> <model>  the selected placed part gets that product of its part from the open parts library (undoable)
      pdbtype <manufacturer> <model>    the selected placed part gets a product that was only typed (no ratings known)
      pdbclear                          the selected placed part loses its product
      pdbinfo                           PARTINFO <n>|<part name>|<part uid>|<library uid>|<needs>|<manufacturer>|<model>|<product uid>|<haves> for every placed part with part data
      pdbfit                            PARTFIT <verdict> then FITLINE <quantity>|<on>|<need>|<have>|<status> for the selected placed part
  =========================================================================== }
procedure PartCommand(Form: TfrmMain; T: TStringList);
var
  Cmd: String;
  M: TDrawMethod;
  Sym: TDesignFileSymbol;
  PL: TPartsLibrary;
  Pr: TProductInfo;
  Pi, k, n: Integer;
  Ch: TProductChoice;
  Lines: TFitLineArray;
begin
  Cmd := LowerCase(T[0]);
  if Cmd = 'pdbinfo' then
  begin
    n := 0;
    for k := 0 to Form.View.Sheet.Drawing.Count - 1 do
      if Form.View.Sheet.Drawing[k] is TDrawMethod then
      begin
        M := TDrawMethod(Form.View.Sheet.Drawing[k]);
        Sym := Form.View.Sheet.Options.Symbols.Symbol(M.SymbolId);
        if (Sym <> nil) and not Sym.PartInfo.IsEmpty then
          WriteLn('PARTINFO ', n, '|', Sym.PartInfo.Name, '|', Sym.PartInfo.UID, '|', Sym.PartInfo.LibraryUID, '|', Length(Sym.PartInfo.Needs), '|', M.Product.Manufacturer, '|', M.Product.MPN, '|',
            M.Product.UID, '|', Length(M.Product.Haves));
        Inc(n);
      end;
    WriteLn('PARTINFO end');
    Exit;
  end;
  if (Form.View.SelectedCount <> 1) or (not (Form.View.SelectedObject(0) is TDrawMethod)) then
  begin
    WriteLn('PARTCMD noselection');
    Exit;
  end;
  M := TDrawMethod(Form.View.SelectedObject(0));
  Sym := Form.View.Sheet.Options.Symbols.Symbol(M.SymbolId);
  if Cmd = 'pdbfit' then
  begin
    Lines := CheckFit(Sym.PartInfo.Needs, M.Product.Haves);
    WriteLn('PARTFIT ', FitVerdict(Lines));
    for k := 0 to High(Lines) do
      WriteLn('FITLINE ', Lines[k].Need.Quantity, '|', Lines[k].Need.AppliesTo, '|', FloatToStr(Lines[k].NeedValue), '|', IfThen(Lines[k].HaveFound, FloatToStr(Lines[k].HaveValue), '-'), '|',
        FitStatusName(Lines[k].Status));
    Exit;
  end;
  Form.View.BeginChange('Choose product');
  if Cmd = 'pdbclear' then
  begin
    Ch.UID := ''; Ch.Manufacturer := ''; Ch.MPN := ''; SetLength(Ch.Haves, 0);
    M.Product := Ch;
  end
  else if Cmd = 'pdbtype' then
  begin
    Ch.UID := ''; Ch.Manufacturer := T[1]; Ch.MPN := T[2]; SetLength(Ch.Haves, 0);
    M.Product := Ch;
  end
  else
  begin
    PL := Form.frameLibraryPanel.PartsLibrary;
    if PL = nil then
      PL := ScriptParts;
    if PL <> nil then
    begin
      Pi := PL.FindPart(Sym.PartInfo.UID);
      if Pi >= 0 then
        for Pr in PL.Products(PL.Parts[Pi].ID) do
          if (Pr.Manufacturer = T[1]) and (Pr.MPN = T[2]) then
            M.Product := PL.ProductChoiceOf(Pr.ID);
    end;
  end;
  Form.View.CommitChange(True);
  WriteLn('PARTCMD ', M.Product.Manufacturer, '|', M.Product.MPN, '|', Length(M.Product.Haves));
end;

{ ===========================================================================
  ColorHex  (function)
  Parameters:
    C: Cardinal
  Returns:
    String
  Notes:
    A color (red + green * 256 + blue * 65536) as RRGGBB
  =========================================================================== }
function ColorHex(C: Cardinal): String;
begin
  Result := Format('%.2x%.2x%.2x', [C and $FF, (C shr 8) and $FF, (C shr 16) and $FF]);
end;

{ ===========================================================================
  RunScript  (procedure)
  Parameters:
    Form: TfrmMain - the main window
    const FileName: String - path of the script file
  Notes:
    Runs a self-test script against the real window: each line is a command (open, tool, mouse,
    ribbon, setprop, undo, shot ...) that goes through the same handlers as a person's actions;
    results are written to standard output.
  =========================================================================== }

{ ===========================================================================
  LibrariesState  (function)
  Parameters:
    F: TfrmLibraries - the Library Setup dialog
  Returns:
    String - what the dialog shows: the list, the selected name and which buttons are enabled
  Notes:
    For the script command "libraries".
  =========================================================================== }
function LibrariesState(F: TfrmLibraries): String;
var
  i: Integer;
begin
  Result := 'items=[';
  for i := 0 to F.ItemCount - 1 do
  begin
    if i > 0 then
      Result := Result + '|';
    Result := Result + F.ItemText(i);
  end;
  Result := Result + '] sel=[' + F.lbLibs.GetSelectedText + '] file=[' + ExtractFileName(F.SelectedFile) + '] add=' + IntToStr(Ord(F.btnAdd.Enabled)) +
    ' remove=' + IntToStr(Ord(F.btnRemove.Enabled)) + ' new=' + IntToStr(Ord(F.btnNew.Enabled)) + ' edit=' + IntToStr(Ord(F.btnEdit.Enabled)) +
    ' cleanup=' + IntToStr(Ord(F.btnCleanup.Enabled)) + ' upgrade=' + IntToStr(Ord(F.btnUpgrade.Enabled));
end;

{ ===========================================================================
  PeClassCommand  (procedure)
  Parameters:
    Ed: TfrPartsEditor - the parts editor shown
    const Group: String - 'page', 'cls' or 'fld'
    A: TStringList - the '|' separated arguments (at least 10, the first is the sub-command)
  Notes:
    The script side of the Classes page:
      pe page parts|classes                    the page shown                          -> PE page ok <page>
      pe cls rows                              PECLS <depth>|name|parent|abstract|description lines, then PECLSINFO <selected path>|<info label>
      pe cls select|<class>                    chooses the class in the tree           -> PE cls select ok id=<id>
      pe cls add|<name>|<parent>|<0|1>|<desc>  PE cls add ok id=<id> count=<n> | PE cls add error <message>
      pe cls prop|<class>|<name>|<parent>|<0|1>|<desc>, pe cls del|<class>
      pe cls dlg|<class or ''>|<parent>        the Class dialog's parent list: PEDLGPARENT <caption> lines
      pe fld rows|<class>                      PEFLD <name>|<type>|<unit>|<req>|<declared by>|<own 0|1>|<enum>|<description>
      pe fld add|<class>|<name>|<type>|<unit>|<enum>|<0|1>|<desc>, pe fld prop|<class>|<field>|<name>|<type>|<unit>|<enum>|<0|1>|<desc>, pe fld del|<class>|<field>
    Classes are named as in the library (their names are unique); a parent of '' is a root.
  =========================================================================== }
procedure PeClassCommand(Form: TfrmMain; Ed: TfrPartsEditor; const Group: String; A: TStringList);
var
  Sub: String;
  Lib: TPartsLibrary;
  k: Integer;
  Cid, Pid: Int64;
  F: TFieldInfoArray;
  Dlg: TfrmClassEdit;
  OK: Boolean;

  function ClassId(const Name: String): Int64;
  var
    j: Integer;
  begin
    Result := 0;
    for j := 0 to Lib.ClassCount - 1 do
      if SameText(Lib.Classes[j].Name, Name) then
        Result := Lib.Classes[j].ID;
  end;

  function OwnField(ClassID: Int64; const Name: String): Int64;
  var
    j: Integer;
    L: TFieldInfoArray;
  begin
    Result := 0;
    L := Lib.ClassFieldList(ClassID);
    for j := 0 to High(L) do
      if (not L[j].FromParent) and SameText(L[j].Name, Name) then
        Result := L[j].ID;
  end;

  function ParentName(ID: Int64): String;
  begin
    Result := '';
    if ID <> 0 then
      Result := Lib.Classes[Lib.ClassIndexOfID(ID)].Name;
  end;

  procedure Walk(ParentID: Int64; Depth: Integer);
  var
    j: Integer;
    Names: TStringList;
  begin
    Names := TStringList.Create;
    try
      for j := 0 to Lib.ClassCount - 1 do
        if Lib.Classes[j].ParentID = ParentID then
          Names.Add(Lib.Classes[j].Name);
      Names.Sort;
      for j := 0 to Names.Count - 1 do
      begin
        with Lib.Classes[Lib.ClassIndexOfID(ClassId(Names[j]))] do
          WriteLn('PECLS ', Depth, '|', Name, '|', ParentName(ParentID), '|', Ord(Abstract), '|', Description);
        Walk(ClassId(Names[j]), Depth + 1);
      end;
    finally
      Names.Free;
    end;
  end;

  procedure Report(OK: Boolean; const What: String; Extra: String);
  begin
    if OK then
      WriteLn('PE ', Group, ' ', What, ' ok ', Extra)
    else
      WriteLn('PE ', Group, ' ', What, ' error ', Ed.LastError);
  end;

begin
  Lib := Ed.Lib;
  Sub := LowerCase(A[0]);
  if Group = 'page' then
  begin
    Ed.ShowPage(LowerCase(A[0]));
    WriteLn('PE page ok ', Ed.PageName);
  end
  else if Group = 'cls' then
  begin
    if Sub = 'rows' then
    begin
      Walk(0, 0);
      WriteLn('PECLSINFO ', Ed.SelectedClassID, '|', Ed.lblClassInfo.Caption);
    end
    else if Sub = 'select' then
    begin
      Cid := ClassId(A[1]);
      for k := 0 to Ed.tvClasses.Items.Count - 1 do
        if PtrInt(Ed.tvClasses.Items[k].Data) = Cid then
          Ed.tvClasses.Selected := Ed.tvClasses.Items[k];
      WriteLn('PE cls select ok id=', Ed.SelectedClassID);
    end
    else if Sub = 'add' then
    begin
      begin
        OK := Ed.AddClass(A[1], ClassId(A[2]), A[3] = '1', A[4]);
        Report(OK, 'add', 'id=' + IntToStr(Ed.SelectedClassID) + ' count=' + IntToStr(Lib.ClassCount));
      end;
    end
    else if Sub = 'prop' then
      Report(Ed.ChangeClass(ClassId(A[1]), A[2], ClassId(A[3]), A[4] = '1', A[5]), 'prop', '')
    else if Sub = 'del' then
      begin
        OK := Ed.RemoveClass(ClassId(A[1]));
        Report(OK, 'del', 'count=' + IntToStr(Lib.ClassCount));
      end
    else if Sub = 'dlg' then
    begin
      Dlg := TfrmClassEdit.Create(Form);
      try
        Dlg.Setup(Lib, ClassId(A[1]), ClassId(A[2]));
        WriteLn('PEDLG caption=', Dlg.Caption, ' name=', Dlg.edName.Text, ' parent=', Dlg.cbParent.Text, ' abstract=', Ord(Dlg.chAbstract.Checked), ' valid=', Ord(Dlg.Valid));
        for k := 0 to Dlg.cbParent.Items.Count - 1 do
          WriteLn('PEDLGPARENT ', Dlg.cbParent.Items[k]);
      finally
        Dlg.Free;
      end;
    end;
  end
  else if Group = 'fld' then
  begin
    Cid := ClassId(A[1]);
    if Sub = 'rows' then
    begin
      F := Lib.ClassFieldList(Cid);
      for k := 0 to High(F) do
        WriteLn('PEFLD ', F[k].Name, '|', F[k].FieldType, '|', F[k].Unit_, '|', Ord(F[k].Required), '|', F[k].DeclaredBy, '|', Ord(not F[k].FromParent), '|', F[k].EnumValues, '|', F[k].Description);
    end
    else if Sub = 'add' then
      Report(Ed.AddField(Cid, A[2], A[3], A[4], A[5], A[6] = '1', A[7]), 'add', '')
    else if Sub = 'prop' then
    begin
      Pid := OwnField(Cid, A[2]);
      if Pid = 0 then
        WriteLn('PE fld prop error no such own field')
      else
        Report(Ed.ChangeField(Pid, A[3], A[4], A[5], A[6], A[7] = '1', A[8]), 'prop', '');
    end
    else if Sub = 'del' then
    begin
      Pid := OwnField(Cid, A[2]);
      if Pid = 0 then
        WriteLn('PE fld del error no such own field')
      else
        Report(Ed.RemoveField(Pid), 'del', '');
    end;
  end;
end;

{ ===========================================================================
  PeRatCommand  (procedure)
  Parameters:
    Form: TfrmMain - the main form
    Ed: TfrPartsEditor - the parts editor shown
    A: TStringList - the '|' separated arguments (at least 12, the first is the sub-command)
  Notes:
    The script side of the Requirements page (the part shown is chosen with `pe rat part|<name>`; an object is named as in the part, '' = the whole part; numbers are typed
    as a person types them, '' = not given):
      pe rat part|<part name>                      PE rat part ok id=<PartID> rows=<n>
      pe rat rows                                  PERAT <applies to>|<quantity>|<min>|<typ>|<max>|<unit>|<condition> as the list shows them, then PERATINFO part=<name> rows=<n>
      pe rat add|<object>|<quantity>|<unit>|<min>|<typ>|<max>|<condition>      PE rat add ok id=<RatingID> | PE rat add error <message>
      pe rat prop|<row>|<object>|<quantity>|<unit>|<min>|<typ>|<max>|<condition>, pe rat del|<row>, pe rat select|<row>
      pe rat dlg|<row or -1>                       PEDLG caption=.. objects=<n> quantities=<n> object=.. quantity=.. unit=.. sense=.. min=.. typ=.. max=.. condition=.. valid=<0|1>
  =========================================================================== }
procedure PeRatCommand(Form: TfrmMain; Ed: TfrPartsEditor; A: TStringList);
var
  Sub: String;
  Lib: TPartsLibrary;
  k, Row: Integer;
  OK: Boolean;
  Id: Int64;
  Dlg: TfrmRatingEdit;
  HMin, HTyp, HMax: Boolean;
  VMin, VTyp, VMax: Double;

  function ObjectId(const Name: String): Int64;
  var
    j: Integer;
    L: TObjectRefArray;
  begin
    Result := 0;
    if Name = '' then
      Exit;
    L := Lib.PartObjects(Ed.CurrentRatPartID);
    for j := 0 to High(L) do
      if SameText(L[j].Name, Name) then
        Result := L[j].ID;
    if Result = 0 then
      Result := -1;      { (no such object: the library refuses it) }
  end;

  procedure Numbers(const SMin, STyp, SMax: String);
  begin
    ParseRatingNumber(SMin, HMin, VMin);
    ParseRatingNumber(STyp, HTyp, VTyp);
    ParseRatingNumber(SMax, HMax, VMax);
  end;

begin
  Lib := Ed.Lib;
  Sub := LowerCase(A[0]);
  if Sub = 'part' then
  begin
    Id := 0;
    for k := 0 to Lib.PartCount - 1 do
      if SameText(Lib.Parts[k].Name, A[1]) then
        Id := Lib.Parts[k].ID;
    for k := 0 to Ed.cbRatPart.Items.Count - 1 do
      if PtrInt(Ed.cbRatPart.Items.Objects[k]) = Id then
        Ed.cbRatPart.ItemIndex := k;
    Ed.cbRatPart.OnChange(Ed.cbRatPart);
    WriteLn('PE rat part ok id=', Ed.CurrentRatPartID, ' rows=', Ed.lvRatings.Items.Count);
  end
  else if Sub = 'rows' then
  begin
    for k := 0 to Ed.lvRatings.Items.Count - 1 do
      with Ed.lvRatings.Items[k] do
        WriteLn('PERAT ', Caption, '|', SubItems[0], '|', SubItems[1], '|', SubItems[2], '|', SubItems[3], '|', SubItems[4], '|', SubItems[5]);
    WriteLn('PERATINFO part=', Ed.cbRatPart.Text, ' rows=', Ed.lvRatings.Items.Count);
  end
  else if Sub = 'select' then
  begin
    Ed.lvRatings.Selected := nil;
    if StrToInt(A[1]) >= 0 then
      Ed.lvRatings.Items[StrToInt(A[1])].Selected := True;
    WriteLn('PE rat select ok id=', Ed.SelectedRatingID);
  end
  else if Sub = 'add' then
  begin
    Numbers(A[4], A[5], A[6]);
    OK := Ed.AddRequirement(Ed.CurrentRatPartID, ObjectId(A[1]), A[2], A[3], A[7], HMin, HTyp, HMax, VMin, VTyp, VMax);
    if OK then
      WriteLn('PE rat add ok id=', Ed.SelectedRatingID, ' rows=', Ed.lvRatings.Items.Count)
    else
      WriteLn('PE rat add error ', Ed.LastError);
  end
  else if Sub = 'prop' then
  begin
    Row := StrToInt(A[1]);
    Numbers(A[5], A[6], A[7]);
    OK := Ed.ChangeRequirement(Ed.RatingIDOfRow(Row), ObjectId(A[2]), A[3], A[4], A[8], HMin, HTyp, HMax, VMin, VTyp, VMax);
    if OK then
      WriteLn('PE rat prop ok')
    else
      WriteLn('PE rat prop error ', Ed.LastError);
  end
  else if Sub = 'del' then
  begin
    Row := StrToInt(A[1]);
    OK := Ed.RemoveRequirement(Ed.RatingIDOfRow(Row));
    if OK then
      WriteLn('PE rat del ok rows=', Ed.lvRatings.Items.Count)
    else
      WriteLn('PE rat del error ', Ed.LastError);
  end
  else if Sub = 'dlg' then
  begin
    Dlg := TfrmRatingEdit.Create(Form);
    try
      Row := StrToInt(A[1]);
      if Row >= 0 then
        Dlg.Setup(Lib, Ed.CurrentRatPartID, Lib.Ratings(Ed.CurrentRatPartID)[Row], 0)
      else
        Dlg.Setup(Lib, Ed.CurrentRatPartID, Default(TPartRating), 0);
      WriteLn('PEDLG caption=', Dlg.Caption, ' objects=', Dlg.cbObject.Items.Count, ' quantities=', Dlg.cbQuantity.Items.Count, ' object=', Dlg.cbObject.Text, ' quantity=', Dlg.Quantity,
        ' unit=', Dlg.lblUnit.Caption, ' sense=', Dlg.lblSense.Caption, ' min=', Dlg.edMin.Text, ' typ=', Dlg.edTyp.Text, ' max=', Dlg.edMax.Text, ' condition=', Dlg.edCondition.Text,
        ' valid=', Ord(Dlg.Valid));
      for k := 0 to Dlg.cbObject.Items.Count - 1 do
        WriteLn('PEDLGOBJ ', Dlg.cbObject.Items[k]);
    finally
      Dlg.Free;
    end;
  end;
end;

{ ===========================================================================
  PeObjCommand  (procedure)
  Parameters:
    Form: TfrmMain - the main form
    Ed: TfrPartsEditor - the parts editor shown
    A: TStringList - the '|' separated arguments (at least 12, the first is the sub-command)
  Notes:
    The script side of the Objects page (the part shown is chosen with `pe obj part|<name>`; objects, kinds and parents are named, '' as a parent = directly in the part):
      pe obj part|<part name>                      PE obj part ok id=<PartID> rows=<n>
      pe obj rows                                  PEOBJ <depth>|<name [designator] - kind>|<id> for every node of the tree, then PEOBJINFO part=<name> rows=<n> addenabled=<0|1>
      pe obj select|<name>                         PE obj select ok id=<ObjectID>
      pe obj add|<name>|<designator>|<kind>|<parent>|<order>|<description>      PE obj add ok id=<ObjectID> | PE obj add error <message>
      pe obj prop|<object>|<name>|<designator>|<kind>|<parent>|<order>|<description>, pe obj del|<object>
      pe obj dlg|<object or ''>|<default parent>   PEDLG caption=.. kinds=<n> parents=<n> name=.. designator=.. kind=.. parent=.. order=.. then PEDLGKIND / PEDLGPAR lines
  =========================================================================== }
procedure PeObjCommand(Form: TfrmMain; Ed: TfrPartsEditor; A: TStringList);
var
  Sub: String;
  Lib: TPartsLibrary;
  k: Integer;
  OK: Boolean;
  Id: Int64;
  Dlg: TfrmObjectEdit;

  function ObjectId(const Name: String): Int64;
  var
    j: Integer;
    L: TObjectRefArray;
  begin
    Result := 0;
    if Name = '' then
      Exit;
    L := Lib.PartObjects(Ed.CurrentObjPartID);
    for j := 0 to High(L) do
      if SameText(L[j].Name, Name) then
        Result := L[j].ID;
    if Result = 0 then
      Result := -1;      { (no such object: the library refuses it) }
  end;

  function KindId(const Name: String): Int64;
  var
    j: Integer;
    L: TKindInfoArray;
  begin
    Result := 0;
    L := Lib.ObjectKinds(Ed.CurrentObjPartID);
    for j := 0 to High(L) do
      if SameText(L[j].Name, Name) then
        Result := L[j].ID;
    if Result = 0 then
      Result := Lib.KindIDOfName(Name);
  end;

  procedure Walk(Node: TTreeNode; Depth: Integer);
  begin
    while Node <> nil do
    begin
      WriteLn('PEOBJ ', Depth, '|', Node.Text, '|', Ed.ObjectIDOfNode(Node));
      Walk(Node.GetFirstChild, Depth + 1);
      Node := Node.GetNextSibling;
    end;
  end;

begin
  Lib := Ed.Lib;
  Sub := LowerCase(A[0]);
  if Sub = 'part' then
  begin
    Id := 0;
    for k := 0 to Lib.PartCount - 1 do
      if SameText(Lib.Parts[k].Name, A[1]) then
        Id := Lib.Parts[k].ID;
    for k := 0 to Ed.cbObjPart.Items.Count - 1 do
      if PtrInt(Ed.cbObjPart.Items.Objects[k]) = Id then
        Ed.cbObjPart.ItemIndex := k;
    Ed.cbObjPart.OnChange(Ed.cbObjPart);
    WriteLn('PE obj part ok id=', Ed.CurrentObjPartID, ' rows=', Ed.tvObjects.Items.Count);
  end
  else if Sub = 'rows' then
  begin
    Walk(Ed.tvObjects.Items.GetFirstNode, 0);
    WriteLn('PEOBJINFO part=', Ed.cbObjPart.Text, ' rows=', Ed.tvObjects.Items.Count, ' addenabled=', Ord(Ed.btnObjAdd.Enabled), ' editenabled=', Ord(Ed.btnObjEdit.Enabled),
      ' deleteenabled=', Ord(Ed.btnObjDelete.Enabled));
  end
  else if Sub = 'select' then
  begin
    Ed.tvObjects.Selected := nil;
    Id := ObjectId(A[1]);
    for k := 0 to Ed.tvObjects.Items.Count - 1 do
      if Ed.ObjectIDOfNode(Ed.tvObjects.Items[k]) = Id then
        Ed.tvObjects.Selected := Ed.tvObjects.Items[k];
    Ed.ObjChange(nil, nil);
    WriteLn('PE obj select ok id=', Ed.SelectedObjectID);
  end
  else if Sub = 'add' then
  begin
    OK := Ed.AddChildObject(Ed.CurrentObjPartID, ObjectId(A[4]), KindId(A[3]), A[1], A[2], A[6], StrToIntDef(A[5], 0));
    if OK then
      WriteLn('PE obj add ok id=', Ed.SelectedObjectID, ' rows=', Ed.tvObjects.Items.Count)
    else
      WriteLn('PE obj add error ', Ed.LastError);
  end
  else if Sub = 'prop' then
  begin
    OK := Ed.ChangeChildObject(ObjectId(A[1]), ObjectId(A[5]), KindId(A[4]), A[2], A[3], A[7], StrToIntDef(A[6], 0));
    if OK then
      WriteLn('PE obj prop ok')
    else
      WriteLn('PE obj prop error ', Ed.LastError);
  end
  else if Sub = 'del' then
  begin
    OK := Ed.RemoveChildObject(ObjectId(A[1]));
    if OK then
      WriteLn('PE obj del ok rows=', Ed.tvObjects.Items.Count)
    else
      WriteLn('PE obj del error ', Ed.LastError);
  end
  else if Sub = 'dlg' then
  begin
    Dlg := TfrmObjectEdit.Create(Form);
    try
      Dlg.Setup(Lib, Ed.CurrentObjPartID, ObjectId(A[1]), ObjectId(A[2]));
      WriteLn('PEDLG caption=', Dlg.Caption, ' kinds=', Dlg.cbKind.Items.Count, ' parents=', Dlg.cbParent.Items.Count, ' name=', Dlg.edName.Text, ' designator=', Dlg.edDesignator.Text,
        ' kind=', Dlg.cbKind.Text, ' parent=', Dlg.cbParent.Text, ' order=', Dlg.edSort.Text);
      for k := 0 to Dlg.cbKind.Items.Count - 1 do
        WriteLn('PEDLGKIND ', Dlg.cbKind.Items[k]);
      for k := 0 to Dlg.cbParent.Items.Count - 1 do
        WriteLn('PEDLGPAR ', Dlg.cbParent.Items[k]);
    finally
      Dlg.Free;
    end;
  end;
end;

{ ===========================================================================
  PeProdCommand  (procedure)
  Parameters:
    Form: TfrmMain - the main form
    Ed: TfrPartsEditor - the parts editor shown
    A: TStringList - the '|' separated arguments (at least 12, the first is the sub-command)
  Notes:
    The script side of the Products page (rows are the list's, counted from 0; numbers typed as a person types them, '' = not given):
      pe prod part|<part name or ''>               PE prod part ok id=<PartID> rows=<n>
      pe prod rows                                 PEPROD <manufacturer>|<model>|<series>|<class>|<status>|<rev>|<fit>|<suggested>|<description> per row, then PEPRODINFO part=<..> rows=<n> ...enabled flags
      pe prod select|<row>                         PE prod select ok id=<ProductID>
      pe prod add|<manufacturer>|<model>|<series>|<class>|<status>|<description>         PE prod add ok id=<ProductID> | PE prod add error <message>
      pe prod prop|<row>|<manufacturer>|<model>|<series>|<class>|<status>|<description>, pe prod del|<row>, pe prod sug|<row>|<state -1,0,1>
      pe prod rrows                                PEPRODRAT <applies to>|<quantity>|<min>|<typ>|<max>|<unit>|<condition> of the chosen product, then PEPRODRATINFO rows=<n>
      pe prod radd|<applies to>|<quantity>|<unit>|<min>|<typ>|<max>|<condition>, rprop|<row>|<applies to>|<quantity>|<unit>|<min>|<typ>|<max>|<condition>, rdel|<row>, rselect|<row>
      pe prod dlg|<row or -1>                      PEDLG caption=.. classes=<n> manufacturer=.. model=.. series=.. class=.. status=.. description=..
      pe prod rdlg|<row or -1>                     PEDLG caption=.. choices=<n> appliesto=.. quantity=.. unit=.. min=.. typ=.. max=.. condition=.. then PEDLGOBJ lines
  =========================================================================== }
procedure PeProdCommand(Form: TfrmMain; Ed: TfrPartsEditor; A: TStringList);
var
  Sub, Msg: String;
  Lib: TPartsLibrary;
  k, Row: Integer;
  OK: Boolean;
  Id: Int64;
  Dlg: TfrmProductEdit;
  RDlg: TfrmRatingEdit;
  HMin, HTyp, HMax: Boolean;
  VMin, VTyp, VMax: Double;

  function ClassId(const Name: String): Int64;
  var
    j: Integer;
  begin
    Result := 0;
    for j := 0 to Lib.ClassCount - 1 do
      if SameText(Lib.Classes[j].Name, Name) then
        Result := Lib.Classes[j].ID;
  end;

  procedure Numbers(const SMin, STyp, SMax: String);
  begin
    ParseRatingNumber(SMin, HMin, VMin);
    ParseRatingNumber(STyp, HTyp, VTyp);
    ParseRatingNumber(SMax, HMax, VMax);
  end;

begin
  Lib := Ed.Lib;
  Sub := LowerCase(A[0]);
  if Sub = 'part' then
  begin
    Id := 0;
    for k := 0 to Lib.PartCount - 1 do
      if SameText(Lib.Parts[k].Name, A[1]) then
        Id := Lib.Parts[k].ID;
    for k := 0 to Ed.cbProdPart.Items.Count - 1 do
      if PtrInt(Ed.cbProdPart.Items.Objects[k]) = Id then
        Ed.cbProdPart.ItemIndex := k;
    Ed.cbProdPart.OnChange(Ed.cbProdPart);
    WriteLn('PE prod part ok id=', Ed.CurrentProdPartID, ' rows=', Ed.lvProducts.Items.Count);
  end
  else if Sub = 'rows' then
  begin
    for k := 0 to Ed.lvProducts.Items.Count - 1 do
      with Ed.lvProducts.Items[k] do
        WriteLn('PEPROD ', Caption, '|', SubItems[0], '|', SubItems[1], '|', SubItems[2], '|', SubItems[3], '|', SubItems[4], '|', SubItems[5], '|', SubItems[6], '|', SubItems[7]);
    WriteLn('PEPRODINFO part=', Ed.cbProdPart.Text, ' rows=', Ed.lvProducts.Items.Count, ' addenabled=', Ord(Ed.btnProdAdd.Enabled), ' editenabled=', Ord(Ed.btnProdEdit.Enabled),
      ' suggestenabled=', Ord(Ed.btnProdSuggest.Enabled), ' suggestcaption=', StringReplace(Ed.btnProdSuggest.Caption, '&', '', []), ' preferredcaption=', StringReplace(Ed.btnProdPreferred.Caption, '&', '', []));
  end
  else if Sub = 'select' then
  begin
    Ed.lvProducts.Selected := nil;
    if StrToInt(A[1]) >= 0 then
      Ed.lvProducts.Items[StrToInt(A[1])].Selected := True;
    Ed.ProdSelectItem(nil, nil, True);
    WriteLn('PE prod select ok id=', Ed.SelectedProductID);
  end
  else if Sub = 'add' then
  begin
    OK := Ed.AddProductRow(ClassId(A[4]), A[1], A[2], A[3], A[6], A[5]);
    if OK then
      WriteLn('PE prod add ok id=', Ed.SelectedProductID, ' rows=', Ed.lvProducts.Items.Count)
    else
      WriteLn('PE prod add error ', Ed.LastError);
  end
  else if Sub = 'prop' then
  begin
    OK := Ed.ChangeProductRow(Ed.ProductIDOfRow(StrToInt(A[1])), ClassId(A[5]), A[2], A[3], A[4], A[7], A[6]);
    if OK then
      WriteLn('PE prod prop ok')
    else
      WriteLn('PE prod prop error ', Ed.LastError);
  end
  else if Sub = 'del' then
  begin
    OK := Ed.RemoveProductRow(Ed.ProductIDOfRow(StrToInt(A[1])));
    if OK then
      WriteLn('PE prod del ok rows=', Ed.lvProducts.Items.Count)
    else
      WriteLn('PE prod del error ', Ed.LastError);
  end
  else if Sub = 'sug' then
  begin
    OK := Ed.SuggestProductFor(Ed.ProductIDOfRow(StrToInt(A[1])), StrToInt(A[2]));
    if OK then
      WriteLn('PE prod sug ok')
    else
      WriteLn('PE prod sug error ', Ed.LastError);
  end
  else if Sub = 'rrows' then
  begin
    for k := 0 to Ed.lvProdRatings.Items.Count - 1 do
      with Ed.lvProdRatings.Items[k] do
        WriteLn('PEPRODRAT ', Caption, '|', SubItems[0], '|', SubItems[1], '|', SubItems[2], '|', SubItems[3], '|', SubItems[4], '|', SubItems[5]);
    WriteLn('PEPRODRATINFO rows=', Ed.lvProdRatings.Items.Count);
  end
  else if Sub = 'rselect' then
  begin
    Ed.lvProdRatings.Selected := nil;
    if StrToInt(A[1]) >= 0 then
      Ed.lvProdRatings.Items[StrToInt(A[1])].Selected := True;
    WriteLn('PE prod rselect ok id=', Ed.SelectedProdRatingID);
  end
  else if Sub = 'radd' then
  begin
    Numbers(A[4], A[5], A[6]);
    OK := Ed.AddProdRatingRow(Ed.SelectedProductID, A[1], A[2], A[3], A[7], HMin, HTyp, HMax, VMin, VTyp, VMax);
    if OK then
      WriteLn('PE prod radd ok id=', Ed.SelectedProdRatingID, ' rows=', Ed.lvProdRatings.Items.Count)
    else
      WriteLn('PE prod radd error ', Ed.LastError);
  end
  else if Sub = 'rprop' then
  begin
    Numbers(A[5], A[6], A[7]);
    OK := Ed.ChangeProdRatingRow(Ed.ProdRatingIDOfRow(StrToInt(A[1])), A[2], A[3], A[4], A[8], HMin, HTyp, HMax, VMin, VTyp, VMax);
    if OK then
      WriteLn('PE prod rprop ok')
    else
      WriteLn('PE prod rprop error ', Ed.LastError);
  end
  else if (Sub = 'csvimport') or (Sub = 'csvexport') then
  begin
    if Sub = 'csvimport' then
      OK := Ed.ImportProductsFile(A[1], Msg)
    else
      OK := Ed.ExportProductsFile(A[1], Msg);
    if OK then
      WriteLn('PE prod ', Sub, ' ok ', Msg)
    else
      WriteLn('PE prod ', Sub, ' error ', Msg);
  end
  else if Sub = 'rdel' then
  begin
    OK := Ed.RemoveProdRatingRow(Ed.ProdRatingIDOfRow(StrToInt(A[1])));
    if OK then
      WriteLn('PE prod rdel ok rows=', Ed.lvProdRatings.Items.Count)
    else
      WriteLn('PE prod rdel error ', Ed.LastError);
  end
  else if Sub = 'dlg' then
  begin
    Dlg := TfrmProductEdit.Create(Form);
    try
      Row := StrToInt(A[1]);
      if Row >= 0 then
        Dlg.Setup(Lib, Ed.ProductIDOfRow(Row), 0)
      else
        Dlg.Setup(Lib, 0, 0);
      WriteLn('PEDLG caption=', Dlg.Caption, ' classes=', Dlg.cbClass.Items.Count, ' manufacturer=', Dlg.edManufacturer.Text, ' model=', Dlg.edMPN.Text, ' series=', Dlg.edSeries.Text,
        ' class=', Dlg.cbClass.Text, ' status=', Dlg.cbStatus.Text, ' description=', Dlg.edDescription.Text);
      for k := 0 to Dlg.cbClass.Items.Count - 1 do
        WriteLn('PEDLGCLASS ', Dlg.cbClass.Items[k]);
    finally
      Dlg.Free;
    end;
  end
  else if Sub = 'rdlg' then
  begin
    RDlg := TfrmRatingEdit.Create(Form);
    try
      Row := StrToInt(A[1]);
      if Row >= 0 then
        RDlg.SetupProduct(Lib, Ed.SelectedProductID, Lib.ProductRatings(Ed.SelectedProductID)[Row])
      else
        RDlg.SetupProduct(Lib, Ed.SelectedProductID, Default(TPartRating));
      WriteLn('PEDLG caption=', RDlg.Caption, ' choices=', RDlg.cbObject.Items.Count, ' appliesto=', RDlg.cbObject.Text, ' quantity=', RDlg.Quantity, ' unit=', RDlg.lblUnit.Caption,
        ' min=', RDlg.edMin.Text, ' typ=', RDlg.edTyp.Text, ' max=', RDlg.edMax.Text, ' condition=', RDlg.edCondition.Text);
      for k := 0 to RDlg.cbObject.Items.Count - 1 do
        WriteLn('PEDLGOBJ ', RDlg.cbObject.Items[k]);
    finally
      RDlg.Free;
    end;
  end;
end;

{ ===========================================================================
  PeValCommand  (procedure)
  Parameters:
    Form: TfrmMain - the main form
    Ed: TfrPartsEditor - the parts editor shown
    A: TStringList - the '|' separated arguments (at least 12, the first is the sub-command)
  Notes:
    The script side of the Values page (rows counted from 0 as the list shows them):
      pe val part|<part name>                      PE val part ok id=<PartID> rows=<n>
      pe val rows                                  PEVAL <applies to>|<field>|<type>|<unit>|<value>|<required>|<declared by> per row, then PEVALINFO part=<..> rows=<n> editenabled=<0|1> clearenabled=<0|1>
      pe val select|<row>                          PE val select ok row=<row>
      pe val set|<row>|<value>                     PE val set ok | PE val set error <message>;  pe val clear|<row>
      pe val raw|<objectID>|<fieldID>|<value>      the same without a row (ids from the file): PE val raw ok | error <message>
      pe val dlg|<row>                             PEDLG caption=.. info=.. picker=<0|1> value=.. then PEDLGVAL <item> for a list
  =========================================================================== }
procedure PeValCommand(Form: TfrmMain; Ed: TfrPartsEditor; A: TStringList);
var
  Sub: String;
  Lib: TPartsLibrary;
  k, Row: Integer;
  OK: Boolean;
  Id: Int64;
  Dlg: TfrmValueEdit;
begin
  Lib := Ed.Lib;
  Sub := LowerCase(A[0]);
  Row := -1;
  if A[1] <> '' then
    Row := StrToIntDef(A[1], -1);
  if Sub = 'part' then
  begin
    Id := 0;
    for k := 0 to Lib.PartCount - 1 do
      if SameText(Lib.Parts[k].Name, A[1]) then
        Id := Lib.Parts[k].ID;
    for k := 0 to Ed.cbValPart.Items.Count - 1 do
      if PtrInt(Ed.cbValPart.Items.Objects[k]) = Id then
        Ed.cbValPart.ItemIndex := k;
    Ed.cbValPart.OnChange(Ed.cbValPart);
    WriteLn('PE val part ok id=', Ed.CurrentValPartID, ' rows=', Ed.lvValues.Items.Count);
  end
  else if Sub = 'rows' then
  begin
    for k := 0 to Ed.lvValues.Items.Count - 1 do
      with Ed.lvValues.Items[k] do
        WriteLn('PEVAL ', Caption, '|', SubItems[0], '|', SubItems[1], '|', SubItems[2], '|', SubItems[3], '|', SubItems[4], '|', SubItems[5]);
    WriteLn('PEVALINFO part=', Ed.cbValPart.Text, ' rows=', Ed.lvValues.Items.Count, ' editenabled=', Ord(Ed.btnValEdit.Enabled), ' clearenabled=', Ord(Ed.btnValClear.Enabled));
  end
  else if Sub = 'select' then
  begin
    Ed.lvValues.Selected := nil;
    if Row >= 0 then
      Ed.lvValues.Selected := Ed.lvValues.Items[Row];
    Ed.ValSelectItem(nil, nil, True);
    WriteLn('PE val select ok row=', Ed.SelectedValueRow);
  end
  else if Sub = 'raw' then
  begin
    OK := Ed.SetValue(StrToInt64(A[1]), StrToInt64(A[2]), A[3]);
    if OK then
      WriteLn('PE val raw ok')
    else
      WriteLn('PE val raw error ', Ed.LastError);
  end
  else if (Sub = 'set') or (Sub = 'clear') then
  begin
    if Sub = 'clear' then
      A[2] := '';
    OK := Ed.SetValue(Ed.ValueRowObject(Row), Ed.ValueRowField(Row), A[2]);
    if OK then
      WriteLn('PE val ', Sub, ' ok')
    else
      WriteLn('PE val ', Sub, ' error ', Ed.LastError);
  end
  else if Sub = 'dlg' then
  begin
    Dlg := TfrmValueEdit.Create(Form);
    try
      Dlg.Setup(Ed.ValueRowAt(Row));
      WriteLn('PEDLG caption=', Dlg.Caption, ' info=', Dlg.lblInfo.Caption, ' picker=', Ord(Dlg.cbValue.Visible), ' value=', Dlg.ValueText, ' hint=', Dlg.lblHint.Caption);
      for k := 0 to Dlg.cbValue.Items.Count - 1 do
        WriteLn('PEDLGVAL ', Dlg.cbValue.Items[k]);
    finally
      Dlg.Free;
    end;
  end;
end;

{ ===========================================================================
  PeSymCommand  (procedure)
  Parameters:
    Form: TfrmMain - the main window
    Ed: TfrPartsEditor - the parts editor shown
    A: TStringList - the '|' separated arguments (at least 12, the first is the sub-command)
  Notes:
    The script side of the Symbols page (rows counted from 0 as the list shows them):
      pe sym part|<part name>                      PE sym part ok id=<PartID> rows=<n>
      pe sym rows                                  PESYM <name>|<standard>|<purpose>|<default or empty>|<bytes> per row, then PESYMINFO part=<..> rows=<n> + one enabled=<0|1> flag per button
      pe sym select|<row>                          PE sym select ok row=<row>
      pe sym start|<row>|<std>|<purpose>|<name>    the symbol editor on the row (row -1: a new symbol with these properties): PE sym start ok docs=<n> current=<tab>
      pe sym import|<std>|<purpose>|<name>         the symbol chosen in the library panel becomes a symbol of the part: PE sym import ok | error <message>
      pe sym add|<std>|<purpose>|<name>|<file>     a symbol from a file's text without any check of the drawing: PE sym add ok id=<id> | error <message>
      pe sym info|<row>|<std>|<purpose>|<name>     properties; pe sym default|<row>; pe sym del|<row>: PE sym <cmd> ok | error <message>
      pe sym defraw|<symbolID>                     the same as default for a SymbolID from the file (also one of another part)
      pe sym dlg|<row>                             PEDLG caption=.. standard=.. purpose=.. name=.. purposes=<n>
  =========================================================================== }
procedure PeSymCommand(Form: TfrmMain; Ed: TfrPartsEditor; A: TStringList);
var
  Sub, Txt: String;
  Lib: TPartsLibrary;
  k, Row: Integer;
  OK: Boolean;
  Id: Int64;
  Dlg: TfrmSymbolInfo;
  Doc: TDocument;
  SL: TStringList;
begin
  Lib := Ed.Lib;
  Sub := LowerCase(A[0]);
  Row := StrToIntDef(A[1], -1);
  if Sub = 'part' then
  begin
    Id := 0;
    for k := 0 to Lib.PartCount - 1 do
      if SameText(Lib.Parts[k].Name, A[1]) then
        Id := Lib.Parts[k].ID;
    for k := 0 to Ed.cbSymPart.Items.Count - 1 do
      if PtrInt(Ed.cbSymPart.Items.Objects[k]) = Id then
        Ed.cbSymPart.ItemIndex := k;
    Ed.cbSymPart.OnChange(Ed.cbSymPart);
    WriteLn('PE sym part ok id=', Ed.CurrentSymPartID, ' rows=', Ed.lvSymbols.Items.Count);
  end
  else if Sub = 'rows' then
  begin
    for k := 0 to Ed.lvSymbols.Items.Count - 1 do
      with Ed.lvSymbols.Items[k] do
        WriteLn('PESYM ', Caption, '|', SubItems[0], '|', SubItems[1], '|', SubItems[2], '|', SubItems[3]);
    WriteLn('PESYMINFO part=', Ed.cbSymPart.Text, ' rows=', Ed.lvSymbols.Items.Count, ' new=', Ord(Ed.btnSymNew.Enabled), ' edit=', Ord(Ed.btnSymEdit.Enabled), ' import=', Ord(Ed.btnSymImport.Enabled),
      ' props=', Ord(Ed.btnSymProps.Enabled), ' default=', Ord(Ed.btnSymDefault.Enabled), ' delete=', Ord(Ed.btnSymDelete.Enabled));
  end
  else if Sub = 'select' then
  begin
    Ed.lvSymbols.Selected := nil;
    if Row >= 0 then
      Ed.lvSymbols.Selected := Ed.lvSymbols.Items[Row];
    Ed.SymSelectItem(nil, nil, True);
    WriteLn('PE sym select ok row=', Ed.SelectedSymbolRow);
  end
  else if Sub = 'start' then
  begin
    Doc := Form.StartPartSymbol(Ed, Ed.CurrentSymPartID, Ed.SymbolIDOfRow(Row), A[2], A[3], A[4]);
    if Doc = nil then
      WriteLn('PE sym start error no symbol editor')
    else
      WriteLn('PE sym start ok docs=', Form.DocumentCount, ' current=', Form.DocumentIndex);
  end
  else if Sub = 'import' then
  begin
    OK := Form.ImportPanelSymbol(Ed, Ed.CurrentSymPartID, A[1], A[2], A[3], Txt);
    if OK then
      WriteLn('PE sym import ok')
    else
      WriteLn('PE sym import error ', Txt);
  end
  else if Sub = 'add' then
  begin
    SL := TStringList.Create;
    try
      if (A[4] <> '') and FileExists(A[4]) then
        SL.LoadFromFile(A[4]);
      Txt := SL.Text;
    finally
      SL.Free;
    end;
    OK := Ed.AddSymbolDrawing(Ed.CurrentSymPartID, A[1], A[2], A[3], Txt, Id);
    if OK then
      WriteLn('PE sym add ok id=', Id)
    else
      WriteLn('PE sym add error ', Ed.LastError);
  end
  else if Sub = 'info' then
  begin
    if Ed.ChangeSymbolInfo(Ed.SymbolIDOfRow(Row), A[2], A[3], A[4]) then
      WriteLn('PE sym info ok')
    else
      WriteLn('PE sym info error ', Ed.LastError);
  end
  else if Sub = 'default' then
  begin
    if Ed.MakeDefaultSymbol(Ed.SymbolIDOfRow(Row)) then
      WriteLn('PE sym default ok')
    else
      WriteLn('PE sym default error ', Ed.LastError);
  end
  else if Sub = 'defraw' then
  begin
    if Ed.MakeDefaultSymbol(StrToInt64(A[1])) then
      WriteLn('PE sym defraw ok')
    else
      WriteLn('PE sym defraw error ', Ed.LastError);
  end
  else if Sub = 'del' then
  begin
    if Ed.RemoveSymbol(Ed.SymbolIDOfRow(Row)) then
      WriteLn('PE sym del ok')
    else
      WriteLn('PE sym del error ', Ed.LastError);
  end
  else if Sub = 'dlg' then
  begin
    Dlg := TfrmSymbolInfo.Create(Form);
    try
      with Ed.SymbolRowAt(Row) do
        Dlg.Setup(Standard, Purpose, Name);
      WriteLn('PEDLG caption=', Dlg.Caption, ' standard=', Dlg.Standard, ' purpose=', Dlg.Purpose, ' name=', Dlg.SymName, ' purposes=', Dlg.cbPurpose.Items.Count);
    finally
      Dlg.Free;
    end;
  end;
end;

{ ===========================================================================
  Esc  (function)
  Parameters:
    const S: String - text
  Returns:
    String - the text on one line
  Notes:
    Line breaks of a message become " / " so that a script's output stays one line a step.
  =========================================================================== }
function Esc(const S: String): String;
begin
  Result := StringReplace(StringReplace(S, LineEnding, ' / ', [rfReplaceAll]), #10, ' / ', [rfReplaceAll]);
end;

{ ===========================================================================
  SymbolInfoLines  (procedure)
  Parameters:
    Form: TfrmMain - the main window
  Notes:
    For the script commands "sym" and "syminfo": a line SYMINFO about the current document
    (symbol or not) and a SYMPIN line for every pin of every sheet.
  =========================================================================== }
procedure SymbolInfoLines(Form: TfrmMain);
var
  Doc: TDocument;
  i, j, Tabs: Integer;
  Sh: TDesignSheet;
  Pn: TDrawPin;
  TabText, OrgText: String;
  Dot: TFormatSettings;
begin
  Dot := DefaultFormatSettings;
  Dot.DecimalSeparator := '.';
  Doc := Form.CurrentDocument;
  if (Doc = nil) or (Doc.Symbol = nil) then
  begin
    WriteLn('SYMINFO symbol=0 docs=', Form.DocumentCount, ' status=[', Esc(Form.sbMainBar.Panels[0].Text), ']');
    Exit;
  end;
  TabText := '';
  for Tabs := 0 to Form.tcSheetTabs.Tabs.Count - 1 do TabText := TabText + Form.tcSheetTabs.Tabs[Tabs] + '|';
  if Doc.Design.Sheets[0].Options.HasOrigin then
    OrgText := Format('%.3f,%.3f', [Doc.Design.Sheets[0].Options.Origin.x / UNITS_PER_MM, Doc.Design.Sheets[0].Options.Origin.y / UNITS_PER_MM], Dot)
  else
    OrgText := 'none';
  WriteLn('SYMINFO symbol=1 docs=', Form.DocumentCount, ' name=[', Doc.DisplayName, '] tab=[', Doc.TabCaption, '] modified=', Ord(Doc.Modified), ' parts=', Doc.Symbol.PartCount,
    ' hetero=', Ord(Doc.Design.Heterogeneous), ' sheets=', Doc.Design.SheetCount, ' editpart=', Doc.Design.EditPart, ' parttext=[', Form.SymbolPartText, '] tabs=[', TabText, '] tabsvisible=',
    Ord(Form.tcSheetTabs.Visible), ' tabsmatch=', Ord(Form.SheetTabsAreRight), ' titleblock=', Ord(Doc.Design.Sheets[0].Details.IsVisible), ' origin=', OrgText, ' title=[', Form.Caption, '] source=', Doc.Symbol.SourceID, ' lib=[', ExtractFileName(Doc.SymbolLibFile), ']',
    ' status=[', Esc(Form.sbMainBar.Panels[0].Text), ']');
  for i := 0 to Doc.Design.SheetCount - 1 do
  begin
    Sh := Doc.Design.Sheets[i];
    for j := 0 to Sh.Drawing.Count - 1 do
      if Sh.Drawing[j] is TDrawPin then
      begin
        Pn := Sh.Drawing[j] as TDrawPin;
        WriteLn(Format('SYMPIN sheet=%d part=%d num=[%s] name=[%s] x=%.3f y=%.3f dir=%d len=%d which=%d elec=%d show=%d', [i, Pn.Part, Pn.Number, Pn.Str, Pn.PointA.x / UNITS_PER_MM,
          Pn.PointA.y / UNITS_PER_MM, Pn.Dir, Pn.Length, Pn.Which, Pn.Elec, Pn.Show], Dot));
      end;
  end;
end;

{ ===========================================================================
  SymPropsState  (function)
  Parameters:
    F: TfrmSymbolProps - the Symbol Properties dialog
  Returns:
    String - what the dialog shows
  Notes:
    For the script command "symprops": the names, the name showing, the description, the
    orientation, the grid (a row is its three cells), the SPICE texts and the buttons.
  =========================================================================== }
function SymPropsState(F: TfrmSymbolProps): String;
var
  i, r: Integer;
begin
  Result := 'names=[';
  for i := 0 to F.lbNames.Items.Count - 1 do
  begin
    if i > 0 then
      Result := Result + '|';
    Result := Result + F.lbNames.Items[i];
  end;
  Result := Result + '] cur=' + IntToStr(F.CurrentName) + ' lib=[' + F.lblLibrary.Caption + '] parts=[' + F.lblParts.Caption + '] desc=[' + F.edDescription.Text + '] orient=' + IntToStr(F.cbOrientation.ItemIndex) +
    ' grid=[';
  for r := 1 to F.sgFields.RowCount - 1 do
  begin
    if r > 1 then
      Result := Result + ';';
    Result := Result + F.Cell(r, 0) + '~' + F.Cell(r, 1) + '~' + F.Cell(r, 2);
  end;
  Result := Result + '] model=[' + F.edModel.Text + '] prolog=[' + F.edProlog.Text + '] epilog=[' + F.edEpilog.Text + '] prologpri=[' + F.edPrologPri.Text + '] epilogpri=[' + F.edEpilogPri.Text +
    '] delname=' + IntToStr(Ord(F.btnDeleteName.Enabled)) + ' delfield=' + IntToStr(Ord(F.btnDeleteField.Enabled)) + ' tabs=[' + F.pcTabs.Page[0].Caption + '|' + F.pcTabs.Page[1].Caption + ']';
end;

{ ===========================================================================
  ScriptMenu  (procedure)
  Parameters:
    AItem: TMenuItem
    ADepth: Integer - whole number
  Notes:
    Prints the items of a menu as CTX lines (depth, caption with _ for spaces, enabled, key), a
    separator as "-".
  =========================================================================== }
procedure ScriptMenu(AItem: TMenuItem; ADepth: Integer);
var
  i: Integer;
begin
  for i := 0 to AItem.Count - 1 do
  if AItem[i].Visible then      { (an item that is not shown is not in the list) }
  begin
    WriteLn('CTX ', ADepth, ' ', StringReplace(AItem[i].Caption, ' ', '_', [rfReplaceAll]), ' enabled=', Ord(AItem[i].Enabled), ' key=[', ShortCutToText(AItem[i].ShortCut), ']');
    if AItem[i].Count > 0 then
      ScriptMenu(AItem[i], ADepth + 1);
  end;
end;

{ ===========================================================================
  ScriptMenuClick  (function)
  Parameters:
    AItem: TMenuItem
    const APath: String - text
  Returns:
    Boolean
  Notes:
    Does what choosing the item would.
  =========================================================================== }
function ScriptMenuClick(AItem: TMenuItem; const APath: String): Boolean;
var
  i, p: Integer;
  Head: String;
begin
  Result := False;
  p := Pos('/', APath);
  if p > 0 then
    Head := Copy(APath, 1, p - 1)
  else
    Head := APath;
  for i := 0 to AItem.Count - 1 do
    if SameText(AItem[i].Caption, Head) then
    begin
      if p > 0 then
        Result := ScriptMenuClick(AItem[i], Copy(APath, p + 1, MaxInt))
      else if AItem[i].Enabled then
      begin
        AItem[i].Click;
        Result := True;
      end;
      Exit;
    end;
end;

{ ===========================================================================
  RunScript  (procedure)
  Parameters:
    Form: TfrmMain - the main window
    const FileName: String - path of the script file
  Notes:
    Runs a self-test script against the real window: each line is a command (open, tool, mouse,
    ribbon, setprop, undo, shot ...) that goes through the same handlers as a person's actions;
    results are written to standard output.
  =========================================================================== }
procedure RunScript(Form: TfrmMain; const FileName: String);
var
  Lines, T, Lines2, ListAny: TStringList;
  Fr: TFrame;
  PopM: TPopupMenu;
  PeEd: TfrPartsEditor;
  PeArgs: TStringList;
  PeDlg: TfrmPartEdit;
  PeCls, PeId: Int64;
  PeRest: String;
  i, k: Integer;
  Rt: TPartRating;
  Bm: TBitmap;
  Pr: TProductInfo;
  PL: TPartsLibrary;
  Pi: Integer;
  PSteps: array of String;
  Cmd, S: String;
  Lad: TDrawLadder;
  Rg: TDrawRungGrid;
  RgN, RgPg, RgCol: Integer;
  RgR: TDRect;
  P, Fp, Fq: TPoint;
  Before, After: TDPoint;
  F: TfrmNewDoc;
  LF: TLadderForm;
  O: TDrawingObject;
  Fx, Fy: Double;
  m, Fxi: Integer;
  PinList: TPointList;
  Tx: TDrawText;
  Lb: TDrawLabel;
  Kc: Word;
  FTCombo: TFontNameCombo;
  KMsg: TLMKey;
  FS: TFileStream;
  Txt: String;
  DF: TfrmDetails;
  ApplyAll: Boolean;
  PF: TfrmPageSetup;
  Err, FrameValue, Arg: String;
  NI: TfrmNumInput;
  IcoBmp: TBitmap;
  FO: TFindOptions;
  SleepEnd: QWord;
  FDown: Boolean;
  DEd: TEdit;
  DKey: Char;
  Mode: Integer;
  Pg: TDrawPolygon;
  PA: TPolyAction;
  PxPt: TPoint;
  HR: TDRect;
  OptF: TfrmOptions;
  OptD: TOptionsData;
  OptKey, OptVal: String;
  OptBmp: TBitmap;
  OptPng: TPortableNetworkGraphic;
  FitWorks: array of TRect;
  FitParts: TStringList;
  FitRect: TRect;
  FitOk: Boolean;
  Src, Dst: TFileStream;
  OptOk: Boolean;
  OptI: Integer;
  GmJ: Integer;
  GmS: String;
  FontB, FontI: Boolean;
  ColF: TfrmOptions;
  SymF: TfrmSymbolProps;
  SymEd: TSymbolEditor;
  SymP: TfrmSymbolParts;
  SymMsg: String;
  SymDoc: TDocument;
  SymOk: Boolean;
  BomF: TfrmPartsList;
  NetF: TfrmNetlist;
  ExpF: TfrmExportImage;
  LibF: TfrmLibraries;
  NdF: TfrmNewDoc;
  LibList: TStringList;
  SavedSettings: TProgramSettings;
  ErcF: TfrmErcOptions;
  AnnoOpts: TStringList;
  BomOk: Boolean;
  Vhdl: Boolean;
  ColT: TUserColors;
  ColId: Integer;
  ColV: Int64;
  CqOk: Boolean;
  FSize: TDSize;
  SnapP: TDPoint;
  Total, Hits: Integer;
  Res: TStringList;
  FmtDot: TFormatSettings;
begin
  TSchematicView.SuppressMenus := True;      // a script has no one to choose from a pop-up menu
  Form.Quiet := True;                        // and no one to read a message box
  UnregisterPropFrames;                      // the Properties panels start with the editors the program makes by itself (registerframe all shows the real frames)
  Form.PropFramesChanged;
  FmtDot := DefaultFormatSettings;
  FmtDot.DecimalSeparator := '.';
  Lines := TStringList.Create;
  T := TStringList.Create;
  Lad := nil;
  try
    Lines.LoadFromFile(FileName);
    Form.Show;
    Settle;
    { every script starts with the window the same size, whatever size and resolution the form was saved at, so the pictures the scripts take are alike }
    Form.SetBounds(Form.Left, Form.Top, 1417, 854);
    Settle;
    for i := 0 to Lines.Count - 1 do
    begin
      S := Trim(Lines[i]);
      if (S = '') or (S[1] = '#') then
        Continue;
      Tokenize(S, T);
      Cmd := LowerCase(T[0]);
      try
        if Cmd = 'echo' then
          WriteLn(Copy(S, 6, MaxInt))
        else if Cmd = 'open' then
          begin
            Form.OpenDesignFile(T[1]);
            Settle;
            WriteLn('OPEN ', T[1], ' sheets=', Form.Design.SheetCount, ' converted=', Ord(Form.CurrentDocument.ConvertedFrom <> ''),
                    ' name=[', Form.CurrentDocument.DisplayName, '] modified=', Ord(Form.CurrentDocument.Modified),
                    ' status=[', Form.sbMainBar.Panels[0].Text, ']');
          end
        else if Cmd = 'dropfiles' then
          begin
            { dropfiles strip|sheet <file> ... : files dropped from the file explorer on the strip of document tabs or on the drawing; prints DROPFILES opened=<n> docs=<count> }
            ListAny := TStringList.Create;
            try
              for k := 2 to T.Count - 1 do
                ListAny.Add(T[k]);
              if LowerCase(T[1]) = 'strip' then
                k := Form.DropFilesAt(ListAny.ToStringArray, Form.DocTabs.ClientToScreen(Point(Form.DocTabs.Width div 2, Form.DocTabs.Height div 2)))
              else
                k := Form.DropFilesAt(ListAny.ToStringArray, Form.View.ClientToScreen(Point(50, 50)));
            finally
              ListAny.Free;
            end;
            Settle;
            WriteLn('DROPFILES opened=', k, ' docs=', Form.DocTabs.TabCount, ' status=[', Form.sbMainBar.Panels[0].Text, ']');
          end
        else if Cmd = 'newdoc' then
          begin
            Form.NewDesignWith(T[1], (T.Count < 3) or (LowerCase(T[2]) <> 'portrait'));
            Settle; WriteLn('NEWDOC ', T[1]);
          end
        else if Cmd = 'lib' then
          begin
            Form.OpenLibraryFile(T[1]); Settle;
            WriteLn('LIB ', T[1], ' rows=', Form.frameLibraryPanel.RowCount);
          end
        else if Cmd = 'libraries' then
          begin
            { libraries <name>=<value> ... : Library > Libraries... worked step by step as a person would: select=<name> (click a library), add=<file>|<file> (the files the
              Add dialog returns), new=<file> (the name the New dialog returns), remove=1, cleanup=1, inuse=<file>|<file> (these libraries count as being edited; empty for none)
              and ok=1 (close). Prints LIBRARIES start ... (what the dialog shows first) and after each step LIBRARIES <step> ... <list, selection, buttons> status=<first status panel> }
            LibF := Form.BeginLibraries;
            LibList := TStringList.Create;
            try
              WriteLn('LIBRARIES start caption=', LibF.Caption, ' ', LibrariesState(LibF), ' hint_edit=', LibF.btnEdit.Hint <> '', ' ok=', LibF.btnOK.Caption, ' cancel=',
                Ord(LibF.btnCancel.Visible));
              for OptI := 1 to T.Count - 1 do
              begin
                OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
                OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
                Form.sbMainBar.Panels[0].Text := '';
                if OptKey = 'select' then
                  WriteLn('LIBRARIES select found=', Ord(LibF.SelectByName(OptVal)))
                else if OptKey = 'add' then
                begin
                  LibList.Clear;
                  LibList.Delimiter := '|';
                  LibList.StrictDelimiter := True;
                  LibList.DelimitedText := OptVal;
                  LibF.AddFiles(LibList);
                end
                else if OptKey = 'new' then
                  WriteLn('LIBRARIES new made=', Ord(LibF.NewLibrary(OptVal)))
                else if OptKey = 'remove' then
                  LibF.RemoveSelected
                else if OptKey = 'cleanup' then
                  LibF.CleanupSelected
                else if OptKey = 'inuse' then
                begin
                  FreeAndNil(Form.TestLibInUse);
                  if OptVal <> '' then
                  begin
                    Form.TestLibInUse := TStringList.Create;
                    Form.TestLibInUse.Delimiter := '|';
                    Form.TestLibInUse.StrictDelimiter := True;
                    Form.TestLibInUse.DelimitedText := OptVal;
                  end;
                end
                else if OptKey = 'ok' then
                begin
                  WriteLn('LIBRARIES ok');
                  Break;
                end
                else
                  WriteLn('LIBRARIES unknown name: ', OptKey);
                Settle;
                WriteLn('LIBRARIES ', OptKey, ' ', LibrariesState(LibF), ' panel=', Form.frameLibraryPanel.LibCount, ' status=', StringReplace(Form.sbMainBar.Panels[0].Text, LineEnding, ' / ', [rfReplaceAll]));
              end;
            finally
              LibList.Free;
              LibF.Free;
            end;
            Settle;
          end
        else if Cmd = 'librestore' then begin
          WriteLn('LIBRESTORE ', Form.RestoreLibraries);
          Settle;
        end
        else if Cmd = 'libregistry' then
          begin
            { the libraries as the registry holds them now (read afresh, the settings in memory left as they are): LIBREGISTRY <n> <file> ... and LIBREGISTRY done }
            SavedSettings := ProgramSettings;
            try
              LoadSettings;
              for k := 0 to LIBRARY_MAX - 1 do
                if ProgramSettings.LibraryFiles[k] <> '' then
                  WriteLn('LIBREGISTRY ', k + 1, ' ', ProgramSettings.LibraryFiles[k]);
            finally
              ProgramSettings := SavedSettings;
            end;
            WriteLn('LIBREGISTRY done');
          end
        else if Cmd = 'libsettings' then
          begin
            { the libraries in the settings, in order }
            for k := 0 to LIBRARY_MAX - 1 do
              if ProgramSettings.LibraryFiles[k] <> '' then
                WriteLn('LIBSETTING ', k + 1, ' ', ProgramSettings.LibraryFiles[k]);
            WriteLn('LIBSETTINGS done');
          end
        else if Cmd = 'libfilter' then
          begin
            { libfilter <text>: type into the filter box (no text clears it) }
            if T.Count > 1 then
              Form.frameLibraryPanel.edFilter.Text := T[1]
            else
              Form.frameLibraryPanel.edFilter.Text := '';
            Settle;
            WriteLn('LIBFILTER rows=', Form.frameLibraryPanel.RowCount);
          end
        else if Cmd = 'libxml' then
          begin
            { libxml export <lib> <file> [<set>] : writes the XML library file of an open library (all its symbols, or the one set); libxml import <lib> <file> : adds the symbols of
              an XML file to it. Prints LIBXML <what> ok=<0|1> msg=[<message>] }
            if LowerCase(T[1]) = 'export' then
            begin
              if T.Count > 4 then
                OptI := StrToInt(T[4])
              else
                OptI := -1;
              OptOk := Form.ExportLibrarySymbols(StrToInt(T[2]), OptI, T[3], OptKey);
            end
            else
              OptOk := Form.ImportLibrarySymbols(StrToInt(T[2]), T[3], OptKey);
            WriteLn('LIBXML ', T[1], ' ok=', Ord(OptOk), ' msg=[', StringReplace(OptKey, LineEnding, ' / ', [rfReplaceAll]), ']');
            Settle;
          end
        else if Cmd = 'ctxmenu' then
          begin
            { ctxmenu <x mm> <y mm> : right click at a point of the sheet: the object there is chosen, and the menu that would open is listed:
              CTX <depth> <caption> enabled=<0|1> key=<shortcut> }
            Before := DPoint(Num(T[1]) * 5, Num(T[2]) * 5);
            Form.View.ContextSelectAt(Before);
            ScriptMenu(Form.BuildContextMenu(Before).Items, 0);
            WriteLn('CTX done sel=', Form.View.SelectedCount);
          end
        else if Cmd = 'ctxclick' then
          begin
            { ctxclick <caption> : does a command of the menu last built by ctxmenu (a caption with spaces: use _ for the space; "Z-Order/Send_to_Back" for a sub item) }
            OptKey := StringReplace(T[1], '_', ' ', [rfReplaceAll]);
            WriteLn('CTXCLICK ', T[1], ' ok=', Ord(ScriptMenuClick(Form.ContextMenuNow.Items, OptKey)));
            Settle;
          end
        else if Cmd = 'peopen' then
          begin
            { peopen <file> : the parts library editor tab for a file: PEOPEN ok docs=<n> current=<i> caption=<tab caption> or PEOPEN error <message> }
            if Form.OpenPartsEditor(T[1]) <> nil then
              WriteLn('PEOPEN ok docs=', Form.DocumentCount, ' current=', Form.DocumentIndex, ' caption=', Form.DocumentCaption(Form.DocumentIndex))
            else
              WriteLn('PEOPEN error ', Form.PartsEditorError);
            Settle;
          end
        else if Cmd = 'pe' then
          begin
            { pe rows | menu | select <row> | add <name>|<class>|<ref>|<desc> | prop <row>|<name>|<ref>|<desc>|<status> | dup <row>|<name> | del <row> | info <name>|<desc>|<author>
              | dlg add | dlg prop <row> : the parts library editor of the tab shown (the editing calls of TfrPartsEditor without dialogs).
              Each command prints PE <command> ok or PE <command> error <message>; rows prints PEROW <i>|name|class|ref|status|rev|modified|description and PEINFO name|desc|author; menu prints
              PEMENU add=.. props=.. dup=.. del=..; dlg prints PEDLG classes=<n> first=<first class> classenabled=<0|1> status=<> name=<> valid=<0|1> caption=<> }
            PeEd := Form.PartsEditorOfCurrent;
            if PeEd = nil then
              WriteLn('PE ', T[1], ' error no parts editor tab is shown')
            else
            begin
              S := LowerCase(T[1]);
              PeArgs := TStringList.Create;
              try
                PeRest := Trim(Copy(Trim(Lines[i]), Length(T[0]) + 1, MaxInt));
                PeRest := Trim(Copy(PeRest, Length(T[1]) + 1, MaxInt));
                PeArgs.Text := StringReplace(PeRest, '|', LineEnding, [rfReplaceAll]);
                while PeArgs.Count < 12 do
                  PeArgs.Add('');
                if S = 'rows' then
                begin
                  for k := 0 to PeEd.Lib.PartCount - 1 do
                    with PeEd.Lib.Parts[k] do
                      WriteLn('PEROW ', k, '|', Name, '|', ClassName, '|', RefPrefix, '|', Status, '|', Revision, '|', Modified, '|', Description);
                  WriteLn('PEINFO ', PeEd.Lib.LibraryName, '|', PeEd.Lib.LibraryDescription, '|', PeEd.Lib.LibraryAuthor);
                end
                else if S = 'menu' then
                begin
                  Form.mParts.Click;
                  WriteLn('PEMENU add=', Ord(Form.mPartsAdd.Enabled), ' props=', Ord(Form.mPartsProps.Enabled), ' dup=', Ord(Form.mPartsDup.Enabled), ' del=', Ord(Form.mPartsDel.Enabled),
                    ' cadd=', Ord(Form.mPartsClassAdd.Enabled), ' cprops=', Ord(Form.mPartsClassProps.Enabled), ' cdel=', Ord(Form.mPartsClassDel.Enabled),
                    ' fadd=', Ord(Form.mPartsFieldAdd.Enabled), ' fprops=', Ord(Form.mPartsFieldProps.Enabled), ' fdel=', Ord(Form.mPartsFieldDel.Enabled),
                    ' radd=', Ord(Form.mPartsRatAdd.Enabled), ' rprops=', Ord(Form.mPartsRatProps.Enabled), ' rdel=', Ord(Form.mPartsRatDel.Enabled),
                    ' oadd=', Ord(Form.mPartsObjAdd.Enabled), ' oprops=', Ord(Form.mPartsObjProps.Enabled), ' odel=', Ord(Form.mPartsObjDel.Enabled),
                    ' padd=', Ord(Form.mPartsProdAdd.Enabled), ' pprops=', Ord(Form.mPartsProdProps.Enabled), ' pdel=', Ord(Form.mPartsProdDel.Enabled), ' psug=', Ord(Form.mPartsProdSuggest.Enabled),
                    ' ppref=', Ord(Form.mPartsProdPrefer.Enabled), ' pradd=', Ord(Form.mPartsProdRatAdd.Enabled), ' prprops=', Ord(Form.mPartsProdRatProps.Enabled), ' prdel=', Ord(Form.mPartsProdRatDel.Enabled),
                    ' vset=', Ord(Form.mPartsValSet.Enabled), ' vclear=', Ord(Form.mPartsValClear.Enabled),
                    ' symnew=', Ord(Form.mPartsSymNew.Enabled), ' symedit=', Ord(Form.mPartsSymEdit.Enabled), ' symimp=', Ord(Form.mPartsSymImport.Enabled), ' symprops=', Ord(Form.mPartsSymProps.Enabled),
                    ' symdef=', Ord(Form.mPartsSymDefault.Enabled), ' symdel=', Ord(Form.mPartsSymDel.Enabled),
                    ' pimp=', Ord(Form.mPartsProdImport.Enabled), ' pexp=', Ord(Form.mPartsProdExport.Enabled));
                end
                else if (S = 'page') or (S = 'cls') or (S = 'fld') then
                  PeClassCommand(Form, PeEd, S, PeArgs)
                else if S = 'rat' then
                  PeRatCommand(Form, PeEd, PeArgs)
                else if S = 'obj' then
                  PeObjCommand(Form, PeEd, PeArgs)
                else if S = 'prod' then
                  PeProdCommand(Form, PeEd, PeArgs)
                else if S = 'val' then
                  PeValCommand(Form, PeEd, PeArgs)
                else if S = 'sym' then
                  PeSymCommand(Form, PeEd, PeArgs)
                else if S = 'select' then
                begin
                  PeEd.lvParts.Selected := nil;
                  if StrToInt(PeArgs[0]) >= 0 then
                    PeEd.lvParts.Items[StrToInt(PeArgs[0])].Selected := True;
                  WriteLn('PE select ok id=', PeEd.SelectedPartID);
                end
                else if S = 'add' then
                begin
                  PeCls := 0;
                  for k := 0 to PeEd.Lib.ClassCount - 1 do
                    if SameText(PeEd.Lib.Classes[k].Name, PeArgs[1]) then
                      PeCls := PeEd.Lib.Classes[k].ID;
                  if PeEd.AddPart(PeArgs[0], PeCls, PeArgs[2], PeArgs[3]) then
                    WriteLn('PE add ok id=', PeEd.SelectedPartID, ' count=', PeEd.Lib.PartCount)
                  else
                    WriteLn('PE add error ', PeEd.LastError);
                end
                else if S = 'prop' then
                begin
                  PeId := PeEd.Lib.Parts[StrToInt(PeArgs[0])].ID;
                  if PeEd.ChangePart(PeId, PeArgs[1], PeArgs[2], PeArgs[3], PeArgs[4]) then
                    WriteLn('PE prop ok')
                  else
                    WriteLn('PE prop error ', PeEd.LastError);
                end
                else if S = 'dup' then
                begin
                  PeId := PeEd.Lib.Parts[StrToInt(PeArgs[0])].ID;
                  if PeEd.CopyPart(PeId, PeArgs[1]) then
                    WriteLn('PE dup ok id=', PeEd.SelectedPartID, ' count=', PeEd.Lib.PartCount)
                  else
                    WriteLn('PE dup error ', PeEd.LastError);
                end
                else if S = 'del' then
                begin
                  PeId := PeEd.Lib.Parts[StrToInt(PeArgs[0])].ID;
                  WriteLn('PE suggestions=', PeEd.Lib.SuggestionCount(PeId));
                  if PeEd.RemovePart(PeId) then
                    WriteLn('PE del ok count=', PeEd.Lib.PartCount)
                  else
                    WriteLn('PE del error ', PeEd.LastError);
                end
                else if S = 'info' then
                begin
                  if PeEd.ApplyLibraryInfo(PeArgs[0], PeArgs[1], PeArgs[2]) then
                    WriteLn('PE info ok')
                  else
                    WriteLn('PE info error ', PeEd.LastError);
                end
                else if S = 'dlg' then
                begin
                  PeDlg := TfrmPartEdit.Create(Form);
                  try
                    if Copy(LowerCase(PeArgs[0]), 1, 4) = 'prop' then
                      PeDlg.Setup(PeEd.Lib, StrToInt(Trim(Copy(PeArgs[0], 5, MaxInt))))
                    else
                      PeDlg.Setup(PeEd.Lib, -1);
                    WriteLn('PEDLG classes=', PeDlg.cbClass.Items.Count, ' first=', PeDlg.cbClass.Text, ' classenabled=', Ord(PeDlg.cbClass.Enabled), ' status=', PeDlg.Status,
                      ' name=', PeDlg.PartName, ' ref=', PeDlg.RefPrefix, ' valid=', Ord(PeDlg.Valid), ' caption=', PeDlg.Caption);
                    for k := 0 to PeDlg.cbClass.Items.Count - 1 do
                      WriteLn('PEDLGCLASS ', PeDlg.cbClass.Items[k]);
                  finally
                    PeDlg.Free;
                  end;
                end;
              finally
                PeArgs.Free;
              end;
            end;
            Settle;
          end
        else if Cmd = 'popup' then
          begin
            { popup <doc|grid|draw|arc|sheet> [click <caption>] : lists a menu made in the form file, as POPUP <name> <caption>:tag:radio:checked:visible:enabled:wired|... ,
              or (with click) chooses the item with that caption (_ for a space) and prints POPUPCLICK <caption> ok=<0|1> }
            S := LowerCase(T[1]);
            if S = 'draw' then
              begin
                Form.View.PrepareDrawPopup;
                PopM := Form.pmPolyDraw;
              end
            else if S = 'arc' then
              begin
                Form.View.PrepareArcPopup;
                PopM := Form.pmArcDraw;
              end
            else if S = 'grid' then
              PopM := Form.pmGridSize
            else if S = 'sheet' then
              PopM := Form.BuildContextMenu(DPoint(0, 0))
            else
              PopM := Form.pmDocTabs;
            if (T.Count > 3) and (LowerCase(T[2]) = 'click') then
              WriteLn('POPUPCLICK ', T[3], ' ok=', Ord(ScriptMenuClick(PopM.Items, StringReplace(T[3], '_', ' ', [rfReplaceAll]))))
            else
              begin
                S := '';
                for k := 0 to PopM.Items.Count - 1 do
                  begin
                    if k > 0 then
                      S := S + '|';
                    with PopM.Items[k] do
                      S := S + StringReplace(Caption, ' ', '_', [rfReplaceAll]) + ':' + IntToStr(Tag) + ':' + IntToStr(Ord(RadioItem)) + ':' + IntToStr(Ord(Checked)) + ':' +
                        IntToStr(Ord(Visible)) + ':' + IntToStr(Ord(Enabled)) + ':' + IntToStr(Ord(Assigned(OnClick) or (Caption = '-')));
                  end;
                WriteLn('POPUP ', T[1], ' ', S);
              end;
            Settle;
          end
        else if Cmd = 'tabmenu' then
          begin
            { tabmenu <tab> : a right click on a sheet tab (0 = the first), then the menu opens: TABMENU current=<sheet> items=<caption>:<0|1>|... }
            Form.SheetTabRightClick(StrToInt(T[1]));      { (the tabs have no size under the test display, so the click is given as the tab it lands on) }
            Form.pmSheetTabsPopup(Form.pmSheetTabs);
            OptKey := '';
            for k := 0 to Form.pmSheetTabs.Items.Count - 1 do
              OptKey := OptKey + Form.pmSheetTabs.Items[k].Caption + ':' + IntToStr(Ord(Form.pmSheetTabs.Items[k].Enabled)) + '|';
            WriteLn('TABMENU current=', Form.View.SheetIndex, ' items=', OptKey, ' wired=',
              Ord(Form.pmTabInsert.OnClick = @Form.DoInsertSheet), Ord(Form.pmTabDelete.OnClick = @Form.DoRemoveSheet), Ord(Form.pmTabRename.OnClick = @Form.DoRenameSheet),
              Ord(Form.pmTabMoveLeft.OnClick = @Form.DoMoveSheetLeft), Ord(Form.pmTabMoveRight.OnClick = @Form.DoMoveSheetRight),
              Ord(Form.pmTabHier.OnClick = @Form.DoAddHierarchicalSymbol), ' popup=', Ord(Form.tcSheetTabs.PopupMenu = Form.pmSheetTabs));
          end
        else if Cmd = 'tabclick' then
          begin
            { tabclick <caption> : does a command of the sheet tabs' menu (_ for a space) }
            OptKey := StringReplace(T[1], '_', ' ', [rfReplaceAll]);
            WriteLn('TABCLICK ', T[1], ' ok=', Ord(ScriptMenuClick(Form.pmSheetTabs.Items, OptKey)));
            Settle;
          end
        else if Cmd = 'replacesym' then
          begin
            { replacesym <lib> <set> <rec> keep|new : Replace Symbol on the chosen symbol with a symbol of an open library. Prints REPLACESYM ok=<0|1> msg=[...] }
            OptOk := Form.ReplaceSymbolWith(StrToInt(T[1]), StrToInt(T[2]), StrToInt(T[3]), LowerCase(T[4]) = 'keep', OptKey);
            WriteLn('REPLACESYM ok=', Ord(OptOk), ' msg=[', OptKey, ']');
            Settle;
          end
        else if Cmd = 'arctype' then
          begin
            { arctype in|out|show : the kind of arc the Arc tool draws (what its right click menu sets) }
            if LowerCase(T[1]) = 'in' then
              Form.View.ArcToolType := Arc_in
            else if LowerCase(T[1]) = 'out' then
              Form.View.ArcToolType := Arc_out;
            WriteLn('ARCTYPE ', Form.View.ArcToolType, ' in=', Arc_in, ' out=', Arc_out);
          end
        else if Cmd = 'sqlitecheck' then
          begin
            { sqlitecheck <file> : what the program makes of a SQLite library file: SQLITECHECK machine=<hex> x86=<problem> x64=<problem> file=<problem> }
            WriteLn('SQLITECHECK machine=', IntToHex(PeMachine(T[1]), 4), ' x86=[', CpuProblem(T[1], PeMachine(T[1]), False), '] x64=[', CpuProblem(T[1], PeMachine(T[1]), True), '] file=[', SqliteFileProblem(T[1]), ']');
          end
        else if Cmd = 'symsets' then
          begin
            { symsets <lib> : the symbols of an open library as the library holds them: SYMSET <position> id=<SymbolID> ppp=<n> orient=<n> names=<a|b|...> }
            with Form.frameLibraryPanel.LibAt(StrToInt(T[1])) do
              for OptI := 0 to SetCount - 1 do
              begin
                OptKey := '';
                for k := 0 to Sets[OptI].RecordCount - 1 do OptKey := OptKey + Sets[OptI].Records[k].Name + '|';
                WriteLn('SYMSET ', OptI, ' id=', Sets[OptI].SymbolID, ' ppp=', Sets[OptI].Ppp, ' orient=', Sets[OptI].Orientation, ' names=', OptKey);
              end;
            WriteLn('SYMSETS done');
          end
        else if Cmd = 'symmenu' then
          begin
            { symmenu : the symbol commands of the Library menu as the menu shows them when it opens: SYMMENU new=<0|1> edit= duplicate= delete= props= pin= origin= symprops= parts= prev= next= store=
              (1 = enabled) and the checked tool item }
            Form.LibraryMenuOpen(nil);
            with Form do
              WriteLn('SYMMENU new=', Ord(miSymNew.Enabled), ' edit=', Ord(miSymEdit.Enabled), ' duplicate=', Ord(miSymDuplicate.Enabled), ' delete=', Ord(miSymDelete.Enabled), ' props=',
                Ord(miSymCommandProps.Enabled), ' pin=', Ord(miSymPin.Enabled), ' origin=', Ord(miSymOrigin.Enabled), ' symprops=', Ord(miSymProps.Enabled), ' parts=', Ord(miSymParts.Enabled),
                ' prev=', Ord(miSymPrevPart.Enabled), ' next=', Ord(miSymNextPart.Enabled), ' store=', Ord(miSymStore.Enabled), ' pinchecked=', Ord(miSymPin.Checked), ' originchecked=', Ord(miSymOrigin.Checked));
          end
        else if Cmd = 'syminfo' then
          SymbolInfoLines(Form)
        else if Cmd = 'sym' then
          begin
            { sym <name>=<value> ... : the symbol editor's commands, one step at a time; after each step SYM <step> ok=<0|1> msg=[<message>] and the SYMINFO of the current document.
              new=<lib> (New symbol in the open library number <lib>), edit=<lib>:<set>, store=1 (Store in library, without the dialog), delete=<lib>:<set>, dup=<lib>:<set>,
              copy=<lib>:<set>:<target library>, part=<n> (draw part n, 1-based), cmd=<new|edit|delete|duplicate> (the library list's command on its selection),
              addsheet=1 (tries Add sheet), close=1 (closes the document without asking) }
            for OptI := 1 to T.Count - 1 do
            begin
              OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
              OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
              Form.sbMainBar.Panels[0].Text := '';
              SymMsg := '';
              SymOk := True;
              if OptKey = 'new' then
                SymOk := Form.NewSymbolDoc(StrToInt(OptVal)) <> nil
              else if OptKey = 'edit' then
                SymOk := Form.OpenSymbolDoc(StrToInt(Copy(OptVal, 1, Pos(':', OptVal) - 1)), StrToInt(Copy(OptVal, Pos(':', OptVal) + 1, MaxInt))) <> nil
              else if OptKey = 'store' then
                SymOk := Form.StoreSymbolDoc(Form.CurrentDocument, SymMsg)
              else if OptKey = 'delete' then
                SymOk := Form.DeleteLibrarySymbol(StrToInt(Copy(OptVal, 1, Pos(':', OptVal) - 1)), StrToInt(Copy(OptVal, Pos(':', OptVal) + 1, MaxInt)), SymMsg)
              else if OptKey = 'dup' then
                SymOk := Form.DuplicateLibrarySymbol(StrToInt(Copy(OptVal, 1, Pos(':', OptVal) - 1)), StrToInt(Copy(OptVal, Pos(':', OptVal) + 1, MaxInt)), SymMsg)
              else if OptKey = 'copy' then
              begin
                SymOk := Form.CopyLibrarySymbol(StrToInt(ExtractWord(1, OptVal, [':'])), StrToInt(ExtractWord(2, OptVal, [':'])), StrToInt(ExtractWord(3, OptVal, [':'])), SymMsg);
              end
              else if OptKey = 'part' then
                Form.ShowSymbolPart(StrToInt(OptVal) - 1)
              else if OptKey = 'cmd' then
              begin
                if OptVal = 'new' then
                  Form.frameLibraryPanel.Command(scNew)
                else if OptVal = 'edit' then
                  Form.frameLibraryPanel.Command(scEdit)
                else if OptVal = 'delete' then
                  Form.frameLibraryPanel.Command(scDelete)
                else if OptVal = 'duplicate' then
                  Form.frameLibraryPanel.Command(scDuplicate)
                else
                  SymOk := False;
              end
              else if OptKey = 'addsheet' then
                Form.DoAddSheet(nil)
              else if OptKey = 'close' then
                SymOk := Form.CloseDocument(Form.DocumentIndex, False)
              else begin
                WriteLn('SYM unknown name: ', OptKey);
                SymOk := False;
              end;
              Settle;
              WriteLn('SYM ', OptKey, ' ok=', Ord(SymOk), ' msg=[', Esc(SymMsg), '] libs=', Form.frameLibraryPanel.LibCount, ' symbols=', Form.frameLibraryPanel.RowCount);
              SymbolInfoLines(Form);
            end;
          end
        else if Cmd = 'symprops' then
          begin
            { symprops <name>=<value> ... : the Symbol Properties dialog of the current symbol, a step at a time as a person works it: select=<i> (0-based), addname=1, delname=1,
              desc=<text>, orient=<0-3>, shot=<png> (a picture of the window), cell=<row>:<col>:<text> (row 1 is Reference), addfield=1, delfield=<row>, model= prolog= epilog= prologpri= epilogpri=, ok=1, cancel=1.
              Prints SYMPROPS start and after each step SYMPROPS <step> <what the dialog shows> }
            { A first word lib=<library>:<symbol> (0-based, as in the library list) works on that symbol on its own, as Symbol properties in the library list does: no tab,
              OK stores the change in the library and prints SYMPROPS stored ok=<0|1> msg=[...] }
            SymEd := nil;
            OptI := 1;
            if (T.Count > 1) and (LowerCase(Copy(T[1], 1, 4)) = 'lib=') then
            begin
              SymF := Form.BeginLibraryProps(StrToInt(ExtractWord(1, Copy(T[1], 5, MaxInt), [':'])), StrToInt(ExtractWord(2, Copy(T[1], 5, MaxInt), [':'])), SymEd);
              OptI := 2;
            end
            else
              SymF := Form.BeginSymbolProps;
            if SymF = nil then
              WriteLn('SYMPROPS no symbol')
            else
            try
              WriteLn('SYMPROPS start ', SymPropsState(SymF), ' ok=', SymF.btnOK.Caption, ' cancel=', SymF.btnCancel.Caption);
              while OptI < T.Count do
              begin
                OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
                OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
                if OptKey = 'select' then
                  SymF.SelectName(StrToInt(OptVal))
                else if OptKey = 'shot' then begin
                  SymF.Show;
                  Settle;
                  SaveForm(SymF, OptVal);
                  WriteLn('SYMPROPS shot ', OptVal);
                end
                else if OptKey = 'addname' then
                  SymF.AddName
                else if OptKey = 'delname' then
                  SymF.DeleteName
                else if OptKey = 'desc' then
                  SymF.edDescription.Text := OptVal
                else if OptKey = 'orient' then
                  SymF.cbOrientation.ItemIndex := StrToInt(OptVal)
                else if OptKey = 'cell' then
                  SymF.SetCell(StrToInt(ExtractWord(1, OptVal, [':'])), StrToInt(ExtractWord(2, OptVal, [':'])), Copy(OptVal, Pos(':', Copy(OptVal, Pos(':', OptVal) + 1, MaxInt)) + Pos(':', OptVal) + 1, MaxInt))
                else if OptKey = 'addfield' then
                  SymF.AddField
                else if OptKey = 'delfield' then
                  SymF.DeleteField(StrToInt(OptVal))
                else if OptKey = 'model' then
                  SymF.edModel.Text := OptVal
                else if OptKey = 'prolog' then
                  SymF.edProlog.Text := OptVal
                else if OptKey = 'epilog' then
                  SymF.edEpilog.Text := OptVal
                else if OptKey = 'prologpri' then
                  SymF.edPrologPri.Text := OptVal
                else if OptKey = 'epilogpri' then
                  SymF.edEpilogPri.Text := OptVal
                else if OptKey = 'ok' then
                begin
                  if SymEd <> nil then
                  begin
                    SymOk := Form.EndLibraryProps(SymF, SymEd, True, SymMsg);
                    WriteLn('SYMPROPS stored ok=', Ord(SymOk), ' msg=[', Esc(SymMsg), ']');
                  end
                  else
                    Form.EndSymbolProps(SymF, True);
                  WriteLn('SYMPROPS ok');
                  Break;
                end
                else if OptKey = 'cancel' then
                begin
                  if SymEd <> nil then
                    Form.EndLibraryProps(SymF, SymEd, False, SymMsg)
                  else
                    Form.EndSymbolProps(SymF, False);
                  WriteLn('SYMPROPS cancel');
                  Break;
                end
                else
                  WriteLn('SYMPROPS unknown name: ', OptKey);
                Settle;
                WriteLn('SYMPROPS ', OptKey, ' ', SymPropsState(SymF));
                Inc(OptI);
              end;
            finally
              SymF.Free;
              SymEd.Free;
            end;
            Settle;
            SymbolInfoLines(Form);
          end
        else if Cmd = 'symparts' then
          begin
            { symparts <name>=<value> ... : the Parts per Package dialog of the current symbol: parts=<n>, hetero=<0|1>, ok=1, cancel=1; SYMPARTS <step> parts=<n> hetero=<0|1> heteroenabled=<0|1> }
            SymP := Form.BeginSymbolParts;
            if SymP = nil then
              WriteLn('SYMPARTS no symbol')
            else
            try
              WriteLn('SYMPARTS start parts=', SymP.Parts, ' hetero=', Ord(SymP.Hetero), ' heteroenabled=', Ord(SymP.HeteroEnabled));
              for OptI := 1 to T.Count - 1 do
              begin
                OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
                OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
                if OptKey = 'shot' then begin
                  SymP.Show;
                  Settle;
                  SaveForm(SymP, OptVal);
                  WriteLn('SYMPARTS shot ', OptVal);
                end
                else if OptKey = 'parts' then
                  SymP.SetParts(StrToInt(OptVal))
                else if OptKey = 'hetero' then
                  SymP.SetHetero(OptVal = '1')
                else if OptKey = 'ok' then begin
                  Form.EndSymbolParts(SymP, True);
                  WriteLn('SYMPARTS ok');
                  Break;
                end
                else if OptKey = 'cancel' then begin
                  Form.EndSymbolParts(SymP, False);
                  WriteLn('SYMPARTS cancel');
                  Break;
                end
                else
                  WriteLn('SYMPARTS unknown name: ', OptKey);
                WriteLn('SYMPARTS ', OptKey, ' parts=', SymP.Parts, ' hetero=', Ord(SymP.Hetero), ' heteroenabled=', Ord(SymP.HeteroEnabled));
              end;
            finally
              SymP.Free;
            end;
            Settle;
            SymbolInfoLines(Form);
          end
        else if Cmd = 'libtree' then
          begin
            { the tree as it is: a line per node, level 0 = a library file, level 1 = a symbol }
            for k := 0 to Form.frameLibraryPanel.tvLib.Items.Count - 1 do
              WriteLn('LIBNODE ', Form.frameLibraryPanel.tvLib.Items[k].Level, ' open=', Ord(Form.frameLibraryPanel.tvLib.Items[k].Expanded),
                ' ', Form.frameLibraryPanel.tvLib.Items[k].Text);
            WriteLn('LIBTREE libs=', Form.frameLibraryPanel.LibCount, ' symbols=', Form.frameLibraryPanel.RowCount);
          end
        else if Cmd = 'libclose' then
          begin
            if StrToIntDef(T[1], -1) < 0 then
              Form.frameLibraryPanel.CloseAll
            else
              Form.frameLibraryPanel.CloseLibrary(StrToInt(T[1]));
            Settle;
            WriteLn('LIBCLOSE libs=', Form.frameLibraryPanel.LibCount, ' symbols=', Form.frameLibraryPanel.RowCount);
          end
        else if Cmd = 'libselect' then
          begin
            Form.frameLibraryPanel.SelectRow(StrToInt(T[1]));
            Settle;
            WriteLn('LIBSELECT ', Form.frameLibraryPanel.RowText(StrToInt(T[1])));
          end
        else if Cmd = 'previewdbl' then
          begin
            { previewdbl <row> : chooses the symbol of a row, then double clicks the preview pane (the one of the library panel): PREVIEWDBL tool=<tool number> placing=<0|1> }
            Form.frameLibraryPanel.SelectRow(StrToInt(T[1]));
            Form.frameLibraryPanel.pbPreview.OnDblClick(Form.frameLibraryPanel.pbPreview);
            Settle;
            WriteLn('PREVIEWDBL tool=', Ord(Form.View.Tool), ' placing=', Ord(Form.View.Tool = vtPlace));
          end
        else if Cmd = 'fonttype' then
          begin
            { fonttype <ms>:<char> ... : keys typed into a font drop-down that lists Arial, Cambria, Comic Sans MS, Consolas, Courier, Courier New, Verdana (the time of each in
              milliseconds, a char of _ is a space); prints FONTTYPE <chosen after each key, - for none> }
            FTCombo := TFontNameCombo.Create(Form);
            try
              FTCombo.Parent := Form;
              FTCombo.Items.CommaText := 'Arial,Cambria,"Comic Sans MS",Consolas,Courier,"Courier New",Verdana';
              S := '';
              for k := 1 to T.Count - 1 do
              begin
                FTCombo.TypeAhead(StringReplace(Copy(T[k], Pos(':', T[k]) + 1, 1), '_', ' ', [])[1], StrToInt(Copy(T[k], 1, Pos(':', T[k]) - 1)));
                if FTCombo.ItemIndex >= 0 then
                  S := S + FTCombo.Items[FTCombo.ItemIndex] + '|'
                else
                  S := S + '-|';
              end;
              WriteLn('FONTTYPE ', S);
            finally
              FTCombo.Free;
            end;
          end
        else if Cmd = 'viewkey' then
          begin
            { viewkey <r|x|esc> : the key pressed on the sheet }
            if LowerCase(T[1]) = 'r' then
              Form.View.PressKey(VK_R, [])
            else if LowerCase(T[1]) = 'x' then
              Form.View.PressKey(VK_X, [])
            else
              Form.View.PressKey(VK_ESCAPE, []);
            Settle;
            WriteLn('VIEWKEY ', T[1]);
          end
        else if Cmd = 'vieworigin' then
          WriteLn('VIEWORIGIN ', FormatFloat('0.###', Form.View.Origin.x / 5, FmtDot), ' ', FormatFloat('0.###', Form.View.Origin.y / 5, FmtDot))
        else if Cmd = 'formdel' then
          begin
            { formdel : Del pressed on the main form (the key handler, then the Delete menu command the shortcut runs); prints FORMDEL objects=<n> text=<focused box text> }
            Kc := VK_DELETE;
            Form.FormKeyDown(Form, Kc, []);
            Form.DoDelete(nil);
            Settle;
            if Form.ActiveControl is TEdit then
              WriteLn('FORMDEL objects=', Form.View.Sheet.Drawing.Count, ' text="', TEdit(Form.ActiveControl).Text, '"')
            else
              WriteLn('FORMDEL objects=', Form.View.Sheet.Drawing.Count, ' text=-');
          end
        else if Cmd = 'dragmode' then
          WriteLn('DRAGMODE ', Form.View.DragMode)
        else if Cmd = 'libghost' then
          begin
            { libghost <row> : the symbol of the row follows the pointer (no click yet); prints GHOST <width> <height> of its box in design units, or GHOST none }
            Form.frameLibraryPanel.SelectRow(StrToInt(T[1]));
            Form.frameLibraryPanel.PlaceSelected;
            Settle;
          end
        else if Cmd = 'ghostinfo' then
          begin
            if Form.View.PlaceGhost = nil then
              WriteLn('GHOST none')
            else
              with Form.View.PlaceGhost do
                WriteLn('GHOST ', FormatFloat('0.###', Abs(PointB.x - PointA.x)), ' ', FormatFloat('0.###', Abs(PointB.y - PointA.y)), ' tool=', Ord(Form.View.Tool));
          end
        else if Cmd = 'libplace' then
          begin Form.PlaceLibraryRow(StrToInt(T[1]), Num(T[2]), Num(T[3]));
            Settle;
            WriteLn('LIBPLACE row ', T[1], ' -> ', Form.frameLibraryPanel.RowText(StrToInt(T[1])));
          end
        else if Cmd = 'ladder' then
          begin
            Lad := Form.InsertLadderMm(Num(T[1]), Num(T[2]), Num(T[3]), Num(T[4]));
            Form.View.SelectObject(Lad, False);
            Settle;
            WriteLn('LADDER id=', Lad.Id, ' width=', Lad.LineWidth);
          end
        else if Cmd = 'rungs' then
          begin
            Form.View.BeginTool(vtRungs);
            Settle;
            Rg := Form.View.FindRungGrid;
            if Rg = nil then
              WriteLn('RUNGS none')
            else
            begin
              WriteLn('RUNGS id=', Rg.Id, ' rows=', Rg.Rows, ' start=', Rg.StartNumber, ' margin=', FloatToStr(Rg.MarginMm), ' pages=', Rg.Pages,
                ' continue=', Ord(Rg.ContinueNumbers), ' showheight=', Ord(Rg.ShowRowHeight), ' aboveblock=', Ord(Rg.AboveBlock), ' count=', Form.View.SelectedCount, ' tool=', Ord(Form.View.Tool));
              RgR := Rg.AreaRect;
              WriteLn('RUNGAREA ', FormatFloat('0.###', RgR.Left / 5), ' ', FormatFloat('0.###', RgR.Top / 5), ' ', FormatFloat('0.###', RgR.Right / 5), ' ', FormatFloat('0.###', RgR.Bottom / 5),
                ' rowh=', FormatFloat('0.###', Rg.RowHeightMm), ' text=[', Rg.HeightText, ']');
              RgR := Rg.HeightTextBox(0);
              WriteLn('RUNGTEXT ', FormatFloat('0.###', RgR.Left / 5), ' ', FormatFloat('0.###', RgR.Top / 5), ' ', FormatFloat('0.###', RgR.Right / 5), ' ', FormatFloat('0.###', RgR.Bottom / 5));
              for RgPg := 0 to Rg.Pages - 1 do
                for RgCol := 0 to 1 do
                begin
                  RgR := Rg.ColumnRect(RgPg, RgCol);
                  WriteLn('RUNGCOL page=', RgPg, ' col=', RgCol, ' ', FormatFloat('0.###', RgR.Left / 5), ' ', FormatFloat('0.###', RgR.Top / 5), ' ', FormatFloat('0.###', RgR.Right / 5), ' ', FormatFloat('0.###', RgR.Bottom / 5));
                end;
            end;
          end
        else if Cmd = 'setrungs' then
          begin
            Rg := Form.View.FindRungGrid;
            if Rg = nil then
              raise Exception.Create('no rung grid yet');
            Form.View.BeginChange('Set rung grid');
            SetProp(Rg, 'rungs.rows', T[1]); SetProp(Rg, 'rungs.start', T[2]); SetProp(Rg, 'rungs.margin', T[3]);
            SetProp(Rg, 'rungs.pages', IfThen(T[4] = '2', '2 pages', '1 page'));
            if T.Count > 5 then
              SetProp(Rg, 'rungs.continue', T[5]);
            if T.Count > 6 then
              SetProp(Rg, 'rungs.showheight', T[6]);
            if T.Count > 7 then
              SetProp(Rg, 'rungs.aboveblock', T[7]);
            Form.View.CommitChange(True);
            Form.View.Invalidate; Settle;
            WriteLn('SETRUNGS rows=', Rg.Rows, ' start=', Rg.StartNumber, ' margin=', FloatToStr(Rg.MarginMm), ' pages=', Rg.Pages, ' continue=', Ord(Rg.ContinueNumbers), ' showheight=', Ord(Rg.ShowRowHeight));
          end
        else if Cmd = 'rungat' then
          begin
            Rg := Form.View.FindRungGrid;
            if (Rg <> nil) and Rg.LineNumberAt(DPoint(Num(T[1]) * 5, Num(T[2]) * 5), RgN) then
              WriteLn('RUNGAT ', T[1], ' ', T[2], ' = ', RgN)
            else
              WriteLn('RUNGAT ', T[1], ' ', T[2], ' = none');
          end
        else if Cmd = 'ladderinfo' then
          begin
            { ladderinfo : the corners of the ladder made by the ladder command, in mm, its rail line width and colour }
            if Lad = nil then
              raise Exception.Create('no ladder yet');
            WriteLn('LADDERINFO ', FormatFloat('0.###', Lad.PointA.x / 5), ' ', FormatFloat('0.###', Lad.PointA.y / 5), ' ', FormatFloat('0.###', Lad.PointB.x / 5), ' ', FormatFloat('0.###', Lad.PointB.y / 5),
              ' width=', Lad.LineWidth, ' color=', ColorHex(Lad.LineColor), ' selected=', Form.View.SelectedCount);
          end
        else if Cmd = 'setladder' then
          begin
            if Lad = nil then
              raise Exception.Create('no ladder yet');
            Lad.LeftWire := T[1]; Lad.RightWire := T[2];
            if T.Count > 3 then
              Lad.LineWidth := StrToInt(T[3]);
            if T.Count > 4 then
              Lad.LineColor := Cardinal(StrToInt('$' + T[4]));
            Form.View.Invalidate; Settle;
            WriteLn('SETLADDER ', Lad.LeftWire, '/', Lad.RightWire, ' width=', Lad.LineWidth, ' color=', ColorHex(Lad.LineColor));
          end
        else if Cmd = 'click' then
          begin
            Form.View.ClickAt(StrToInt(T[1]), StrToInt(T[2]), []);
            Settle;
          end
        else if Cmd = 'clickmm' then
        begin
          P := Form.View.DesignToScreen(DPoint(Num(T[1]) * UNITS_PER_MM, Num(T[2]) * UNITS_PER_MM));
          Form.View.ClickAt(P.x, P.y, []);
          Settle;
          S := '';
          for k := 0 to Form.View.SelectedCount - 1 do
            begin
              O := Form.View.SelectedObject(k);
              if S <> '' then
                S := S + ',';
              S := S + O.ClassName;
            end;
          WriteLn('CLICK ', T[1], ',', T[2], ' mm -> selected ', Form.View.SelectedCount, ' [', S, ']');
        end
        else if Cmd = 'sel' then
          begin
            S := '';
            for k := 0 to Form.View.SelectedCount - 1 do
            begin
              if S <> '' then
                S := S + ',';
              S := S + Form.View.SelectedObject(k).ClassName;
            end;
            WriteLn('SEL ', Form.View.SelectedCount, ' [', S, ']');
          end
        else if Cmd = 'metrics' then
          begin
            { metrics real|table : what the sheets made from now on measure text with (the real fonts, or the table of Arial widths, which is the default in scripts) }
            UseRealTextMetrics(LowerCase(T[1]) = 'real');
            WriteLn('METRICS ', LowerCase(T[1]));
          end
        else if Cmd = 'fontface' then
          begin
            { fontface <font number> <face name> : the face of one of the sheet's fonts (0 is the text font) }
            (Form.View.Sheet.Options.Fonts.Get(StrToInt(T[1])) as TFontResource).FaceName := T[2];
            WriteLn('FONTFACE ', T[2]);
          end
        else if Cmd = 'textbox' then
          begin
            { textbox <index> : the box of a text object of the sheet, in mm: width and height, }
            O := Form.View.Sheet.Drawing[StrToInt(T[1])];
            if O is TDrawText then
              WriteLn('TEXTBOX ', FormatFloat('0.000', Abs(TDrawText(O).PointB.x - TDrawText(O).PointA.x) / UNITS_PER_MM, DefaultFormatSettings), ' ',
                FormatFloat('0.000', Abs(TDrawText(O).PointB.y - TDrawText(O).PointA.y) / UNITS_PER_MM, DefaultFormatSettings));
          end
        else if Cmd = 'selectalike' then begin
          Form.View.SelectAllAlike;
          Settle;
          WriteLn('SELECTALIKE ', Form.View.SelectedCount);
        end
        else if Cmd = 'selectall' then begin
          Form.View.SelectAll;
          Settle;
          WriteLn('SELECTALL ', Form.View.SelectedCount);
        end
        else if Cmd = 'selclear' then
          begin
            Form.View.ClearSelection;
            Settle;
          end
        else if Cmd = 'delete' then
          begin
            Form.View.DeleteSelection;
            Settle;
          end
        else if Cmd = 'resizewindow' then
          begin
            { resizewindow <width> <height> : the main window gets this size in pixels (the drawing area follows); a larger one shows more of the sheet at a time }
            Form.SetBounds(Form.Left, Form.Top, Trunc(Num(T[1])), Trunc(Num(T[2])));
            Settle;
            Form.View.ZoomFit;
            Settle;
          end
        else if Cmd = 'zoomfit' then
          begin
            Form.View.ZoomFit;
            Settle;
          end
        else if Cmd = 'wheel' then
          begin
            { wheel <x> <y> <delta> [<window width> <window height>] : the wheel turned at x, y of the drawing area (client pixels); optionally the window is first given
              that size. Prints the point of the sheet under the pointer before and after (it should not move), the zoom and where it is shown. }
            if T.Count > 5 then
            begin
              Form.SetBounds(Form.Left, Form.Top, StrToInt(T[4]), StrToInt(T[5]));
              Settle;
            end;
            P := Point(StrToInt(T[1]), StrToInt(T[2]));
            Before := Form.View.ScreenToDesign(P);
            Form.View.SimWheel(P.x, P.y, StrToInt(T[3]));
            Settle;
            After := Form.View.ScreenToDesign(P);
            WriteLn('WHEEL zoom=', Form.View.ZoomPercent, ' before=', Before.x:0:3, ',', Before.y:0:3, ' after=', After.x:0:3, ',', After.y:0:3,
              ' label=[', Form.lbZoomPct.Caption, '] panel=[', Form.sbMainBar.Panels[4].Text, '] view=', Form.View.Width, 'x', Form.View.Height, ' top=', Form.View.ClientToScreen(Point(0, 0)).y,
              ' panels=', Form.sbMainBar.Panels.Count, ' widths=', Form.sbMainBar.Panels[0].Width, ',', Form.sbMainBar.Panels[1].Width, ',', Form.sbMainBar.Panels[2].Width, ',',
              Form.sbMainBar.Panels[3].Width, ',', Form.sbMainBar.Panels[4].Width, ' formwidth=', Form.Width,
              ' zoomlabel=', Form.lbZoomPct.Left, ',', Form.lbZoomPct.Top, ',', Form.lbZoomPct.Width, ' poslabel=', Form.lblPosition.Left, ',', Form.lblPosition.Width);
          end
        else if Cmd = 'zoom' then
          begin
            Form.View.ZoomBy(Num(T[1]));
            Settle;
          end
        else if Cmd = 'centeron' then
          begin
            { centeron <x mm> <y mm> : scroll the sheet so that this point is in the middle of the window (the zoom stays) }
            Form.View.CenterOnPoint(DPoint(Num(T[1]) * 5, Num(T[2]) * 5));
            Settle;
          end
        else if Cmd = 'arrowkey' then
          begin
            { arrowkey left|right|up|down : the key pressed on the sheet; prints ARROWKEY <name> moved=<0|1> }
            Kc := 0;
            if T[1] = 'left' then
              Kc := VK_LEFT else if T[1] = 'right' then
              Kc := VK_RIGHT
            else if T[1] = 'up' then
              Kc := VK_UP else if T[1] = 'down' then
              Kc := VK_DOWN;
            Form.View.ArrowKey(Kc, []);
            Settle;
            WriteLn('ARROWKEY ', T[1], ' moved=', Ord(Kc = 0));
          end
        else if Cmd = 'zoomfactor' then
          WriteLn('ZOOMFACTOR ', FormatFloat('0.#####', Form.View.Zoom, FmtDot))
        else if Cmd = 'zoompercent' then
          WriteLn('ZOOMPERCENT ', Form.View.ZoomPercent)
        else if Cmd = 'save' then
          begin
            Form.Design.SaveToFile(T[1]);
            WriteLn('SAVED ', T[1]);
          end
        else if Cmd = 'info' then
          begin
            if Form.View.Sheet = nil then
              WriteLn('INFO no document')
            else
              WriteLn('INFO sheets=', Form.Design.SheetCount, ' objects=', Form.View.Sheet.Drawing.Count, ' page=', Form.View.Sheet.Details.PageWidth, 'x', Form.View.Sheet.Details.PageHeight,
                         ' ', DescribePage(Form.View.Sheet.Details.PageWidth, Form.View.Sheet.Details.PageHeight));
          end
        else if Cmd = 'hitmap' then
        begin
          Fx := Num(T[2]); Total := 0; Hits := 0;
          Res := TStringList.Create;
          try
            while Fx <= Num(T[4]) + 1E-9 do
            begin
              Fy := Num(T[3]);
              while Fy <= Num(T[5]) + 1E-9 do
              begin
                Inc(Total);
                O := Form.View.HitTest(DPoint(Fx * UNITS_PER_MM, Fy * UNITS_PER_MM));
                if O <> nil then
                begin
                  Inc(Hits);
                  Res.Add(Format('%.3f %.3f %s', [Fx, Fy, O.ClassName], FmtDot));
                end;
                Fy := Fy + Num(T[6]);
              end;
              Fx := Fx + Num(T[6]);
            end;
            Res.SaveToFile(T[1]);
          finally
            Res.Free;
          end;
          WriteLn('HITMAP ', Total, ' points, ', Hits, ' hit');
        end
        else if Cmd = 'tool' then
        begin
          S := LowerCase(T[1]);
          if S = 'select' then
            Form.View.CancelTool
          else if S = 'wire' then
            Form.View.BeginTool(vtWire)
          else if S = 'line' then
            Form.View.BeginTool(vtLine)
          else if S = 'polygon' then
            Form.View.BeginTool(vtPolygon)
          else if S = 'rect' then
            Form.View.BeginTool(vtRect)
          else if S = 'circle' then
            Form.View.BeginTool(vtCircle)
          else if S = 'arc' then
            Form.View.BeginTool(vtArc)
          else if S = 'note' then
            Form.View.BeginTool(vtNote)
          else if S = 'cloud' then
            Form.View.BeginTool(vtCloud)
          else if S = 'label' then
            Form.View.BeginTool(vtLabel)
          else if S = 'junction' then
            Form.View.BeginTool(vtJunction)
          else if S = 'rulerh' then
            Form.View.BeginTool(vtRulerH)
          else if S = 'rulerv' then
            Form.View.BeginTool(vtRulerV)
          else if S = 'measure' then
            Form.View.BeginTool(vtMeasure)
          else if S = 'ladder' then
            Form.View.BeginTool(vtLadder)
          else if S = 'rungs' then
            Form.View.BeginTool(vtRungs)
          else if S = 'xrefline' then
            Form.View.BeginTool(vtXRefLine)
          else if S = 'xrefcontacts' then
            Form.View.BeginTool(vtXRefContacts)
          else if S = 'bus' then
            Form.View.BeginTool(vtBus)
          else if S = 'busslash' then
            Form.View.BeginTool(vtBusSlash)
          else if S = 'noconnect' then
            Form.View.BeginTool(vtNoConnect)
          else if S = 'power' then
            Form.View.BeginTool(vtPower)
          else if S = 'text' then
            Form.View.BeginTool(vtText)
          else if S = 'symboltext' then
            Form.View.BeginTool(vtSymbolText)
          else if S = 'pin' then
            Form.View.BeginTool(vtPin)
          else if S = 'origin' then
            Form.View.BeginTool(vtOrigin)
          else if S = 'place' then
            Form.View.BeginTool(vtPlace)
          else
            WriteLn('? unknown tool ', S);
            Settle;
        end
        else if Cmd = 'mouse' then
          begin
            P := Form.View.DesignToScreen(DPoint(Num(T[2]) * UNITS_PER_MM, Num(T[3]) * UNITS_PER_MM));
            S := LowerCase(T[1]);
            if S = 'down' then
              Form.View.SimMouse(0, P.x, P.y, [ssLeft], mbLeft)
            else if S = 'move' then
              begin
                { mouse move <x> <y> [ctrl] : the pointer moves (with the Ctrl key held if asked) }
                if (T.Count > 4) and (LowerCase(T[4]) = 'ctrl') then
                  Form.View.SimMouse(1, P.x, P.y, [ssCtrl], mbLeft)
                else
                  Form.View.SimMouse(1, P.x, P.y, [], mbLeft);
              end
            else if S = 'up' then
              Form.View.SimMouse(2, P.x, P.y, [], mbLeft)
            else if S = 'lost' then
              Form.View.SimMouse(3, P.x, P.y, [], mbLeft)      { mouse lost <x> <y> : the pointer moves with no button held although the view saw a press and no release }
            else if S = 'mdown' then
              Form.View.SimMouse(0, P.x, P.y, [ssMiddle], mbMiddle)
            else if S = 'mup' then
              Form.View.SimMouse(2, P.x, P.y, [], mbMiddle)
            else if S = 'dbl' then
              begin
                Form.View.SimMouse(0, P.x, P.y, [ssLeft, ssDouble], mbLeft);
                Form.View.SimMouse(2, P.x, P.y, [], mbLeft);
              end
            else if S = 'rdown' then
              begin
                Form.View.SimMouse(0, P.x, P.y, [ssRight], mbRight);
                Form.View.SimMouse(2, P.x, P.y, [], mbRight);
              end;
            Settle;
          end
        else if Cmd = 'ribbon' then
          begin
            if Form.PressRibbon(T[1]) then
              WriteLn('RIBBON pressed "', T[1], '"')
            else
              WriteLn('RIBBON no button "', T[1], '"');
            Settle;
          end
        else if Cmd = 'ribbontab' then
          begin
            Form.ShowRibbonTab(T[1]);
            Settle;
            WriteLn('RIBBONTAB ', Form.RibbonTabTitle);
          end
        else if Cmd = 'ribbonclick' then
          begin
            { ribbonclick <tab>: a click on a ribbon tab, as a person does it (ribbontab brings a page forward from code) }
            Form.ChooseRibbonTab(T[1]);
            Settle;
            WriteLn('RIBBONCLICK ', Form.RibbonTabTitle);
          end
        else if Cmd = 'newdocdialog' then
          begin
            { newdocdialog <name>=<value> ...: the New Document dialog as it opens: pick=<paper, _ for a space>, orient=portrait|landscape, ok=1 (accept: the choice is remembered).
              Prints NEWDOCDIALOG paper=<selected paper> landscape=<0|1> margin=<the margin box> and, when accepted, NEWDOCDIALOG remembered ... }
            NdF := TfrmNewDoc.Create(Form);
            try
              for OptI := 1 to T.Count - 1 do
              begin
                OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
                OptVal := StringReplace(Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt), '_', ' ', [rfReplaceAll]);
                if OptKey = 'pick' then
                  NdF.SelectPaper(OptVal, NdF.Landscape)
                else if OptKey = 'orient' then
                  NdF.SelectPaper(PaperInfo(NdF.PaperIndex).Name, LowerCase(OptVal) <> 'portrait')
                else if OptKey = 'ok' then
                begin
                  NdF.RememberChoice;
                  WriteLn('NEWDOCDIALOG remembered paper=', ProgramSettings.NewDocPaper, ' landscape=', Ord(ProgramSettings.NewDocLandscape));
                end
                else
                  WriteLn('NEWDOCDIALOG unknown name: ', OptKey);
              end;
              WriteLn('NEWDOCDIALOG paper=', PaperInfo(NdF.PaperIndex).Name, ' landscape=', Ord(NdF.Landscape), ' margin=', NdF.edMargin.Text);
            finally
              NdF.Free;
            end;
          end
        else if Cmd = 'ribbonstate' then
          WriteLn('RIBBONSTATE tab=', Form.RibbonTabTitle, ' tool=', Ord(Form.View.Tool))
        else if Cmd = 'setprop' then
          begin
            if Form.SetPropertyText(T[1], T[2]) then
              WriteLn('SETPROP ', T[1], '=', T[2])
            else
              WriteLn('SETPROP no such property on the selection: ', T[1]);
            Settle;
          end
        else if Cmd = 'toolbuttons' then
          begin
            { toolbuttons : the tool, and which of the Select buttons (Home, Draw) and of a few draw tool buttons are pressed }
            WriteLn('TOOLBUTTONS tool=', Ord(Form.View.Tool), ' homeselect=', Ord(Form.sbHomeSelectOne.Down), ' drawselect=', Ord(Form.sbDrawSelect.Down),
              ' pinvisible=', Ord(Form.miDrawPin.Visible), ' pin=', Ord(Form.miDrawPin.Down), ' wire=', Ord(Form.sbDrawWiresWire.Down), ' rect=', Ord(Form.sbDrawShapesRect.Down), ' bus=', Ord(Form.sbDrawWiresBus.Down));
          end
        else if Cmd = 'selectbutton' then
          begin
            { selectbutton draw | home : a click on the Select button of the Draw or of the Home ribbon }
            if LowerCase(T[1]) = 'draw' then
              Form.sbDrawSelect.Click
            else
              Form.sbHomeSelectOne.Click;
            Settle;
          end
        else if Cmd = 'linestyleitems' then
          begin
            { linestyleitems : paints each of the five line style items the way the drop-down does onto a bitmap, and prints how many dark pixels (and the first and last column with any) it has, then the same for the picture in ilListBoxImages it should show }
            Settle;
            for k := 0 to 4 do
              WriteLn('LSITEM ', k, ' ', Form.LineStyleItemStats(k));
          end
        else if Cmd = 'linestylecombos' then
          begin
            { linestylecombos : style, item height and OnDrawItem of the tool panel's drop-downs that list line styles }
            Settle;
            WriteLn('LSCOMBOS ', Form.LineStyleComboInfo);
          end
        else if Cmd = 'toolpanel' then
          begin
            { toolpanel : the Draw ribbon's Properties panel of the tool in use: whether it is there, the separator before it, its label, and its editors (class, left, top, width, height, name) }
            Settle;
            if Form.ToolPanelInfo then
              for k := 0 to High(Form.ToolEditorNames) do
                WriteLn('TOOLCTL ', Form.ToolEditorNames[k]);
          end
        else if Cmd = 'registerframe' then
          begin
            { registerframe <key> demo|bad|none|all (all: the frames the program registers, whatever the key) : makes the demo frame (wire properties), the badly named demo frame or no frame the one used for a tool/object key; none removes every registered frame }
            if LowerCase(T[2]) = 'none' then
              UnregisterPropFrames
            else if LowerCase(T[2]) = 'all' then begin
              UnregisterPropFrames;
              RegisterAllPropFrames;
            end
            else if LowerCase(T[2]) = 'demo' then
              RegisterPropFrame(LowerCase(T[1]), TfrDemoWire)
            else
              RegisterPropFrame(LowerCase(T[1]), TfrDemoBad);
            Form.PropFramesChanged;
            Settle;
            WriteLn('REGISTERFRAME ', T[1], ' ', T[2]);
          end
        else if Cmd = 'frameact' then
          begin
            FrameValue := '';
            for k := 4 to T.Count - 1 do
            begin
              if k > 4 then
                FrameValue := FrameValue + ' ';
              FrameValue := FrameValue + T[k];      // (the value is the rest of the line, so a text may hold spaces)
            end;
            { frameact tool|sel <control> click|choose|text|color [value] : does to a control of the property frame what a person does (a click, an item chosen by position, text typed, a color chosen) }
            WriteLn('FRAMEACT ', T[2], ' ', T[3], ' ', Ord(Form.FrameAct(LowerCase(T[1]) = 'tool', T[2], LowerCase(T[3]), FrameValue)));
            Settle;
          end
        else if Cmd = 'filldrop' then
          begin
            { filldrop [wheel-up|wheel-down|up|down|home|end|enter|esc|close|color <hex>] : turns the wheel or presses a key on the Fill menu dropped down from the Fill button, and tells what it shows }
            if T.Count > 2 then
              WriteLn('FILLDROP ', Form.FillDropAct(LowerCase(T[1]) + ' ' + T[2]))
            else if T.Count > 1 then
              WriteLn('FILLDROP ', Form.FillDropAct(LowerCase(T[1])))
            else
              WriteLn('FILLDROP ', Form.FillDropAct(''));
            Settle;
          end
        else if Cmd = 'busdrop' then
          begin
            { busdrop [close|esc|phase 1|phase 3|space 1..4|custom <text>] : does to the Phases panel dropped down from the Phases button what a person does, and tells what it shows }
            Arg := '';
            for k := 1 to T.Count - 1 do
              Arg := Trim(Arg + ' ' + T[k]);
            WriteLn('BUSDROP ', Form.BusDropAct(LowerCase(Arg)));
            Settle;
          end
        else if Cmd = 'busdropshot' then
          begin
            { busdropshot <png> : a picture of the Phases panel while it is open }
            Settle;
            if Form.BusDropForm <> nil then
            begin
              SaveForm(Form.BusDropForm, T[1]); WriteLn('BUSDROPSHOT ', T[1]);
            end
            else
              WriteLn('BUSDROPSHOT none');
          end
        else if Cmd = 'filldropshot' then
          begin
            { filldropshot <png> : a picture of the Fill menu while it is open }
            Settle;
            if Form.FillDropForm <> nil then
            begin
              SaveForm(Form.FillDropForm, T[1]); WriteLn('FILLDROPSHOT ', T[1]);
            end
            else
              WriteLn('FILLDROPSHOT none');
          end
        else if Cmd = 'frameglyph' then
          WriteLn('FRAMEGLYPH ', T[2], ' ', Form.FrameGlyph(LowerCase(T[1]) = 'tool', T[2]))      { frameglyph tool|sel <button> : the pixels of the picture on a Fill button }
        else if Cmd = 'comboitems' then
          WriteLn('COMBOITEMS ', T[2], ' ', Form.FrameComboItems(LowerCase(T[1]) = 'tool', T[2]))      { comboitems tool|sel <control> : the items of a combo box of the frame }
        else if Cmd = 'wireinfo' then
          WriteLn('WIREINFO angle=', Ord(Form.View.WireAngleNow))      { wireinfo : the angle mode the wire tool is using (0 free, 1 90, 2 45), -1 when no wire tool }
        else if Cmd = 'sharedinfo' then
          begin
            { sharedinfo <name>... : for each component name, whether the shared controls form owns it and whether the main form does (the dialogs and image lists live in the shared form only) }
            for k := 1 to T.Count - 1 do
              WriteLn('SHARED ', T[k], ' shared=', Ord(frmSharedControls.FindComponent(T[k]) <> nil), ' main=', Ord(Form.FindComponent(T[k]) <> nil),
                ' same=', Ord((Form.FindComponent(T[k]) = nil) and (frmSharedControls.FindComponent(T[k]) <> nil)));
          end
        else if Cmd = 'formesc' then
          begin
            { formesc [view] : Esc pressed on the main form, with the focus off the sheet (or, with view, on the sheet) }
            Kc := 27;
            if (T.Count > 1) and (LowerCase(T[1]) = 'view') then
              Form.ActiveControl := Form.View
            else
              Form.ActiveControl := nil;
            Form.FormKeyDown(Form, Kc, []);
            Settle;
            WriteLn('FORMESC key=', Kc, ' tool=', Ord(Form.View.Tool));
          end
        else if Cmd = 'viewdblclick' then
          begin
            { viewdblclick : the sheet's double click event (the first click of the double click has already chosen what it chose) }
            Form.View.OnDblClick(Form.View);
            Settle;
          end
        else if Cmd = 'focusinfo' then
          begin
            { focusinfo : the control with the focus on the main form, and for a text box its text and the selection }
            Settle;
            if Form.ActiveControl is TEdit then
              WriteLn('FOCUS ', Form.ActiveControl.Name, ' text="', TEdit(Form.ActiveControl).Text, '" selstart=', TEdit(Form.ActiveControl).SelStart,
                ' sellen=', TEdit(Form.ActiveControl).SelLength, ' sel=', Form.View.SelectedCount)
            else if Form.ActiveControl <> nil then
              WriteLn('FOCUS ', Form.ActiveControl.Name, ' sel=', Form.View.SelectedCount)
            else
              WriteLn('FOCUS none sel=', Form.View.SelectedCount);
          end
        else if Cmd = 'userfont' then
          WriteLn('USERFONT ', Form.View.UserFontInfo)
        else if Cmd = 'floatinfo' then
          begin
            { floatinfo : the text following the pointer (the Text tool), '' when none }
            Settle;
            WriteLn('FLOAT "', Form.View.FloatingText, '"');
          end
        else if Cmd = 'editcaret' then
          begin
            { editcaret <start> [length] : puts the caret (and a selection) in the focused text box }
            Settle;
            if Form.ActiveControl is TEdit then
              with TEdit(Form.ActiveControl) do
              begin
                SelStart := StrToInt(T[1]);
                if T.Count > 2 then
                  SelLength := StrToInt(T[2])
                else
                  SelLength := 0;
              end;
          end
        else if Cmd = 'editdel' then
          begin
            { editdel : presses Del in the focused text box the way the keyboard does: the form's key preview, then the shortcuts of the menus (Delete), then the box }
            Settle;
            if Form.ActiveControl is TWinControl then
            begin
              Kc := 46;
              Form.FormKeyDown(Form, Kc, []);
              FillChar(KMsg, SizeOf(KMsg), 0);
              KMsg.Msg := LM_KEYDOWN;
              KMsg.CharCode := 46;
              if (Kc <> 0) and not Form.IsShortcut(KMsg) then
              begin
                Form.PropEditKeyDown(Form.ActiveControl, Kc, []);
                if Kc <> 0 then
                  Form.EditDeleteForward(Form.ActiveControl);
              end;
              Kc := 46;
              Form.FormKeyUp(Form, Kc, []);
            end;
            Settle;
            WriteLn('EDITDEL objects=', Form.View.Sheet.Drawing.Count);
          end
        else if Cmd = 'frameinfo' then
          begin
            { frameinfo tool|sel : the frame in use for the tool panel or the selection: a header line, then the bound editors and the problems found }
            Settle;
            for k := 0 to High(Form.FrameInfo(LowerCase(T[1]) = 'tool')) do
              WriteLn('FRAMEINFO ', Form.FrameInfo(LowerCase(T[1]) = 'tool')[k]);
          end
        else if Cmd = 'typenumber' then
          begin
            { typenumber sel|tool <name> <value> [done] : types a number in the number box of a property (the selection's, or the tool panel's); with done, Enter is pressed
              (otherwise it is applied after the pause that follows the last change) }
            WriteLn('TYPENUMBER ', T[2], ' ', Ord(Form.TypeNumber(T[2], StrToFloat(T[3], DefaultFormatSettings), LowerCase(T[1]) = 'tool', (T.Count > 4) and (LowerCase(T[4]) = 'done'))));
            Settle;
          end
        else if Cmd = 'toolprop' then
          begin
            { toolprop <name> <value> : a value chosen in the tool's Properties panel }
            WriteLn('TOOLPROP ', T[1], ' ', Ord(Form.SetToolPropertyText(T[1], T[2])));
            Settle;
          end
        else if Cmd = 'text' then
          begin
            { text <component> <property>  : the Caption, Hint or Text of a component of the main window (or of a frame in it), as it is after translation
              text frame <key> <component> <property>  : the same in a frame made for the moment (the key is the one it is registered with: pin, wire ...)
              rs ready|snapon|nothing|undohint|grid <x>  : a resourcestring (the grid one with its value filled in) }
            if (T.Count > 4) and (LowerCase(T[1]) = 'frame') and (PropFrameFor(T[2]) <> nil) then
            begin
              Fr := PropFrameFor(T[2]).Create(nil);
              try
                WriteLn(ComponentText(Fr, T[3], T[4]));
              finally
                Fr.Free;
              end;
            end
            else if T.Count > 2 then
              WriteLn(ComponentText(Form, T[1], T[2]));
          end
        else if Cmd = 'rs' then
          begin
            if T.Count > 1 then
            begin
              if T[1] = 'ready' then
                WriteLn('RS ready=[', rsReady, ']')
              else if T[1] = 'snapon' then
                WriteLn('RS snapon=[', rsSnapToGridOn, ']')
              else if T[1] = 'nothing' then
                WriteLn('RS nothing=[', rsNothingSelected, ']')
              else if T[1] = 'undohint' then
                WriteLn('RS undohint=[', rsUndoCtrlZ, ']')
              else if (T[1] = 'grid') and (T.Count > 2) then
                WriteLn('RS grid=[', Format(rsGrid, [T[2]]), ']')
              else
                WriteLn('RS ', T[1], ' unknown');
            end;
          end
        else if Cmd = 'propspanel' then
          begin
            { propspanel : plPropsProperties: its width, the label at its foot, and the position of every other control in it }
            Settle;
            WriteLn('PROPSPANEL width=', Form.plPropsProperties.Width, ' label=[', Form.lbPropsProperties.Caption, '] labelwidth=', Form.lbPropsProperties.Width,
              ' labelalign=', Ord(Form.lbPropsProperties.Align), ' sepleft=', Form.pnlPropsSep.Left, ' sepvisible=', Ord(Form.pnlPropsSep.Visible), ' panelleft=', Form.plPropsProperties.Left, ' controls=', Form.plPropsProperties.ControlCount - 1);
            for k := 0 to Form.plPropsProperties.ControlCount - 1 do
              if Form.plPropsProperties.Controls[k] <> Form.lbPropsProperties then
                with Form.plPropsProperties.Controls[k] do
                  if Form.plPropsProperties.Controls[k] is TLabel then
                    WriteLn('PROPCTL ', ClassName, ' ', Left, ' ', Top, ' ', Width, ' ', Height, ' ', Left + Width, ' [', TLabel(Form.plPropsProperties.Controls[k]).Caption, ']')
                  else
                    WriteLn('PROPCTL ', ClassName, ' ', Left, ' ', Top, ' ', Width, ' ', Height, ' ', Left + Width);
          end
        else if Cmd = 'props' then
          WriteLn('PROPS ', Form.PropertyDump)
        else if Cmd = 'undo' then
          begin
            WriteLn('UNDO ', Ord(Form.View.DoUndo));
            Settle;
          end
        else if Cmd = 'redo' then
          begin
            WriteLn('REDO ', Ord(Form.View.DoRedo));
            Settle;
          end
        else if Cmd = 'undoinfo' then
          WriteLn('UNDOINFO undo=', Form.View.Undo.UndoCount, ' redo=', Form.View.Undo.RedoCount, ' next="', Form.View.Undo.UndoCaption, '"')
        else if Cmd = 'snap' then
          begin
            Form.View.SnapEnabled := LowerCase(T[1]) = 'on';
            WriteLn('SNAP ', Ord(Form.View.SnapEnabled));
          end
        else if Cmd = 'gridmm' then
          begin
            Form.SetGridMmFromScript(Num(T[1]));
            WriteLn('GRID ', Form.View.GridMm:0:3);
          end
        else if Cmd = 'pinbutton' then
          begin
            { pinbutton [click] : the Pin button of the Draw tab: PINBUTTON visible=<0|1> tool=<tool number> down=<0|1>, after a click on it when asked (a click on a hidden button is not done) }
            Form.RefreshSymbolControls;
            if (T.Count > 1) and Form.miDrawPin.Visible then
            begin
              Form.miDrawPin.Click;
              Settle;
            end;
            WriteLn('PINBUTTON visible=', Ord(Form.miDrawPin.Visible), ' tool=', Ord(Form.View.Tool), ' down=', Ord(Form.miDrawPin.Down), ' pintool=', Ord(Form.View.Tool = vtPin));
          end
        else if Cmd = 'selpoints' then
          begin
            { selpoints : SELPT <n> <class> a=<x>,<y> b=<x>,<y> (mm) for each selected object, then SELPT end }
            for k := 0 to Form.View.SelectedCount - 1 do
              WriteLn('SELPT ', k, ' ', Form.View.SelectedObject(k).ClassName, ' a=', (Form.View.SelectedObject(k).PointA.x / UNITS_PER_MM):0:3, ',', (Form.View.SelectedObject(k).PointA.y / UNITS_PER_MM):0:3,
                ' b=', (Form.View.SelectedObject(k).PointB.x / UNITS_PER_MM):0:3, ',', (Form.View.SelectedObject(k).PointB.y / UNITS_PER_MM):0:3);
            WriteLn('SELPT end');
          end
        else if Cmd = 'onepxgrid' then
          begin
            { onepxgrid 0|1 : the 1 px grid check box of the Alignment panel clicked; ONEPXGRID checked=<0|1> enabled=<0|1> mm=<grid> dot600=<dot pixels at 600%> dot100=<at 100%> alignmm=<the grid Align to Grid uses> }
            Form.SetOnePxGridBox(T[1] = '1');
            Settle;
            WriteLn('ONEPXGRID checked=', Ord(Form.OnePxGridChecked), ' enabled=', Ord(Form.OnePxGridEnabled), ' mm=', Form.View.GridMm:0:3, ' dot600=', GridDotSize(6, Form.View.OnePxDots), ' dot100=', GridDotSize(1, Form.View.OnePxDots), ' alignmm=', (Form.AlignGridUnits / UNITS_PER_MM):0:3);
          end
        else if Cmd = 'aligntogrid' then
          begin
            { aligntogrid : Z-Order > Align to Grid on the selection (the pop-up item is visible only in symbol editing: ALIGNTOGRID visible=<0|1> enabled=<0|1>) }
            Form.AlignMenuOpen;
            WriteLn('ALIGNTOGRID visible=', Ord(Form.AlignItemVisible), ' enabled=', Ord(Form.AlignItemEnabled));
            Form.DoAlignToGrid(nil);
            Settle;
          end
        else if Cmd = 'gridinfo' then
          WriteLn('GRIDINFO snap=', Ord(Form.View.SnapEnabled), ' mm=', Form.View.GridMm:0:3)
        else if Cmd = 'pinsof' then
          begin
            m := 0;
            for k := 0 to Form.View.Sheet.Drawing.Count - 1 do
              if Form.View.Sheet.Drawing[k] is TDrawMethod then
              begin
                PinList := ActivePointsOf(Form.View.Sheet.Drawing[k]);
                for Fxi := 0 to High(PinList) do
                  WriteLn('PIN ', m, ' ', Fxi, ' ', PinList[Fxi].x:0:3, ' ', PinList[Fxi].y:0:3);
                Inc(m);
              end;
          end
        else if Cmd = 'mousepin' then
          begin
            m := 0;
            for k := 0 to Form.View.Sheet.Drawing.Count - 1 do
              if Form.View.Sheet.Drawing[k] is TDrawMethod then
              begin
                if m = StrToInt(T[2]) then
                begin
                  PinList := ActivePointsOf(Form.View.Sheet.Drawing[k]);
                  Fx := PinList[StrToInt(T[3])].x + Num(T[4]) * UNITS_PER_MM;
                  Fy := PinList[StrToInt(T[3])].y + Num(T[5]) * UNITS_PER_MM;
                  P := Form.View.DesignToScreen(DPoint(Fx, Fy));
                  S := LowerCase(T[1]);
                  if S = 'down' then
                    Form.View.SimMouse(0, P.x, P.y, [ssLeft], mbLeft)
                  else if S = 'move' then
                    Form.View.SimMouse(1, P.x, P.y, [], mbLeft)
                  else if S = 'up' then
                    Form.View.SimMouse(2, P.x, P.y, [], mbLeft)
                  else if S = 'dbl' then
                    begin
                      Form.View.SimMouse(0, P.x, P.y, [ssLeft, ssDouble], mbLeft);
                      Form.View.SimMouse(2, P.x, P.y, [], mbLeft);
                    end
                  else if S = 'rdown' then
                    begin
                      Form.View.SimMouse(0, P.x, P.y, [ssRight], mbRight);
                      Form.View.SimMouse(2, P.x, P.y, [], mbRight);
                    end;
                  Break;
                end;
                Inc(m);
              end;
            Settle;
          end
        else if Cmd = 'objects' then
          begin
            for k := 0 to Form.View.Sheet.Drawing.Count - 1 do
            begin
              O := Form.View.Sheet.Drawing[k];
              if O.GetType = xWire then
                WriteLn('OBJ wire ', O.PointA.x:0:3, ' ', O.PointA.y:0:3, ' ', O.PointB.x:0:3, ' ', O.PointB.y:0:3, ' default=', Ord((O as TDrawLine).UseDefaultStyle), ' style=', (O as TDrawLine).Style)
              else if O.GetType = xJunction then
                WriteLn('OBJ junction ', O.PointA.x:0:3, ' ', O.PointA.y:0:3)
              else
                WriteLn('OBJ ', O.ClassName, ' id=', O.Id);
            end;
            WriteLn('OBJ end ', Form.View.Sheet.Drawing.Count);
          end
        else if Cmd = 'buses' then
          begin
            { buses : every bus wire of the sheet: BUS <index> a=<x>,<y> b=<x>,<y> (millimetres) group=<id> phase=<-1|0|1> phases=<1|3> gap=<mm> selected=<0|1> }
            for k := 0 to Form.View.Sheet.Drawing.Count - 1 do
              if Form.View.Sheet.Drawing[k].GetType = xBus then
                with Form.View.Sheet.Drawing[k] as TDrawLine do
                  WriteLn('BUS ', k, ' a=', PointA.x / UNITS_PER_MM:0:3, ',', PointA.y / UNITS_PER_MM:0:3, ' b=', PointB.x / UNITS_PER_MM:0:3, ',', PointB.y / UNITS_PER_MM:0:3,
                    ' group=', Group, ' phase=', Phase, ' phases=', Phases, ' gap=', PhaseSpacing / UNITS_PER_MM:0:3, ' selected=', Ord(Form.View.SelectedList.IndexOf(Form.View.Sheet.Drawing[k]) >= 0));
            WriteLn('BUS end');
          end
        else if Cmd = 'hiersymbols' then
          begin
            { hiersymbols : every placed design (hierarchical symbol) of the sheet shown: HIER <index> pos= rotate= scale= file=[] fields= name=[] box=<PointB minus PointA> id= }
            for k := 0 to Form.View.Sheet.Drawing.Count - 1 do
              if Form.View.Sheet.Drawing[k] is TDrawHierarchicalSymbol then
                with Form.View.Sheet.Drawing[k] as TDrawHierarchicalSymbol do
                  WriteLn('HIER ', k, ' pos=', PointA.x / UNITS_PER_MM:0:3, ',', PointA.y / UNITS_PER_MM:0:3, ' rotate=', Rotate, ' scale=', ScalingX:0:3, ',', ScalingY:0:3, ' can_scale=', CanScale,
                    ' file=[', FileName, '] fields=', Length(Fields), ' name=[', Fields[FIELD_NAME].Value, '] box=', (PointB.x - PointA.x):0:1, ',', (PointB.y - PointA.y):0:1,
                    ' id=', Id, ' hassym=', Ord(HasSymbol), ' err=[', LoadError, ']');
            WriteLn('HIER end');
          end
        else if Cmd = 'docs' then
        begin
          { DOCS n current=<index> list=<tab captions> }
          Txt := '';
          for k := 0 to Form.DocumentCount - 1 do Txt := Txt + Form.DocumentCaption(k) + '|';
          WriteLn('DOCS ', Form.DocumentCount, ' current=', Form.DocumentIndex, ' list=', Txt);
        end
        else if Cmd = 'doctabs' then
        begin
          { doctabs : DOCTABS visible=<0|1> w=<strip width> h=<strip height> count=<tabs> current=<tab> names=<name>|... modified=<0|1>,... glyphs=<picture each tab shows>,...
            rects=<l:t:r:b>;... closes=<the glyph squares, l:t:r:b>;... arrows=<0|1> scroll=<pixels> total=<width of all the tabs> hot=<tab under the pointer> hotclose=<0|1>
            pressed=<tab> images=<pictures in the list> size=<w>x<h> linked=<0|1> }
          with Form.DocTabs do
          begin
            Txt := 'DOCTABS visible=' + IntToStr(Ord(Visible)) + ' w=' + IntToStr(Width) + ' h=' + IntToStr(Height) + ' count=' + IntToStr(TabCount) + ' current=' + IntToStr(TabIndex) + ' names=';
            for k := 0 to TabCount - 1 do
              Txt := Txt + TabName(k) + '|';
            Txt := Txt + ' modified=';
            for k := 0 to TabCount - 1 do
              Txt := Txt + IntToStr(Ord(TabModified(k))) + ',';
            Txt := Txt + ' glyphs=';
            for k := 0 to TabCount - 1 do
              Txt := Txt + IntToStr(GlyphIndexFor(k)) + ',';
            Txt := Txt + ' rects=';
            for k := 0 to TabCount - 1 do
              Txt := Txt + Format('%d:%d:%d:%d;', [TabRect(k).Left, TabRect(k).Top, TabRect(k).Right, TabRect(k).Bottom]);
            Txt := Txt + ' closes=';
            for k := 0 to TabCount - 1 do
              Txt := Txt + Format('%d:%d:%d:%d;', [CloseRect(k).Left, CloseRect(k).Top, CloseRect(k).Right, CloseRect(k).Bottom]);
            WriteLn(Txt, ' arrows=', Ord(ArrowsShown), ' scroll=', Scroll, ' total=', TotalWidth, ' hot=', HotTab, ' hotclose=', Ord(HotOnClose), ' pressed=', PressedClose);
            if Images <> nil then
              WriteLn('DOCTABIMAGES images=', Images.Count, ' size=', Images.Width, 'x', Images.Height, ' linked=', Ord(Images = frmSharedControls.ilDocTabs))
            else
              WriteLn('DOCTABIMAGES images=0 size=0x0 linked=0');
          end;
        end
        else if Cmd = 'doctab' then
        begin
          { doctab move <x> <y> | down <x> <y> [l|m|r] | up <x> <y> [l|m|r] | wheel <turn> | shot <file.png> : what a person does with the mouse on the strip of document tabs (x and y in the strip),
            and a picture of the strip. Prints DOCTAB <verb> }
          OptKey := LowerCase(T[1]);
          with Form.DocTabs do
          begin
            if T.Count > 4 then
              Txt := LowerCase(T[4])
            else
              Txt := 'l';
            if OptKey = 'move' then
              MouseMove([], StrToInt(T[2]), StrToInt(T[3]))
            else if OptKey = 'down' then
            begin
              if Txt = 'm' then
                MouseDown(mbMiddle, [ssMiddle], StrToInt(T[2]), StrToInt(T[3]))
              else if Txt = 'r' then
                MouseDown(mbRight, [ssRight], StrToInt(T[2]), StrToInt(T[3]))
              else
                MouseDown(mbLeft, [ssLeft], StrToInt(T[2]), StrToInt(T[3]));
            end
            else if OptKey = 'up' then
            begin
              if Txt = 'm' then
                MouseUp(mbMiddle, [], StrToInt(T[2]), StrToInt(T[3]))
              else if Txt = 'r' then
                MouseUp(mbRight, [], StrToInt(T[2]), StrToInt(T[3]))
              else
                MouseUp(mbLeft, [], StrToInt(T[2]), StrToInt(T[3]));
            end
            else if OptKey = 'wheel' then
              Wheel(StrToInt(T[2]))
            else if OptKey = 'shot' then
            begin
              OptBmp := TBitmap.Create;
              try
                OptBmp.SetSize(Width, Height);
                DrawStrip(OptBmp.Canvas, Width, Height);
                OptPng := TPortableNetworkGraphic.Create;
                try
                  OptPng.Assign(OptBmp);
                  OptPng.SaveToFile(T[2]);
                finally
                  OptPng.Free;
                end;
              finally
                OptBmp.Free;
              end;
            end;
          end;
          Settle;
          WriteLn('DOCTAB ', OptKey);
        end
        else if Cmd = 'gotodoc' then begin
          Form.ActivateDocument(StrToInt(T[1]));
          Settle;
          WriteLn('GOTODOC ', T[1]);
        end
        else if Cmd = 'nextdoc' then begin
          Form.DoNextDocument(nil);
          Settle;
          WriteLn('NEXTDOC');
        end
        else if Cmd = 'prevdoc' then begin
          Form.DoPrevDocument(nil);
          Settle;
          WriteLn('PREVDOC');
        end
        else if Cmd = 'closedoc' then
        begin
          { closedoc [index]: close without asking about unsaved changes }
          if T.Count > 1 then
            k := StrToInt(T[1])
          else
            k := Form.DocumentIndex;
          WriteLn('CLOSEDOC ', Ord(Form.CloseDocument(k, False)));
          Settle;
        end
        else if Cmd = 'savedocas' then begin
          Form.SaveCurrentAs(T[1]);
          Settle;
          WriteLn('SAVEDOCAS ', T[1]);
        end
        else if Cmd = 'windowmenu' then
          WriteLn('WINDOW ', Form.WindowMenuText)
        else if Cmd = 'addsheet' then begin
          Form.DoAddSheet(nil);
          Settle;
          WriteLn('ADDSHEET');
        end
        else if Cmd = 'removesheet' then begin
          WriteLn('REMOVESHEET ', Ord(Form.RemoveCurrentSheet(False)));
          Settle;
        end
        else if Cmd = 'renamesheet' then begin
          Form.RenameCurrentSheet(T[1]);
          Settle;
          WriteLn('RENAMESHEET ', T[1]);
        end
        else if Cmd = 'movesheet' then begin
          Form.MoveCurrentSheet(StrToInt(T[1]));
          Settle;
          WriteLn('MOVESHEET ', T[1]);
        end
        else if Cmd = 'gosheet' then
        begin
          { what clicking a sheet tab does }
          Form.tcSheetTabs.TabIndex := StrToInt(T[1]);
          Form.SheetTabChange(Form.tcSheetTabs);
          Settle;
          WriteLn('GOSHEET ', T[1]);
        end
        else if Cmd = 'tabmarks' then
        begin
          { tabmarks : TABMARKS images=<pictures in the list> size=<w>x<h> marks=<the picture asked for by each tab: 0 current, 1 other, -1 the + tab> current=<sheet> tabs=<number of tabs> linked=<0|1> }
          Txt := '';
          for k := 0 to Form.tcSheetTabs.Tabs.Count - 1 do
          begin
            OptI := 99;
            Form.SheetTabImage(Form.tcSheetTabs, k, OptI);
            Txt := Txt + IntToStr(OptI) + ',';
          end;
          WriteLn('TABMARKS images=', frmSharedControls.ilSheetTabs.Count, ' size=', frmSharedControls.ilSheetTabs.Width, 'x', frmSharedControls.ilSheetTabs.Height, ' marks=', Txt,
            ' current=', Form.View.SheetIndex, ' tabs=', Form.tcSheetTabs.Tabs.Count, ' linked=', Ord(Form.tcSheetTabs.Images = frmSharedControls.ilSheetTabs));
        end
        else if Cmd = 'sheetinfo' then
        begin
          { SHEETS count current=<view index> tabs=<tab captions> names=<sheet names, with their object counts> }
          Txt := '';
          for k := 0 to Form.Design.SheetCount - 1 do
            Txt := Txt + Form.Design.Sheets[k].SheetName + ':' + IntToStr(Form.Design.Sheets[k].Drawing.Count) + ',';
          WriteLn('SHEETS ', Form.Design.SheetCount, ' current=', Form.View.SheetIndex, ' tabs=', Form.tcSheetTabs.Tabs.CommaText, ' names=', Txt);
        end
        else if (Cmd = 'numinput') or (Cmd = 'gridcustom') then
        begin
          { numinput <text> <low> <high> : what the number dialog makes of the text typed in it;
            gridcustom <text>            : the same, with the grid size range, then used as the grid size }
          if Cmd = 'gridcustom' then
            NI := TfrmNumInput.Create(Form, [fcbOK, fcbCancel], 0.05, 100, 'Enter a new grid size:')
          else
            NI := TfrmNumInput.Create(Form, [fcbOK, fcbCancel], Num(T[2]), Num(T[3]), 'Enter a number:');
          try
            if T[1] = '<empty>' then
              NI.edInput.Text := ''
            else
              NI.edInput.Text := T[1];      // (an empty word cannot be written in a script)
            if NI.ValidInput then
            begin
              WriteLn('NUMINPUT ok value=', NI.FInput);
              if Cmd = 'gridcustom' then
                Form.SetGridMmFromScript(Num(NI.FInput));
            end
            else
              WriteLn('NUMINPUT refused: ', NI.ErrorText);
          finally
            NI.Free;
          end;
          Settle;
        end
        else if Cmd = 'polyinfo' then
        begin
          { the one selected polygon: POLY handles=<n> close=<0|1> points=<flattened points> box=<mm> then
            POLYH <n> <x mm> <y mm> <arc type> <control x mm> <control y mm> <screen x> <screen y> for each handle }
          if (Form.View.SelectedCount = 1) and (Form.View.SelectedObject(0) is TDrawPolygon) then
          begin
            Pg := Form.View.SelectedObject(0) as TDrawPolygon;
            WriteLn('POLY handles=', Length(Pg.Handles), ' close=', Pg.Close, ' points=', Length(Pg.Points), ' box=',
              FormatFloat('0.###', Min(Pg.PointA.x, Pg.PointB.x) / 5, FmtDot), ',', FormatFloat('0.###', Min(Pg.PointA.y, Pg.PointB.y) / 5, FmtDot), '-',
              FormatFloat('0.###', Max(Pg.PointA.x, Pg.PointB.x) / 5, FmtDot), ',', FormatFloat('0.###', Max(Pg.PointA.y, Pg.PointB.y) / 5, FmtDot));
            Txt := '';
            for k := 0 to High(Pg.Points) do
              Txt := Txt + FormatFloat('0.##', (Pg.Points[k].x + Pg.PointA.x) / 5, FmtDot) + ',' + FormatFloat('0.##', (Pg.Points[k].y + Pg.PointA.y) / 5, FmtDot) + ';';
            WriteLn('POLYPTS ', Txt);
            for k := 0 to High(Pg.Handles) do
            begin
              PxPt := Form.View.DesignToScreen(DPoint(Pg.Handles[k].X + Pg.PointA.x, Pg.Handles[k].Y + Pg.PointA.y));
              WriteLn('POLYH ', k, ' ', FormatFloat('0.###', (Pg.Handles[k].X + Pg.PointA.x) / 5, FmtDot), ' ',
                FormatFloat('0.###', (Pg.Handles[k].Y + Pg.PointA.y) / 5, FmtDot), ' ', Pg.Handles[k].Arc, ' ',
                FormatFloat('0.###', (Pg.Handles[k].Control.x + Pg.PointA.x) / 5, FmtDot), ' ',
                FormatFloat('0.###', (Pg.Handles[k].Control.y + Pg.PointA.y) / 5, FmtDot), ' ', PxPt.x, ' ', PxPt.y);
            end;
          end
          else
            WriteLn('POLY none');
        end
        else if Cmd = 'polyaction' then
        begin
          { polyaction <freeline|arcin|arcout|curve|addhandle|deletehandle> <x mm> <y mm> : a choice of the polygon menu }
          S := LowerCase(T[1]);
          if S = 'freeline' then
            PA := paFreeLine
          else if S = 'arcin' then
            PA := paArcIn
          else if S = 'arcout' then
            PA := paArcOut
          else if S = 'curve' then
            PA := paCurve
          else if S = 'addhandle' then
            PA := paAddHandle
          else
            PA := paDeleteHandle;
          WriteLn('POLYACTION ', S, ' changed=', Ord(Form.View.PolygonAction(PA, DPoint(Num(T[2]) * 5, Num(T[3]) * 5))));
          Settle;
        end
        else if Cmd = 'polyarc' then
        begin
          { polyarc <none|in|out> : the kind of segment for the points of the next polygon drawn }
          S := LowerCase(T[1]);
          if S = 'in' then
            Form.View.SetDrawArcType(Arc_in) else if S = 'out' then
            Form.View.SetDrawArcType(Arc_out)
          else
            Form.View.SetDrawArcType(Arc_none);
          WriteLn('POLYARC ', Form.View.DrawArcType);
        end
        else if Cmd = 'sheetribbon' then
        begin
          { sheetribbon <field> <value> ... : sets a control of the details panel on the ribbon and commits it as a person
            does: rulers / border by clicking the check box, cols / rows / margin by typing and pressing Enter; the same name
            followed by x (colsx ...) leaves the box instead of pressing Enter, followed by esc (colsesc ...) presses Esc }
          k := 1;
          while k + 1 < T.Count do
          begin
            S := LowerCase(T[k]);
            if S = 'rulers' then
            begin
              Form.sbSheetDetails.Checked := T[k + 1] = '1';      // (the button turns over by itself on a click)
              Form.DoDesignDetailsRuler(Form.sbSheetDetails);
            end
            else if S = 'border' then
            begin
              Form.DetailsDrop.cbSheetDetailsBorder.Checked := T[k + 1] = '1';
              Form.DoDesignDetailsBorder(Form.DetailsDrop.cbSheetDetailsBorder);
            end
            else if S = 'extended' then
            begin
              Form.sbExtendedInfo.Down := T[k + 1] = '1';
              Form.DoDesignDetailsExtended(Form.sbExtendedInfo);
            end
            else
            begin
              if RightStr(S, 3) = 'esc' then begin
                Mode := 2;
                S := Copy(S, 1, Length(S) - 3);
              end
              else if (RightStr(S, 1) = 'x') then begin
                Mode := 1;
                S := Copy(S, 1, Length(S) - 1);
              end
              else
                Mode := 0;
              if S = 'cols' then
                DEd := Form.DetailsDrop.edSheetDetailsCols
              else if S = 'rows' then
                DEd := Form.DetailsDrop.edSheetDetailsRows
              else
                DEd := Form.DetailsDrop.edSheetDetailsMargin;
              DEd.Text := T[k + 1];
              case Mode of
                0: begin
                  DKey := #13;
                  DEd.OnKeyPress(DEd, DKey);
                end;
                1: DEd.OnExit(DEd);
                2: begin
                  DKey := #27;
                  DEd.OnKeyPress(DEd, DKey);
                end;
              end;
            end;
            Inc(k, 2);
          end;
          Settle;
          WriteLn('SHEETRIBBON done');
        end
        else if Cmd = 'sheetribboninfo' then
        begin
          WriteLn('SHEETRIBBON rulers=', Ord(Form.sbSheetDetails.Checked), ' cols=', Form.DetailsDrop.edSheetDetailsCols.Text,
            ' rows=', Form.DetailsDrop.edSheetDetailsRows.Text, ' border=', Ord(Form.DetailsDrop.cbSheetDetailsBorder.Checked), ' margin=', Form.DetailsDrop.edSheetDetailsMargin.Text,
            ' enabled=', Ord(Form.sbSheetDetails.Enabled), Ord(Form.DetailsDrop.edSheetDetailsCols.Enabled), Ord(Form.DetailsDrop.edSheetDetailsRows.Enabled),
            Ord(Form.DetailsDrop.cbSheetDetailsBorder.Enabled), Ord(Form.DetailsDrop.edSheetDetailsMargin.Enabled), ' snap=', Ord(Form.sbViewGridSnapTo.Down),
            ' extended=', Ord(Form.sbExtendedInfo.Down), Ord(Form.sbExtendedInfo.Enabled));
        end
        else if Cmd = 'ribbonpaints' then
          WriteLn('RIBBONPAINTS ', Form.RibbonPaintCount)
        else if Cmd = 'recent' then
        begin
          { RECENT n <menu entries as caption|full path;> -- the recently used files and the File menu entries made from them }
          WriteLn('RECENT ', MRUCount, ' ', Form.RecentMenuText);
        end
        else if Cmd = 'openrecent' then begin
          Form.OpenRecentFile(StrToInt(T[1]));
          Settle;
          WriteLn('OPENRECENT ', T[1]);
        end
        else if (Cmd = 'find') or (Cmd = 'replace') then
        begin
          { find <text> [case] [word] [up] [sheet]      replace <text> <with> [case] [word] [all] [up] [sheet] [prompt:<answers y/n/c>]
            (the search covers every sheet unless 'sheet' is given: then only the sheet shown)
            the ReplaceDlg component is filled in as the dialog would be, and its own Find Next / Replace
            handler is called; <empty> stands for a replacement of nothing }
          Form.ReplaceDlg.FindText := T[1];
          FO := [frHidePromptOnReplace, frEntireScope];
          k := 2;
          if Cmd = 'replace' then
          begin
            if T[2] = '<empty>' then
              Form.ReplaceDlg.ReplaceText := ''
            else
              Form.ReplaceDlg.ReplaceText := T[2];
            Include(FO, frReplace);
            k := 3;
          end;
          FDown := True;
          while k < T.Count do
          begin
            S := LowerCase(T[k]);
            if S = 'case' then
              Include(FO, frMatchCase)
            else if S = 'word' then
              Include(FO, frWholeWord)
            else if S = 'all' then
              Include(FO, frReplaceAll)
            else if S = 'up' then
              FDown := False
            else if S = 'sheet' then
              Exclude(FO, frEntireScope)
            else if Copy(S, 1, 7) = 'prompt:' then
            begin
              FO := FO - [frHidePromptOnReplace] + [frPromptOnReplace];
              Form.SetFindPrompt(Copy(S, 8, MaxInt));
            end;
            Inc(k);
          end;
          if FDown then
            Include(FO, frDown);
          Form.ReplaceDlg.Options := FO;
          if Cmd = 'find' then
            Form.ReplaceDlgFind(Form.ReplaceDlg)
          else
            Form.ReplaceDlgReplace(Form.ReplaceDlg);
          Settle;
          WriteLn(UpperCase(Cmd), ' ', Form.FindInfoText);
        end
        else if Cmd = 'findnext' then begin
          Form.DoFindNext(nil);
          Settle;
          WriteLn('FINDNEXT ', Form.FindInfoText);
        end
        else if Cmd = 'findprev' then begin
          Form.DoFindPrevious(nil);
          Settle;
          WriteLn('FINDPREV ', Form.FindInfoText);
        end
        else if Cmd = 'sleep' then
        begin
          { sleep <milliseconds> : wait, keeping the window alive and painting (to look at it from outside) }
          SleepEnd := GetTickCount64 + StrToInt(T[1]);
          while GetTickCount64 < SleepEnd do begin
            Application.ProcessMessages;
            Sleep(20);
          end;
          WriteLn('SLEEP ', T[1]);
        end
        else if Cmd = 'icons' then
        begin
          { icons [<folder>] : the size and number of icons in the main form's image list ilTinyIcons; with a folder, each saved as icon_<n>.bmp }
          WriteLn('ICONS count=', Form.ilTinyIcons.Count, ' size=', Form.ilTinyIcons.Width, 'x', Form.ilTinyIcons.Height);
          if T.Count > 1 then
            for k := 0 to Form.ilTinyIcons.Count - 1 do
            begin
              IcoBmp := TBitmap.Create;
              try
                Form.ilTinyIcons.GetBitmap(k, IcoBmp);
                IcoBmp.SaveToFile(IncludeTrailingPathDelimiter(T[1]) + 'icon_' + IntToStr(k) + '.bmp');
              finally
                IcoBmp.Free;
              end;
            end;
        end
        else if Cmd = 'viewpoint' then
        begin
          { viewpoint <x mm> <y mm> : where that point of the sheet is in the window now (to look at what is drawn there) }
          PxPt := Form.View.DesignToScreen(DPoint(Num(T[1]) * 5, Num(T[2]) * 5));
          WriteLn('VIEWPOINT ', PxPt.x, ' ', PxPt.y);
        end
        else if Cmd = 'handlepos' then
          begin
            { handlepos <n> : where handle n (0 top left, 1 top right, 2 bottom right, 3 bottom left, 4 top, 5 right, 6 bottom, 7 left) of the
              one selected rectangle is, in mm }
            if Form.View.SelectedResizable = nil then
              WriteLn('HANDLEPOS none')
            else
            begin
              HR := Form.View.SelectedResizable.ResizeHandleRect(StrToInt(T[1]), Form.View.ResizeHandleSize);
              SnapP := Form.View.ProbeSnap(DPoint((HR.Left + HR.Right) / 2, (HR.Top + HR.Bottom) / 2));
              WriteLn('HANDLEPOS ', T[1], ' ', ((HR.Left + HR.Right) / 2 / UNITS_PER_MM):0:4, ' ', ((HR.Top + HR.Bottom) / 2 / UNITS_PER_MM):0:4,
                ' snap ', (SnapP.x / UNITS_PER_MM):0:4, ' ', (SnapP.y / UNITS_PER_MM):0:4, ' size ', (Form.View.ResizeHandleSize / UNITS_PER_MM):0:4);
            end;
          end
        else if Cmd = 'symname' then
          begin
            { symname : the one selected symbol: SYMNAME name=[..] ref=[..] pins=<count> first=<x mm>,<y mm> (the first pin) lowest=<x mm>,<y mm> (the pin that is first in TinyCAD's order: the left one, the upper of two) }
            if (Form.View.SelectedCount <> 1) or (not (Form.View.SelectedObject(0) is TDrawMethod)) then
              WriteLn('SYMNAME none')
            else
              with TDrawMethod(Form.View.SelectedObject(0)) do
              begin
                PinList := ActivePointsOf(Form.View.SelectedObject(0));
                Before := PinList[0];
                for k := 1 to High(PinList) do
                  if (Abs(PinList[k].x - Before.x) < 0.001) and (PinList[k].y < Before.y) or (PinList[k].x < Before.x - 0.001) then
                    Before := PinList[k];
                WriteLn('SYMNAME name=[', GetName, '] ref=[', GetRef, '] pins=', Length(PinList), ' first=', FormatFloat('0.###', PinList[0].x / UNITS_PER_MM, FmtDot), ',', FormatFloat('0.###', PinList[0].y / UNITS_PER_MM, FmtDot),
                  ' lowest=', FormatFloat('0.###', Before.x / UNITS_PER_MM, FmtDot), ',', FormatFloat('0.###', Before.y / UNITS_PER_MM, FmtDot));
              end;
          end
        else if Cmd = 'symbolinfo' then
          begin
            { symbolinfo : the one selected symbol's box and scale: SYMINFO <ax> <ay> <bx> <by> <scale x> <scale y> <native width> <native height> <rotate> <resizable>,
              the corners and sizes in mm; the native size is the symbol's own, at scale 1 and not turned }
            if (Form.View.SelectedCount <> 1) or (not (Form.View.SelectedObject(0) is TDrawMethod)) then
              WriteLn('SYMINFO none')
            else
              with TDrawMethod(Form.View.SelectedObject(0)) do
              begin
                SnapP := GetSymbolData.GetTr(Part, ShowPower <> 0);
                WriteLn('SYMINFO ', (PointA.x / UNITS_PER_MM):0:5, ' ', (PointA.y / UNITS_PER_MM):0:5, ' ', (PointB.x / UNITS_PER_MM):0:5, ' ', (PointB.y / UNITS_PER_MM):0:5, ' ',
                  ScalingX:0:5, ' ', ScalingY:0:5, ' ', (SnapP.x / UNITS_PER_MM):0:5, ' ', (SnapP.y / UNITS_PER_MM):0:5, ' ', Rotate, ' ', CanScale);
              end;
          end
        else if Cmd = 'textinfo' then
          begin
            { textinfo : the one selected text or label: TEXTINFO text|label <ax> <ay> <bx> <by> <direction> <font number> <font height> <font width> <original width>
              <original box width> <target box width> [<active x> <active y> <label style>]; positions and widths in design units, all numbers with every digit,
              because the resizing truncates what it works out and a rounded number could fall the other side of a whole one }
            if Form.View.SelectedCount <> 1 then
              WriteLn('TEXTINFO none')
            else if Form.View.SelectedObject(0) is TDrawText then
              with TDrawText(Form.View.SelectedObject(0)) do
                WriteLn('TEXTINFO text ', FloatToStrF(PointA.x, ffGeneral, 17, 0, FmtDot), ' ', FloatToStrF(PointA.y, ffGeneral, 17, 0, FmtDot), ' ',
                  FloatToStrF(PointB.x, ffGeneral, 17, 0, FmtDot), ' ', FloatToStrF(PointB.y, ffGeneral, 17, 0, FmtDot), ' ', Dir, ' ', FontStyle, ' ',
                  (Options.Fonts.Get(FontStyle) as TFontResource).Height, ' ', Options.GetFontWidth(FontStyle), ' ', FloatToStrF(OriginalWidth, ffGeneral, 17, 0, FmtDot), ' ',
                  FloatToStrF(OriginalBoxWidth, ffGeneral, 17, 0, FmtDot), ' ', FloatToStrF(TargetBoxWidth, ffGeneral, 17, 0, FmtDot))
            else if Form.View.SelectedObject(0) is TDrawLabel then
              with TDrawLabel(Form.View.SelectedObject(0)) do
                WriteLn('TEXTINFO label ', FloatToStrF(PointA.x, ffGeneral, 17, 0, FmtDot), ' ', FloatToStrF(PointA.y, ffGeneral, 17, 0, FmtDot), ' ',
                  FloatToStrF(PointB.x, ffGeneral, 17, 0, FmtDot), ' ', FloatToStrF(PointB.y, ffGeneral, 17, 0, FmtDot), ' ', Dir, ' ', FontStyle, ' ',
                  (Options.Fonts.Get(FontStyle) as TFontResource).Height, ' ', Options.GetFontWidth(FontStyle), ' ', FloatToStrF(OriginalWidth, ffGeneral, 17, 0, FmtDot), ' ',
                  FloatToStrF(OriginalBoxWidth, ffGeneral, 17, 0, FmtDot), ' ', FloatToStrF(TargetBoxWidth, ffGeneral, 17, 0, FmtDot), ' ',
                  FloatToStrF(ActivePoint.x, ffGeneral, 17, 0, FmtDot), ' ', FloatToStrF(ActivePoint.y, ffGeneral, 17, 0, FmtDot), ' ', LabelStyle)
            else
              WriteLn('TEXTINFO none');
          end
        else if Cmd = 'options' then
          begin
            { options <name>=<value> ... : the Options dialog is filled in the way a person would and then OK is pressed (nothing is applied if what is
              typed cannot be used). Names: grid (a number, in the units the dialog shows), units (mm or in), showgrid, snap, autodrag, autosnap, autojunction
              (0 or 1), range (design units), autosave (minutes; 0 for none), symfont (a font name), symsize (points), symbold, symitalic (0 or 1), sheetborder, sheetrulers (0 or 1), sheetcols (a number), sheetrows (a letter), sheetmargin (mm: what the sheet of a new design starts with) }
            OptF := TfrmOptions.Create(Form);
            try
              OptF.LoadFromData(Form.CurrentOptions);
              for OptI := 1 to T.Count - 1 do
              begin
                OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
                OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
                if OptKey = 'grid' then
                  OptF.edGrid.Text := OptVal
                else if OptKey = 'units' then
                begin
                  OptF.rgUnits.ItemIndex := Ord(LowerCase(OptVal) = 'in');
                  OptF.UnitsClick(nil);
                end
                else if OptKey = 'showgrid' then
                  OptF.cbShowGrid.Checked := OptVal = '1'
                else if OptKey = 'snap' then
                  OptF.cbSnapGrid.Checked := OptVal = '1'
                else if OptKey = 'autodrag' then
                  OptF.cbAutoDrag.Checked := OptVal = '1'
                else if OptKey = 'autosnap' then
                begin
                  OptF.cbAutoSnap.Checked := OptVal = '1';
                  OptF.AutoSnapClick(nil);
                end
                else if OptKey = 'autojunction' then
                  OptF.cbAutoJunction.Checked := OptVal = '1'
                else if OptKey = 'range' then
                  OptF.edRange.Text := OptVal
                else if OptKey = 'symfont' then
                  begin
                    OptF.cbSymbolFont.FontName := OptVal;
                    OptF.SymbolFontChange(nil);
                  end
                else if OptKey = 'symsize' then
                  begin
                    OptF.cbSymbolSize.Text := OptVal;
                    OptF.SymbolFontChange(nil);
                  end
                else if OptKey = 'symbold' then
                  OptF.sbBold.Down := OptVal = '1'
                else if OptKey = 'symitalic' then
                  OptF.sbItalic.Down := OptVal = '1'
                else if OptKey = 'reopen' then
                  OptF.cbReopen.Checked := OptVal = '1'
                else if OptKey = 'sheetborder' then
                begin
                  OptF.cbSheetDetailsBorder.Checked := OptVal = '1';
                  OptF.SheetBorderClick(nil);
                end
                else if OptKey = 'sheetrulers' then
                begin
                  OptF.cbSheetDetailsShowRuler.Checked := OptVal = '1';
                  OptF.SheetRulerClick(nil);
                end
                else if OptKey = 'sheetcols' then
                  OptF.edSheetDetailsCols.Text := OptVal
                else if OptKey = 'sheetrows' then
                  OptF.edSheetDetailsRows.Text := OptVal
                else if OptKey = 'sheetmargin' then
                  OptF.edSheetDetailsMargin.Text := OptVal
                else if OptKey = 'autosave' then
                begin
                  OptF.cbAutoSave.Checked := OptVal <> '0';
                  if OptVal <> '0' then
                    OptF.edMinutes.Text := OptVal;
                  OptF.AutoSaveClick(nil);
                end
                else
                  WriteLn('OPTIONS unknown name: ', OptKey);
              end;
              OptKey := OptF.ReadData(OptD);
              WriteLn('OPTIONS err=', OptKey, ' grid=', OptF.edGrid.Text, ' ', OptF.lblGridUnits.Caption, ' preset=', OptF.cbPreset.ItemIndex);
              if OptKey = '' then
                WriteLn('OPTIONS applied=', Ord(Form.ApplyOptions(OptD)));
            finally
              OptF.Free;
            end;
            Settle;
          end
        else if Cmd = 'colors' then
          begin
            { colors <name>=<RRGGBB> ... or colors reset [<name>=<RRGGBB> ...] : the Colors dialog is filled in as a person does (a color chosen, or Defaults pressed) and OK pressed.
              Names: wire bus junction noconnect label power pin hiddenpin background notefill noteline notetext (or the number) }
            ColF := TfrmOptions.Create(Form);
            try
              if (Form.Design <> nil) and (Form.View.Sheet <> nil) then
                ColF.LoadColors(Form.View.Sheet.Options.Colors)
              else
              begin
                ColT := TUserColors.Create;
                try ColF.LoadColors(ColT); finally ColT.Free; end;
              end;
              for OptI := 1 to T.Count - 1 do
                if LowerCase(T[OptI]) = 'reset' then
                  ColF.ResetToStandard
                else
                begin
                  OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
                  OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
                  ColId := 0;
                  if OptKey = 'wire' then
                    ColId := UC_WIRE else if OptKey = 'bus' then
                    ColId := UC_BUS else if OptKey = 'junction' then
                    ColId := UC_JUNCTION
                  else if OptKey = 'noconnect' then
                    ColId := UC_NOCONNECT else if OptKey = 'label' then
                    ColId := UC_LABEL else if OptKey = 'power' then
                    ColId := UC_POWER
                  else if OptKey = 'pin' then
                    ColId := UC_PIN else if OptKey = 'hiddenpin' then
                    ColId := UC_HIDDEN_PIN else if OptKey = 'background' then
                    ColId := UC_BACKGROUND
                  else if OptKey = 'notefill' then
                    ColId := UC_NOTETEXT_FILL else if OptKey = 'noteline' then
                    ColId := UC_NOTETEXT_LINE else if OptKey = 'notetext' then
                    ColId := UC_NOTETEXT_TEXT
                  else
                    ColId := StrToIntDef(OptKey, 0);
                  if ColId = 0 then
                    WriteLn('COLORS unknown name: ', OptKey)
                  else
                  begin
                    ColV := StrToInt('$' + OptVal);
                    { RRGGBB as people write it; a color is held as red + green * 256 + blue * 65536 }
                    ColF.SetColor(ColId, Cardinal(((ColV shr 16) and $FF) or (ColV and $FF00) or ((ColV and $FF) shl 16)));
                  end;
                end;
              Form.ApplyColors(ColF);
              WriteLn('COLORS applied');
            finally
              ColF.Free;
            end;
            Settle;
          end
        else if Cmd = 'colorsinfo' then
          begin
            { colorsinfo : every color of each sheet of the open design as RRGGBB, then the colors that are kept for new designs (- where there is none) }
            if Form.Design <> nil then
              for OptI := 0 to Form.Design.SheetCount - 1 do
              begin
                OptKey := '';
                for ColId := UC_WIRE to UC_NOTETEXT_TEXT do OptKey := OptKey + ' ' + IntToStr(ColId) + '=' + ColorHex(Form.Design.Sheets[OptI].Options.Colors.Get(ColId));
                WriteLn('COLORSINFO sheet ', OptI, OptKey);
              end;
            OptKey := '';
            for ColId := UC_WIRE to UC_NOTETEXT_TEXT do
              if UserColorOverride[ColId] >= 0 then
                OptKey := OptKey + ' ' + IntToStr(ColId) + '=' + ColorHex(Cardinal(UserColorOverride[ColId]))
              else
                OptKey := OptKey + ' ' + IntToStr(ColId) + '=-';
            WriteLn('COLORSINFO kept', OptKey);
            ColT := TUserColors.Create;
            try
              OptKey := '';
              for ColId := UC_WIRE to UC_NOTETEXT_TEXT do OptKey := OptKey + ' ' + IntToStr(ColId) + '=' + ColorHex(ColT.Get(ColId));
              WriteLn('COLORSINFO newdesign', OptKey);
            finally
              ColT.Free;
            end;
          end
        else if Cmd = 'dialogcolors' then
          begin
            { dialogcolors <file> : a picture of the Colors dialog, as it opens now }
            ColF := TfrmOptions.Create(Form);
            try
              if (Form.Design <> nil) and (Form.View.Sheet <> nil) then
                ColF.LoadColors(Form.View.Sheet.Options.Colors)
              else
              begin
                ColT := TUserColors.Create;
                try ColF.LoadColors(ColT); finally ColT.Free; end;
              end;
              ColF.DefaultColorsTab := true;
              ColF.Show;
              Settle;
              SaveForm(ColF, T[1]);
              WriteLn('DIALOGCOLORS ', T[1]);
            finally
              ColF.Free;
            end;
          end
        else if Cmd = 'colorcontrols' then
          begin
            { colorcontrols : the controls of the Colors page of the Options dialog as the form designer left them: COLORCTL <class> <name> tag= left= top= caption= click=0|1 color=<hex>
              parent=<name>, and COLORDLG <class> <name> owner=<name> (the color chooser the Change buttons use) }
            ColF := TfrmOptions.Create(Form);
            try
              for k := 0 to ColF.ComponentCount - 1 do
                if (ColF.Components[k] is TLabel) and (TLabel(ColF.Components[k]).Parent = ColF.pnlColors) then
                  with TLabel(ColF.Components[k]) do WriteLn('COLORCTL TLabel ', Name, ' tag=', Tag, ' left=', Left, ' top=', Top, ' caption=', Caption, ' click=0 color=- parent=', Parent.Name)
                else if (ColF.Components[k] is TPanel) and (TPanel(ColF.Components[k]).Parent = ColF.pnlColors) then
                  with TPanel(ColF.Components[k]) do WriteLn('COLORCTL TPanel ', Name, ' tag=', Tag, ' left=', Left, ' top=', Top, ' caption=', Caption, ' click=0 color=', IntToHex(Color, 6), ' parent=', Parent.Name)
                else if (ColF.Components[k] is TButton) and (TButton(ColF.Components[k]).Parent = ColF.pnlColors) then
                  with TButton(ColF.Components[k]) do WriteLn('COLORCTL TButton ', Name, ' tag=', Tag, ' left=', Left, ' top=', Top, ' caption=', Caption, ' click=', Ord(Assigned(OnClick)), ' color=- parent=', Parent.Name);
              WriteLn('COLORDLG ', frmSharedControls.DlgColor.ClassName, ' ', frmSharedControls.DlgColor.Name, ' owner=', frmSharedControls.DlgColor.Owner.Name);
            finally
              ColF.Free;
            end;
          end
        else if Cmd = 'themeinfo' then
          WriteLn('THEMEINFO dark=', Ord(Form.Theme = themeDark), ' caption=', Form.mTheme.Caption, ' setting=', Ord(ProgramSettings.DarkMode))
        else if Cmd = 'dotheme' then
          begin
            { dotheme : View > Dark Mode / Light Mode chosen from the menu }
            Form.mTheme.Click;
            Settle;
          end
        else if Cmd = 'menuselect' then
          begin
            { menuselect <component name> : the cursor goes onto a menu item (what the toolkit does when it is highlighted); prints MENUSELECT <name> hint=<its Hint> panel0=<the status bar's first panel> enabled=<0|1> checked=<0|1> }
            if Form.FindComponent(T[1]) is TMenuItem then
            begin
              TMenuItem(Form.FindComponent(T[1])).IntfDoSelect;
              WriteLn('MENUSELECT ', T[1], ' hint=', TMenuItem(Form.FindComponent(T[1])).Hint, ' panel0=', Form.sbMainBar.Panels[0].Text, ' enabled=', Ord(TMenuItem(Form.FindComponent(T[1])).Enabled), ' checked=', Ord(TMenuItem(Form.FindComponent(T[1])).Checked));
            end
            else
              WriteLn('MENUSELECT ', T[1], ' none');
          end
        else if Cmd = 'menuclick' then
          begin
            { menuclick <component name> : a menu item is chosen (its OnClick runs, and the check of a radio item follows what the handler does); prints MENUCLICK <name> or MENUCLICK <name> none }
            if Form.FindComponent(T[1]) is TMenuItem then
            begin
              TMenuItem(Form.FindComponent(T[1])).Click;
              Settle;
              WriteLn('MENUCLICK ', T[1]);
            end
            else
              WriteLn('MENUCLICK ', T[1], ' none');
          end
        else if Cmd = 'picinfo' then
          begin
            { picinfo : the one selected picture: PICINFO a=<x>,<y> b=<x>,<y> (mm) rot=<quarter turns right> mirror=<0|1> (its orientation, see UOrient) }
            if (Form.View.SelectedCount = 1) and (Form.View.SelectedObject(0) is TDrawMetaFile) then
              with TDrawMetaFile(Form.View.SelectedObject(0)) do
              begin
                OptI := 0; OptD.ShowGrid := False;
                if not OrientToTurns(Orient, OptI, OptD.ShowGrid) then
                  OptI := -1;
                WriteLn('PICINFO a=', (PointA.x / UNITS_PER_MM):0:4, ',', (PointA.y / UNITS_PER_MM):0:4, ' b=', (PointB.x / UNITS_PER_MM):0:4, ',', (PointB.y / UNITS_PER_MM):0:4,
                  ' rot=', OptI, ' mirror=', Ord(OptD.ShowGrid));
              end
            else
              WriteLn('PICINFO none');
          end
        else if Cmd = 'dupcheck' then
          begin
            { dupcheck : Special > Check Duplicate References; prints DUPREF <report line> for each duplicate and DUPCHECK status=<the message shown> }
            Form.CheckDuplicateRefs(False);
            S := Form.CheckDuplicateRefs(True);
            Lines2 := TStringList.Create;
            try
              Lines2.Text := S;
              for k := 0 to Lines2.Count - 1 do
                WriteLn('DUPREF ', Lines2[k]);
            finally
              Lines2.Free;
            end;
            WriteLn('DUPCHECK status=', Form.sbMainBar.Panels[0].Text);
            Settle;
          end
        else if Cmd = 'symbom' then
          begin
            { symbom <file> : Special > Export Symbol BoM (CSV) to that file; prints SYMBOM wrote=<0|1> status=<the warning, if any> }
            Form.sbMainBar.Panels[0].Text := '';
            WriteLn('SYMBOM wrote=', Ord(Form.WriteSymbolBom(T[1])), ' status=', Form.sbMainBar.Panels[0].Text);
            Settle;
          end
        else if Cmd = 'symdata' then
          begin
            { symdata <file> : Special > Export Symbol Data (CSV) to that file; prints SYMDATA wrote=<0|1> }
            WriteLn('SYMDATA wrote=', Ord(Form.WriteSymbolData(T[1])));
            Settle;
          end
        else if Cmd = 'partslist' then
          begin
            { partslist <name>=<value> ... : Special > Create Parts List with the dialog filled in as a person does, then Export pressed (or, with cancel=1, Cancel).
              Names: type (0 text, 1 CSV, 2 spreadsheet CSV; chosen in the list, so the extension of the file name follows), file (a path; "none" for an empty box), sheets, attrs,
              prefix, hier (0 or 1). Prints PARTSLIST start ... (what the dialog shows first), PARTSLIST export ... (what it holds when Export is pressed, with the registry
              values kept) and PARTSLIST wrote=<0|1> status=<the status bar text> (the message the user would have been given) }
            BomF := TfrmPartsList.Create(Form);
            try
              BomF.LoadFromSettings(Form.CurrentFileName);
              WriteLn('PARTSLIST start type=', BomF.cbType.ItemIndex, ' file=', BomF.edFile.Text, ' sheets=', Ord(BomF.cbAllSheets.Checked), ' attrs=', Ord(BomF.cbAttrs.Checked),
                ' prefix=', Ord(BomF.cbPrefix.Checked), ' hier=', Ord(BomF.cbHier.Checked), ' button=', BomF.btnOK.Caption);
              BomOk := True;
              for OptI := 1 to T.Count - 1 do
              begin
                OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
                OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
                if OptKey = 'type' then
                  BomF.SelectType(StrToIntDef(OptVal, 0))
                else if OptKey = 'file' then
                begin
                  if OptVal = 'none' then
                    BomF.edFile.Text := ''
                  else
                    BomF.edFile.Text := OptVal;
                end
                else if OptKey = 'sheets' then
                  BomF.cbAllSheets.Checked := OptVal = '1'
                else if OptKey = 'attrs' then
                  BomF.cbAttrs.Checked := OptVal = '1'
                else if OptKey = 'prefix' then
                  BomF.cbPrefix.Checked := OptVal = '1'
                else if OptKey = 'hier' then
                  BomF.cbHier.Checked := OptVal = '1'
                else if OptKey = 'cancel' then
                  BomOk := OptVal <> '1'
                else
                  WriteLn('PARTSLIST unknown name: ', OptKey);
              end;
              WriteLn('PARTSLIST export type=', BomF.cbType.ItemIndex, ' file=', BomF.edFile.Text, ' sheets=', Ord(BomF.cbAllSheets.Checked), ' attrs=', Ord(BomF.cbAttrs.Checked),
                ' prefix=', Ord(BomF.cbPrefix.Checked), ' hier=', Ord(BomF.cbHier.Checked), ' ok=', Ord(BomOk));
              if BomOk then
              begin
                Form.View.CancelTool;
                BomF.KeepInSettings;
                SaveSettings;
                Form.sbMainBar.Panels[0].Text := '';
                BomOk := Form.WritePartsList(BomF.FileName, BomF.Options);
                WriteLn('PARTSLIST wrote=', Ord(BomOk), ' status=', Form.sbMainBar.Panels[0].Text);
              end;
            finally
              BomF.Free;
            end;
            Settle;
          end
        else if Cmd = 'exportimage' then
          begin
            { exportimage <name>=<value> ... : File > Export Image with the dialog filled in as a person does, then Export pressed (or, with cancel=1, Cancel). Names: type (0 to 3:
              colour PNG, B&W PNG, colour SVG, B&W SVG; chosen in the list, so the extension of the file name follows), file (a path; "none" for an empty box), scale (the text typed),
              rotate (0 or 1), cancel (0 or 1). What is saved is the selection, or the sheet showing when nothing is selected. Prints EXPORTIMAGE start ... (what the dialog shows first),
              EXPORTIMAGE export ... (what it holds when Export is pressed; "stays open <reason>" when it would not close), and EXPORTIMAGE wrote=<0|1> status=<the status bar text> }
            ExpF := Form.BeginExportImage;
            try
              WriteLn('EXPORTIMAGE start type=', ExpF.Kind, ' file=', ExpF.edFile.Text, ' scale=', ExpF.edScale.Text, ' rotate=', Ord(ExpF.Rotate), ' scaleenabled=', Ord(ExpF.edScale.Enabled),
                ' rotateenabled=', Ord(ExpF.cbRotate.Enabled), ' button=', ExpF.btnOK.Caption, ' kinds=', ExpF.cbType.Items.Count, ' what=', ExpF.lblWhat.Caption);
              BomOk := True;
              for OptI := 1 to T.Count - 1 do
              begin
                OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
                OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
                if OptKey = 'type' then
                  ExpF.SelectKind(StrToIntDef(OptVal, 0))
                else if OptKey = 'file' then
                begin
                  if OptVal = 'none' then
                    ExpF.edFile.Text := ''
                  else
                    ExpF.edFile.Text := OptVal;
                end
                else if OptKey = 'scale' then
                  ExpF.edScale.Text := OptVal
                else if OptKey = 'rotate' then
                  ExpF.cbRotate.Checked := OptVal = '1'
                else if OptKey = 'cancel' then
                  BomOk := OptVal <> '1'
                else
                  WriteLn('EXPORTIMAGE unknown name: ', OptKey);
              end;
              WriteLn('EXPORTIMAGE export type=', ExpF.Kind, ' file=', ExpF.edFile.Text, ' scale=', ExpF.edScale.Text, ' scaleenabled=', Ord(ExpF.edScale.Enabled), ' rotate=', Ord(ExpF.Rotate),
                ' ok=', Ord(BomOk), ' error=[', ExpF.ValidationError, ']');
              if BomOk and (ExpF.ValidationError = '') then
              begin
                Form.sbMainBar.Panels[0].Text := '';
                BomOk := Form.ExportImageFile(ExpF);
                WriteLn('EXPORTIMAGE wrote=', Ord(BomOk), ' status=', Form.sbMainBar.Panels[0].Text);
              end
              else if BomOk then
                WriteLn('EXPORTIMAGE stays open');
            finally
              ExpF.Free;
            end;
            Settle;
          end
        else if Cmd = 'netlist' then
          begin
            { netlist <name>=<value> ... : Special > Create PCB Net List with the dialog filled in as a person does, then Export pressed (or, with cancel=1, Cancel).
              Names: type (0 to 6: TinyCAD, PADS-PCB, PADS-PCB-WITH-VALUE, Eagle SCR, Protel, gEDA PCB, XML; chosen in the list, so the extension of the file name follows), file
              (a path; "none" for an empty box), prefix (0 or 1). Prints NETLIST start ... (what the dialog shows first), NETLIST export ... (what it holds when Export is pressed)
              and NETLIST wrote=<0|1> status=<the status bar text> }
            NetF := Form.BeginNetList;      // (the design rules are checked first, as the menu does)
            try
              WriteLn('NETLIST start type=', NetF.Format, ' file=', NetF.edFile.Text, ' prefix=', Ord(NetF.cbPrefix.Checked), ' button=', NetF.btnOK.Caption, ' formats=', NetF.cbType.Items.Count);
              BomOk := True;
              for OptI := 1 to T.Count - 1 do
              begin
                OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
                OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
                if OptKey = 'type' then
                  NetF.SelectType(StrToIntDef(OptVal, 0))
                else if OptKey = 'file' then
                begin
                  if OptVal = 'none' then
                    NetF.edFile.Text := ''
                  else
                    NetF.edFile.Text := OptVal;
                end
                else if OptKey = 'prefix' then
                  NetF.cbPrefix.Checked := OptVal = '1'
                else if OptKey = 'cancel' then
                  BomOk := OptVal <> '1'
                else
                  WriteLn('NETLIST unknown name: ', OptKey);
              end;
              WriteLn('NETLIST export type=', NetF.Format, ' file=', NetF.edFile.Text, ' prefix=', Ord(NetF.cbPrefix.Checked), ' ok=', Ord(BomOk));
              if BomOk then
              begin
                Form.View.CancelTool;
                Form.sbMainBar.Panels[0].Text := '';
                BomOk := Form.ExportNetList(NetF);
                WriteLn('NETLIST wrote=', Ord(BomOk), ' status=', Form.sbMainBar.Panels[0].Text);
              end;
            finally
              NetF.Free;
            end;
            Settle;
          end
        else if (Cmd = 'spice') or (Cmd = 'vhdl') then
          begin
            { spice|vhdl <name>=<value> ... : Special > Create Spice Net List / Create VHDL file with the Save dialog answered as a person does: file=<path> ("none" for an empty
              name), or cancel=1 for Cancel. Prints SPICE|VHDL start file=<the name the dialog proposes> and SPICE|VHDL wrote=<0|1> status=<the status bar text> }
            BomOk := True;
            if Cmd = 'spice' then
              OptVal := Form.BeginSpice
            else
              OptVal := Form.BeginVhdl;      // (the design rules are checked first, as the menu does)
            WriteLn(UpperCase(Cmd), ' start file=', OptVal);
            for OptI := 1 to T.Count - 1 do
            begin
              OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
              if OptKey = 'file' then
              begin
                OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
                if OptVal = 'none' then
                  OptVal := '';
              end
              else if OptKey = 'cancel' then
                BomOk := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt) <> '1'
              else
                WriteLn(UpperCase(Cmd), ' unknown name: ', OptKey);
            end;
            if BomOk then
            begin
              Form.View.CancelTool;
              Form.sbMainBar.Panels[0].Text := '';
              if Cmd = 'spice' then
                BomOk := Form.ExportSpice(OptVal)
              else
                BomOk := Form.ExportVhdl(OptVal);
              WriteLn(UpperCase(Cmd), ' wrote=', Ord(BomOk), ' status=', Form.sbMainBar.Panels[0].Text);
            end;
            Settle;
          end
        else if Cmd = 'annotatedialog' then
          begin
            { annotatedialog <name>=<value> ... : Special > Generate Symbol References answered as a person does (no dialog is shown). Names: action (add remove), which (all
              unnum match), match, value (default start), start (text typed in the start box), all (0 1), press (ok painter cancel). Prints ANNOTATEDIALOG <what it showed,
              the choices when the button was pressed and what happened> }
            AnnoOpts := TStringList.Create;
            try
              for k := 1 to T.Count - 1 do AnnoOpts.Add(T[k]);
              WriteLn('ANNOTATEDIALOG ', Form.AnnotateScriptRun(AnnoOpts));
            finally
              AnnoOpts.Free;
            end;
            Settle;
          end
        else if Cmd = 'annotatenext' then
          begin
            { annotatenext <name>=<value> ... : the next time the command is run (from the menu or the Design Markers window) its dialog is answered like this;
              annotatenext alone puts the dialog back }
            if Form.AnnotateScript = nil then
              Form.AnnotateScript := TStringList.Create;
            Form.AnnotateScript.Clear;
            for k := 1 to T.Count - 1 do Form.AnnotateScript.Add(T[k]);
            if T.Count = 1 then
              FreeAndNil(Form.AnnotateScript);
          end
        else if Cmd = 'annotatereport' then
          WriteLn('ANNOTATEREPORT ', Form.AnnotateReport)
        else if Cmd = 'annotaterefs' then
          WriteLn('ANNOTATEREFS ', Form.AnnotateRefsText)
        else if Cmd = 'annotatemenu' then
          WriteLn('ANNOTATEMENU ', Form.mAnnotate.Caption, ' enabled=', Ord(Form.mAnnotate.Enabled), ' index=', Form.mAnnotate.MenuIndex, ' hint=', Form.mAnnotate.Hint,
            ' check=', Form.mCheckRules.MenuIndex, ' vhdlcheck=', Form.mVhdlCheck.MenuIndex, ' parts=', Form.mPartsList.MenuIndex)
        else if Cmd = 'annotateclick' then
          begin
            { annotateclick <x mm> <y mm> [right] : a click of the reference painter (or any tool) at a point of the sheet }
            P := Form.View.DesignToScreen(DPoint(Num(T[1]) * UNITS_PER_MM, Num(T[2]) * UNITS_PER_MM));
            if (T.Count > 3) and (T[3] = 'right') then
              Form.View.RightClickAt(P.x, P.y)
            else
              Form.View.ClickAt(P.x, P.y, []);
            Settle;
            WriteLn('ANNOTATECLICK tool=', Ord(Form.View.Tool), ' ', Form.AnnotateRefsText);
          end
        else if Cmd = 'printsink' then
          begin
            { printsink <folder> [dpi] : File > Print and Print Preview use A4 bitmap pages (at dpi, 100 by default), written to the folder as page_<n>.png, in place of the
              printer; printsink alone puts the printer back }
            if T.Count > 1 then
            begin
              Form.PrintSinkDir := T[1];
              if T.Count > 2 then
                Form.PrintTestDpi := StrToIntDef(T[2], 100)
              else
                Form.PrintTestDpi := 100;
            end
            else
              Form.PrintSinkDir := '';
          end
        else if Cmd = 'printdialog' then
          begin
            { printdialog <name>=<value> ... : File > Print answered as a person does (no dialog is shown). Names: scale (typed in the Scale box), bw (0 1), sheets (current all), fit
              (0 1), from, to, copies, collate (what the system's Print dialog would give), press (ok cancel). Prints PRINTDIALOG <what it showed, the choices when the button was
              pressed and what happened> }
            AnnoOpts := TStringList.Create;
            try
              for k := 1 to T.Count - 1 do AnnoOpts.Add(T[k]);
              WriteLn('PRINTDIALOG ', Form.PrintScriptRun(AnnoOpts));
            finally
              AnnoOpts.Free;
            end;
            Settle;
          end
        else if Cmd = 'printnext' then
          begin
            { printnext <name>=<value> ... : the next time File > Print is run (from the menu) its dialog is answered like this; printnext alone puts the dialog back }
            if Form.PrintScript = nil then
              Form.PrintScript := TStringList.Create;
            Form.PrintScript.Clear;
            for k := 1 to T.Count - 1 do Form.PrintScript.Add(T[k]);
            if T.Count = 1 then
              FreeAndNil(Form.PrintScript);
          end
        else if Cmd = 'printreport' then
          WriteLn('PRINTREPORT ', Form.PrintReport)
        else if Cmd = 'printmenu' then
          WriteLn('PRINTMENU ', Form.mPrint.Caption, ' enabled=', Ord(Form.mPrint.Enabled), ' index=', Form.mPrint.MenuIndex, ' shortcut=', ShortCutToTextRaw(Form.mPrint.ShortCut), ' | ',
            Form.mPrintPreview.Caption, ' enabled=', Ord(Form.mPrintPreview.Enabled), ' index=', Form.mPrintPreview.MenuIndex, ' | ', Form.mPageSetup.Caption, ' enabled=',
            Ord(Form.mPageSetup.Enabled), ' index=', Form.mPageSetup.MenuIndex, ' | ', Form.mPrintSetup.Caption, ' enabled=', Ord(Form.mPrintSetup.Enabled), ' index=',
            Form.mPrintSetup.MenuIndex, ' | save=', Form.mSaveAll.MenuIndex, ' sep=', Form.mSep1.MenuIndex, ' exit=', Form.mExit.MenuIndex, ' hints=', Form.mPrint.Hint, '/',
            Form.mPrintPreview.Hint, '/', Form.mPageSetup.Hint, '/', Form.mPrintSetup.Hint, ' dialogs=', Form.PrintDlg.ClassName, '/', Form.dlgPrinterSetup.ClassName, '/',
            Form.dlgPageSetup.ClassName, ' installed=', Ord(Form.PrinterInstalled))
        else if Cmd = 'printsetup' then
          begin
            { printsetup : File > Print Setup... ; with no printer installed it says so in the status bar }
            Form.sbMainBar.Panels[0].Text := '';
            Form.DoPrintSetup(nil);
            WriteLn('PRINTSETUP status=', Form.sbMainBar.Panels[0].Text);
          end
        else if Cmd = 'previewrun' then
          begin
            { previewrun <action> ... : File > Print Preview worked like a person (no window is shown): next prev two zoomin zoomout info page=<n> press=close|print. Prints
              PREVIEWRUN <the window's state when it opened and after each action> }
            AnnoOpts := TStringList.Create;
            try
              for k := 1 to T.Count - 1 do AnnoOpts.Add(T[k]);
              WriteLn('PREVIEWRUN ', Form.PreviewScriptRun(AnnoOpts));
            finally
              AnnoOpts.Free;
            end;
            Settle;
          end
        else if Cmd = 'previewnext' then
          begin
            { previewnext <action> ... : the next time File > Print Preview is run (from the menu) it is worked like this; alone puts the window back }
            if Form.PreviewScript = nil then
              Form.PreviewScript := TStringList.Create;
            Form.PreviewScript.Clear;
            for k := 1 to T.Count - 1 do Form.PreviewScript.Add(T[k]);
            if T.Count = 1 then
              FreeAndNil(Form.PreviewScript);
          end
        else if Cmd = 'previewreport' then
          WriteLn('PREVIEWREPORT ', Form.PreviewReport)
        else if Cmd = 'printerpage' then
          begin
            { printerpage <none|WxH> : what the printer answers (in mm) to the Printer Paper and Printer Setup buttons of the Page Setup dialog; alone asks the printer }
            if T.Count > 1 then
              Form.PrinterPageScript := T[1]
            else
              Form.PrinterPageScript := '';
          end
        else if Cmd = 'pagesetupprinter' then
          begin
            { pagesetupprinter <paper|setup> [landscape|portrait] : the Page Setup dialog opened, the orientation chosen when one is given, and the Printer Paper (or Printer
              Setup) button pressed. Prints PAGESETUPPRINTER w= h= orient= paper= used=0/1 status= and applies nothing }
            PF := TfrmPageSetup.Create(Form);
            try
              PF.OnPrinterPage := @Form.PrinterPageFor;
              PF.LoadFromSheet(Form.View.Sheet);
              if T.Count > 2 then
              begin
                if LowerCase(T[2]) = 'portrait' then
                  PF.rgOrient.ItemIndex := 1
                else
                  PF.rgOrient.ItemIndex := 0;
                PF.OrientChange(nil);
              end;
              Form.sbMainBar.Panels[0].Text := '';
              if LowerCase(T[1]) = 'setup' then
                BomOk := PF.UsePrinterPage(True)
              else
                BomOk := PF.UsePrinterPage(False);
              if PF.lbPapers.ItemIndex >= 0 then
                S := PF.lbPapers.Items[PF.lbPapers.ItemIndex]
              else
                S := '(custom)';
              WriteLn('PAGESETUPPRINTER w=', PF.edWidth.Text, ' h=', PF.edHeight.Text, ' orient=', PF.rgOrient.Items[PF.rgOrient.ItemIndex], ' paper=', S, ' used=', Ord(BomOk),
                ' captions=', PF.btnPrinterPaper.Caption, '|', PF.btnPrinterSetup.Caption, ' status=', Form.sbMainBar.Panels[0].Text);
            finally
              PF.Free;
            end;
            Settle;
          end
        else if Cmd = 'ercdialog' then
          begin
            { ercdialog <name>=<value> ... : Special > Check Design Rules (vhdl=1: V&HDL Check Design Rules) with the options dialog filled as a person does, then Check pressed (or
              cancel=1). Names: word (all eleven checks as TinyCAD's WORD), vhdl, and one per box set to 0 or 1: dupref unconnect noconnect unassigned power outputpwr output nooutput
              unconnected multiple nondistinct. Prints ERCDIALOG start ... (the boxes in that order as 0/1, the title, the group titles and the button), ERCDIALOG pressed ... and
              ERCDIALOG errors=<n> word=<the kept WORD> }
            ErcF := Form.BeginErcDialog;
            try
              BomOk := True; Vhdl := False;
              WriteLn('ERCDIALOG start word=', ErcOptionsToWord(ErcF.Options), ' title=', ErcF.Caption, ' errors=', ErcF.gbErrors.Caption, ' warnings=', ErcF.gbWarnings.Caption,
                ' button=', ErcF.btnOK.Caption, ' boxes=', Ord(ErcF.cbDupRef.Checked), Ord(ErcF.cbUnConnect.Checked), Ord(ErcF.cbNoConnect.Checked), Ord(ErcF.cbUnassigned.Checked),
                Ord(ErcF.cbPower.Checked), Ord(ErcF.cbOutputPwr.Checked), Ord(ErcF.cbOutput.Checked), Ord(ErcF.cbNoOutput.Checked), Ord(ErcF.cbUnConnected.Checked),
                Ord(ErcF.cbMultiple.Checked), Ord(ErcF.cbNonCase.Checked), ' captions=', ErcF.cbDupRef.Caption, '|', ErcF.cbUnConnect.Caption, '|', ErcF.cbNoConnect.Caption, '|',
                ErcF.cbUnassigned.Caption, '|', ErcF.cbPower.Caption, '|', ErcF.cbOutputPwr.Caption, '|', ErcF.cbOutput.Caption, '|', ErcF.cbNoOutput.Caption, '|',
                ErcF.cbUnConnected.Caption, '|', ErcF.cbMultiple.Caption, '|', ErcF.cbNonCase.Caption);
              for OptI := 1 to T.Count - 1 do
              begin
                OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
                OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
                if OptKey = 'word' then
                  ErcF.SetOptions(ErcOptionsFromWord(Word(StrToInt(OptVal))))
                else if OptKey = 'vhdl' then
                  Vhdl := OptVal = '1'
                else if OptKey = 'cancel' then
                  BomOk := OptVal <> '1'
                else if OptKey = 'dupref' then
                  ErcF.cbDupRef.Checked := OptVal = '1'
                else if OptKey = 'unconnect' then
                  ErcF.cbUnConnect.Checked := OptVal = '1'
                else if OptKey = 'noconnect' then
                  ErcF.cbNoConnect.Checked := OptVal = '1'
                else if OptKey = 'unassigned' then
                  ErcF.cbUnassigned.Checked := OptVal = '1'
                else if OptKey = 'power' then
                  ErcF.cbPower.Checked := OptVal = '1'
                else if OptKey = 'outputpwr' then
                  ErcF.cbOutputPwr.Checked := OptVal = '1'
                else if OptKey = 'output' then
                  ErcF.cbOutput.Checked := OptVal = '1'
                else if OptKey = 'nooutput' then
                  ErcF.cbNoOutput.Checked := OptVal = '1'
                else if OptKey = 'unconnected' then
                  ErcF.cbUnConnected.Checked := OptVal = '1'
                else if OptKey = 'multiple' then
                  ErcF.cbMultiple.Checked := OptVal = '1'
                else if OptKey = 'nondistinct' then
                  ErcF.cbNonCase.Checked := OptVal = '1'
                else
                  WriteLn('ERCDIALOG unknown name: ', OptKey);
              end;
              WriteLn('ERCDIALOG pressed word=', ErcOptionsToWord(ErcF.Options), ' vhdl=', Ord(Vhdl), ' ok=', Ord(BomOk));
              if BomOk then
              begin
                OptI := Form.FinishErcDialog(ErcF, Vhdl);
                WriteLn('ERCDIALOG errors=', OptI, ' word=', ProgramSettings.ErcWord);
              end;
            finally
              ErcF.Free;
            end;
            Settle;
          end
        else if Cmd = 'partcheck' then
          begin
            { partcheck [on=0|1] [unresolved=0|1|2] [oversized=0|1] : the settings of the parts check (a part with no product chosen: not reported, warning, error); prints PARTCHECK on=.. unresolved=.. oversized=.. }
            for OptI := 1 to T.Count - 1 do
            begin
              OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
              OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
              if OptKey = 'on' then
                ProgramSettings.PartCheck := OptVal = '1'
              else if OptKey = 'unresolved' then
                ProgramSettings.PartCheckUnresolved := StrToIntDef(OptVal, 1)
              else if OptKey = 'oversized' then
                ProgramSettings.PartCheckOversized := OptVal = '1'
              else
                WriteLn('PARTCHECK unknown name: ', OptKey);
            end;
            WriteLn('PARTCHECK on=', Ord(ProgramSettings.PartCheck), ' unresolved=', ProgramSettings.PartCheckUnresolved, ' oversized=', Ord(ProgramSettings.PartCheckOversized));
          end
        else if Cmd = 'check' then
          begin
            { check [vhdl=0|1] [show=0|1] : the check itself, as the netlist commands run it first (show=0, the default: the list opens only when there are errors) or as the dialog's
              Check does (show=1). Prints CHECK errors=<n> }
            Vhdl := False; BomOk := False;
            for OptI := 1 to T.Count - 1 do
            begin
              OptKey := LowerCase(Copy(T[OptI], 1, Pos('=', T[OptI]) - 1));
              OptVal := Copy(T[OptI], Pos('=', T[OptI]) + 1, MaxInt);
              if OptKey = 'vhdl' then
                Vhdl := OptVal = '1'
              else if OptKey = 'show' then
                BomOk := OptVal = '1'
              else
                WriteLn('CHECK unknown name: ', OptKey);
            end;
            WriteLn('CHECK errors=', Form.RunCheck(Vhdl, BomOk));
            Settle;
          end
        else if Cmd = 'ercwindow' then
          WriteLn('ERCWINDOW ', Form.ErcWindowText)
        else if Cmd = 'ercmarkers' then
          WriteLn('ERCMARKERS ', Form.ErcMarkersText)
        else if Cmd = 'ercchoose' then
          begin
            { ercchoose <line> : a line of the Design Markers window is clicked }
            Form.ErcChoose(StrToInt(T[1]));
            Settle;
            WriteLn('ERCCHOOSE ', Form.ErcMarkersText);
          end
        else if Cmd = 'ercpress' then
          begin
            { ercpress <close|recheck|annotate> : a button of the Design Markers window is pressed }
            Form.ErcPress(T[1]);
            Settle;
            WriteLn('ERCPRESS ', T[1], ' ', Form.ErcWindowText);
          end
        else if Cmd = 'ercmenu' then
          WriteLn('ERCMENU check=', Form.mCheckRules.Caption, ' checkenabled=', Ord(Form.mCheckRules.Enabled), ' checkindex=', Form.mCheckRules.MenuIndex, ' vhdlcheck=', Form.mVhdlCheck.Caption,
            ' vhdlcheckenabled=', Ord(Form.mVhdlCheck.Enabled), ' vhdlcheckindex=', Form.mVhdlCheck.MenuIndex, ' net=', Form.mNetList.MenuIndex, ' parts=', Form.mPartsList.MenuIndex,
            ' hint=', Form.mVhdlCheck.Hint)
        else if Cmd = 'partsmenu' then
          begin
            { partsmenu : the Special menu and its Create Parts List item as the main window has them now }
            WriteLn('PARTSMENU menu=', Form.mSpecial.Caption, ' item=', Form.mPartsList.Caption, ' enabled=', Ord(Form.mPartsList.Enabled), ' index=', Form.mSpecial.MenuIndex,
              ' net=', Form.mNetList.Caption, ' netenabled=', Ord(Form.mNetList.Enabled), ' netindex=', Form.mNetList.MenuIndex,
              ' spice=', Form.mSpice.Caption, ' spiceenabled=', Ord(Form.mSpice.Enabled), ' vhdl=', Form.mVhdl.Caption, ' vhdlenabled=', Ord(Form.mVhdl.Enabled),
              ' spiceindex=', Form.mSpice.MenuIndex, ' vhdlindex=', Form.mVhdl.MenuIndex, ' partsindex=', Form.mPartsList.MenuIndex);
          end
        else if Cmd = 'saveall' then
          begin
            { saveall : File > Save All without asking for names: every design with unsaved changes and a file is saved; SAVEALL saved=<n> skipped=<n without a name> failed=<n> }
            OptI := Form.SaveAllDocuments(False, ColId, OptKey);
            WriteLn('SAVEALL saved=', OptI, ' skipped=', ColId, ' failed=', Length(OptKey) - Length(StringReplace(OptKey, #10, '', [rfReplaceAll])));
            Settle;
          end
        else if Cmd = 'fsdel' then
          begin
            { fsdel <path> : a test hook: a file, or an empty folder, is deleted (to make a save fail, or a remembered design go missing) }
            if DirectoryExists(T[1]) then
              WriteLn('FSDEL ', Ord(RemoveDir(T[1])))
            else
              WriteLn('FSDEL ', Ord(DeleteFile(T[1])));
          end
        else if Cmd = 'sessionsave' then begin
          Form.SaveSession;
          WriteLn('SESSIONSAVE');
        end
        else if Cmd = 'sessionrestore' then begin
          WriteLn('SESSIONRESTORE ', Form.RestoreSession);
          Settle;
        end
        else if Cmd = 'sessioninfo' then
          begin
            { sessioninfo : what is remembered: SESSIONINFO reopen=<0|1> active=<n> files=<a>|<b>|... }
            OptKey := '';
            for OptI := 0 to SESSION_MAX - 1 do
              if ProgramSettings.SessionFiles[OptI] <> '' then
                OptKey := OptKey + ProgramSettings.SessionFiles[OptI] + '|';
            WriteLn('SESSIONINFO reopen=', Ord(ProgramSettings.ReopenDesigns), ' active=', ProgramSettings.SessionActive, ' files=', OptKey);
          end
        else if Cmd = 'layoutinfo' then
          begin
            { layoutinfo : LAYOUT left= top= width= height= max= leftw= previewh= (the window and the splitters now), then SAVED left= top= width= height= max= leftw= previewh= (what was loaded from the registry) }
            WriteLn('LAYOUT left=', Form.Left, ' top=', Form.Top, ' width=', Form.Width, ' height=', Form.Height, ' max=', Ord(Form.WindowState = wsMaximized), ' leftw=', Form.pnlLeft.Width,
              ' previewh=', Form.frameLibraryPanel.pbPreview.Height);
            with ProgramSettings do
              WriteLn('SAVED left=', WinLeft, ' top=', WinTop, ' width=', WinWidth, ' height=', WinHeight, ' max=', Ord(WinMaximized), ' leftw=', SplitLeftWidth, ' previewh=', SplitPreviewHeight);
          end
        else if Cmd = 'layoutset' then
          begin
            { layoutset <left> <top> <width> <height> <panel width> <preview height> : moves the window and the splitters }
            Form.SetBounds(StrToInt(T[1]), StrToInt(T[2]), StrToInt(T[3]), StrToInt(T[4]));
            Form.pnlLeft.Width := StrToInt(T[5]);
            Form.frameLibraryPanel.pbPreview.Height := StrToInt(T[6]);
            Settle;
            WriteLn('LAYOUTSET');
          end
        else if Cmd = 'fitwindow' then
          begin
            { fitwindow <l> <t> <w> <h> <minw> <minh> <work areas as l,t,r,b ...> : FitSavedWindow: FITWINDOW ok=<0|1> l t r b }
            SetLength(FitWorks, T.Count - 7);
            for k := 7 to T.Count - 1 do
              begin
                FitParts := TStringList.Create;
                try
                  FitParts.CommaText := T[k];
                  FitWorks[k - 7] := Rect(StrToInt(FitParts[0]), StrToInt(FitParts[1]), StrToInt(FitParts[2]), StrToInt(FitParts[3]));
                finally
                  FitParts.Free;
                end;
              end;
            FitOk := FitSavedWindow(Rect(StrToInt(T[1]), StrToInt(T[2]), StrToInt(T[1]) + StrToInt(T[3]), StrToInt(T[2]) + StrToInt(T[4])), FitWorks, StrToInt(T[5]), StrToInt(T[6]), FitRect);
            WriteLn('FITWINDOW ok=', Ord(FitOk), ' ', FitRect.Left, ' ', FitRect.Top, ' ', FitRect.Right, ' ', FitRect.Bottom);
          end
        else if Cmd = 'closequery' then
          begin
            { closequery : what happens when the window is closed: the check for unsaved changes (so only with none), and the session is remembered }
            Form.FormCloseQuery(Form, CqOk);
            WriteLn('CLOSEQUERY canclose=', Ord(CqOk));
          end
        else if Cmd = 'pdbopen' then
          begin
            { pdbopen <file> : opens a TyCAD parts file (upgrading it by the rules of UPartsDb); PARTSOPEN ok version=.. name=.. uid=.. parts=.. classes=.. or PARTSOPEN error <message> }
            FreeAndNil(ScriptParts);
            ScriptParts := TPartsLibrary.Create;
            try
              ScriptParts.Open(T[1]);
              WriteLn('PARTSOPEN ok version=', ScriptParts.SchemaVersion, ' name=', ScriptParts.LibraryName, ' uid=', ScriptParts.LibraryUID, ' parts=', ScriptParts.PartCount, ' classes=', ScriptParts.ClassCount);
            except
              on E: EPartsError do
              begin
                FreeAndNil(ScriptParts);
                WriteLn('PARTSOPEN error ', E.Message);
              end;
            end;
          end
        else if Cmd = 'pdblist' then
          begin
            { pdblist : PART <index>|<uid>|<name>|<class>|<description> for every part, in the order the Parts tab lists them }
            if ScriptParts <> nil then
              for k := 0 to ScriptParts.PartCount - 1 do
                WriteLn('PART ', k, '|', ScriptParts.Parts[k].UID, '|', ScriptParts.Parts[k].Name, '|', ScriptParts.Parts[k].ClassName, '|', ScriptParts.Parts[k].Description);
            WriteLn('PART end');
          end
        else if Cmd = 'pdbglyph' then
          begin
            { pdbglyph <index> <size> : PARTGLYPH size=<size found> bytes=<n> crc=<crc32 hex> of the icon nearest to the size }
            if ScriptParts <> nil then
            begin
              S := ScriptParts.GlyphPng(ScriptParts.Parts[StrToInt(T[1])].ID, StrToInt(T[2]), k);
              WriteLn('PARTGLYPH size=', k, ' bytes=', Length(S), ' crc=', LowerCase(IntToHex(crc32(0, PByte(PChar(S)), Length(S)), 1)));
            end;
          end
        else if Cmd = 'pdbratings' then
          begin
            { pdbratings <index> : RATING <object>|<quantity>|<min>|<typ>|<max>|<unit>|<condition> ('-' for a value that is not given) }
            if ScriptParts <> nil then
              for Rt in ScriptParts.Ratings(ScriptParts.Parts[StrToInt(T[1])].ID) do
                WriteLn('RATING ', Rt.ObjectName, '|', Rt.Quantity, '|', IfThen(Rt.HasMin, FloatToStr(Rt.Min), '-'), '|', IfThen(Rt.HasTyp, FloatToStr(Rt.Typ), '-'), '|',
                  IfThen(Rt.HasMax, FloatToStr(Rt.Max), '-'), '|', Rt.Unit_, '|', Rt.Condition);
            WriteLn('RATING end');
          end
        else if Cmd = 'pdbproducts' then
          begin
            { pdbproducts <index> : PRODUCT <manufacturer>|<mpn>|<verdict>|<undersized>|<missing>|<mismatch>|<oversized> for the products of the part's class, in the order offered }
            if ScriptParts <> nil then
              for Pr in ScriptParts.Products(ScriptParts.Parts[StrToInt(T[1])].ID) do
                WriteLn('PRODUCT ', Pr.Manufacturer, '|', Pr.MPN, '|', Pr.Verdict, '|', Pr.Undersized, '|', Pr.Missing, '|', Pr.Mismatch, '|', Pr.Oversized);
            WriteLn('PRODUCT end');
          end
        else if Cmd = 'pdbupgrade' then
          begin
            { pdbupgrade <file> <current version> <step SQL> ... : runs UpgradePartsFile with these steps (the SQL of each step is one token, '_' for a space); PARTSUPGRADE <version> or PARTSUPGRADE error <message> }
            SetLength(PSteps, 0);
            for k := 3 to T.Count - 1 do
            begin
              SetLength(PSteps, Length(PSteps) + 1);
              PSteps[High(PSteps)] := StringReplace(T[k], '_', ' ', [rfReplaceAll]);
            end;
            try
              k := UpgradePartsFile(T[1], StrToInt(T[2]), PSteps);
              WriteLn('PARTSUPGRADE ', k);
            except
              on E: EPartsError do WriteLn('PARTSUPGRADE error ', E.Message);
            end;
          end
        else if Cmd = 'pdbtab' then
          begin
            { pdbtab open <file> | new <file> | rows | select <row> | pixel <row> | selected : the Parts tab of the library panel. open: PDBTAB ok rows=.. caption=.. or PDBTAB error <message>;
              rows: PDBROW <row>|<name>|<class>|<image index> then PDBTAB images=<count in the list> size=<w>x<h>; pixel: PDBPIXEL <row> <RRGGBB> of the middle of the row's icon;
              select: the row is chosen as a click does, PDBTAB selected=<part index> }
            with Form.frameLibraryPanel do
              if LowerCase(T[1]) = 'open' then
              begin
                if OpenPartsFile(T[2]) then
                  WriteLn('PDBTAB ok rows=', PartsRowCount, ' caption=', lbPartsCaption.Caption)
                else
                  WriteLn('PDBTAB error ', PartsError);
              end
              else if LowerCase(T[1]) = 'new' then
              begin
                { pdbtab new <file> : Parts > New Parts Library without the dialog: PDBTAB ok rows=.. caption=.. or PDBTAB error <message> }
                if NewPartsFile(T[2]) then
                  WriteLn('PDBTAB ok rows=', PartsRowCount, ' caption=', lbPartsCaption.Caption)
                else
                  WriteLn('PDBTAB error ', PartsError);
              end
              else if LowerCase(T[1]) = 'rows' then
              begin
                for k := 0 to PartsRowCount - 1 do
                  WriteLn('PDBROW ', k, '|', PartsRowText(k), '|', PartsRowImage(k));
                WriteLn('PDBTAB images=', ilParts.Count, ' size=', ilParts.Width, 'x', ilParts.Height);
              end
              else if LowerCase(T[1]) = 'pixel' then
              begin
                Bm := TBitmap.Create;
                try
                  ilParts.GetBitmap(PartsRowImage(StrToInt(T[2])), Bm);
                  WriteLn('PDBPIXEL ', T[2], ' ', IntToHex(ColorToRGB(Bm.Canvas.Pixels[ilParts.Width div 2, ilParts.Height div 2]), 6));
                finally
                  Bm.Free;
                end;
              end
              else if LowerCase(T[1]) = 'select' then
              begin
                SelectPartRow(StrToInt(T[2]));
                WriteLn('PDBTAB selected=', SelectedPartIndex);
              end;
          end
        else if Cmd = 'pdbplace' then
          begin
            { pdbplace <row> <x mm> <y mm> [yes|no] : double clicks a part of the Parts tab and puts it down at the point; yes / no answer the compatibility warning in advance (default: ask like a person).
              PDBPLACE <row> <placed|refused|nosheet|blocked|nosymbol>; pdbwarn off|on|status sets the "do not show again" setting or reports it }
            if T.Count > 4 then
              if LowerCase(T[4]) = 'yes' then
                Form.PartsWarnMode := 1
              else
                Form.PartsWarnMode := 2;
            WriteLn('PDBPLACE ', T[1], ' ', Form.PlacePartRow(StrToInt(T[1]), Num(T[2]), Num(T[3])));
            Settle;
          end
        else if (Cmd = 'pdbchoose') or (Cmd = 'pdbtype') or (Cmd = 'pdbclear') or (Cmd = 'pdbinfo') or (Cmd = 'pdbfit') then
          PartCommand(Form, T)
        else if Cmd = 'pdbpick' then
          begin
            { pdbpick <manufacturer> <model> | cancel : the Choose Product window for the selected placed part, answered as given; PDBPICK <chosen|cancelled|noselection|nolibrary|nopart|noproduct>.
              pdbpick list : PICKROW <manufacturer>|<model>|<fit words> for the rows the window would show }
            if LowerCase(T[1]) = 'list' then
            begin
              if (Form.frameLibraryPanel.PartsLibrary <> nil) and (Form.View.SelectedCount = 1) and (Form.View.SelectedObject(0) is TDrawMethod) and (PartOf(TDrawMethod(Form.View.SelectedObject(0))) <> nil) then
              begin
                PL := Form.frameLibraryPanel.PartsLibrary;
                Pi := PL.FindPart(PartOf(TDrawMethod(Form.View.SelectedObject(0))).PartInfo.UID);
                for Pr in PL.Products(PL.Parts[Pi].ID) do
                  WriteLn('PICKROW ', Pr.Manufacturer, '|', Pr.MPN, '|', FitWords(Pr.Verdict, Pr.Undersized, Pr.Missing, Pr.Mismatch));
              end;
              WriteLn('PICKROW end');
            end
            else
            begin
              if LowerCase(T[1]) = 'cancel' then
                Form.ProductPickAnswer := 'cancel'
              else
                Form.ProductPickAnswer := T[1] + '|' + T[2];
              WriteLn('PDBPICK ', Form.ChooseProduct);
              Form.ProductPickAnswer := '';
              Settle;
            end;
          end
        else if Cmd = 'pdbfittext' then
          begin
            { pdbfittext : PARTFITTEXT <words> and the detail lines (PARTFITLINE ...) for the selected placed part, as the property frame would show them }
            if (Form.View.SelectedCount = 1) and (Form.View.SelectedObject(0) is TDrawMethod) then
            begin
              WriteLn('PARTFITTEXT ', PartFitText(TDrawMethod(Form.View.SelectedObject(0))));
              WriteLn('PARTFITDETAIL ', StringReplace(PartFitDetail(TDrawMethod(Form.View.SelectedObject(0))), LineEnding, ' ## ', [rfReplaceAll]));
            end;
          end
        else if Cmd = 'libbegin' then
          begin
            { libbegin <row> : chooses the library row and starts placing it, without clicking the sheet; LIBBEGIN <1 when the place tool is in use> }
            Form.frameLibraryPanel.SelectRow(StrToInt(T[1]));
            Form.frameLibraryPanel.PlaceSelected;
            Settle;
            WriteLn('LIBBEGIN ', Ord(Form.View.Tool = vtPlace));
          end
        else if Cmd = 'symframe' then
          begin
            { symframe tool|sel rotate | dir <0 up 1 right 2 down 3 left> | mirror | state : the rotate button of the symbol frame and its menu }
            if T.Count > 3 then
              k := StrToInt(T[3])
            else
              k := 0;
            WriteLn('SYMFRAME ', T[2], ' ', Form.SymbolFrameAct(LowerCase(T[1]) = 'tool', LowerCase(T[2]), k));
            Settle;
          end
        else if Cmd = 'symlist' then
          begin
            { symlist tool|sel open|close|rows|click <row> <col>|type <text>|enter|escape|add|delete|state : the parameter list dropped down from the symbol frame }
            FrameValue := '';
            for k := 3 to T.Count - 1 do
              FrameValue := FrameValue + IfThen(k > 3, ' ', '') + T[k];
            WriteLn('SYMLIST ', T[2], ' ', Form.SymbolListAct(LowerCase(T[1]) = 'tool', LowerCase(T[2]), FrameValue));
            Settle;
          end
        else if Cmd = 'pdbwarn' then
          begin
            if LowerCase(T[1]) = 'off' then
              ProgramSettings.PartsWarningOff := True
            else if LowerCase(T[1]) = 'on' then
              ProgramSettings.PartsWarningOff := False
            else if LowerCase(T[1]) = 'ask' then
              Form.PartsWarnMode := 0;
            WriteLn('PDBWARN off=', Ord(ProgramSettings.PartsWarningOff), ' mode=', Form.PartsWarnMode);
          end
        else if Cmd = 'viewmenuinfo' then
          begin
            { viewmenuinfo : the View menu items that mirror ribbon tools, next to their buttons: VIEWMENUINFO snap=<button><pos button><menu> rulers=<button><menu> ext=<button><menu> grid=<items> checked=<index or -1> captions=<a|b|...>; gridmenuclick <n> : chooses item n (from 0) of the Grid Size submenu }
            Settle;
            OptI := -1;
            GmS := '';
            for GmJ := 0 to Form.miGridSize.Count - 1 do
            begin
              if Form.miGridSize.Items[GmJ].Checked then
                OptI := GmJ;
              if GmJ > 0 then
                GmS := GmS + '|';
              GmS := GmS + Form.miGridSize.Items[GmJ].Caption;
            end;
            WriteLn('VIEWMENUINFO snap=', Ord(Form.sbViewGridSnapTo.Down), Ord(Form.sbPosSnap.Down), Ord(Form.miGridSnap.Checked),
              ' rulers=', Ord(Form.sbSheetDetails.Checked), Ord(Form.miShowRulers.Checked), ' ext=', Ord(Form.sbExtendedInfo.Down), Ord(Form.miExtendedInfo.Checked),
              ' grid=', Form.miGridSize.Count, ' checked=', OptI, ' captions=', GmS);
          end
        else if Cmd = 'gridmenuclick' then
          begin
            Form.miGridSize.Items[StrToInt(T[1])].Click;
            Settle;
            WriteLn('GRIDMENUCLICK ', T[1]);
          end
        else if Cmd = 'positioninfo' then
          WriteLn('POSITIONINFO ', Form.PositionInfo)
        else if Cmd = 'positionshow' then
          begin
            { positionshow 0|1 : shows or hides the Position bar (and keeps the choice); positionshow menu | button : the View menu item or the ribbon button is clicked }
            if LowerCase(T[1]) = 'menu' then
              Form.DoShowPosition(Form.mShowPosition)
            else if LowerCase(T[1]) = 'button' then
            begin
              Form.sbView.Checked := not Form.sbView.Checked;      // (a click on the button turns it over before its handler runs)
              Form.DoShowPosition(Form.sbView);
            end
            else
              Form.ShowPositionBar(T[1] = '1', True);
            Settle;
          end
        else if Cmd = 'viewrulers' then
          begin
            { viewrulers 0|1 : shows or hides the rulers round the drawing area (and keeps the choice); viewrulers menu | button : the View menu item or the check box of the Position panel is clicked }
            if LowerCase(T[1]) = 'menu' then
              Form.DoShowViewRulers(Form.miShowViewRulers)
            else if LowerCase(T[1]) = 'button' then
            begin
              Form.DoShowViewRulers(Form.miAlignShowRulers);      // (the handler turns the item over)
            end
            else
              Form.ShowViewRulers(T[1] = '1', True);
            Settle;
            WriteLn('VIEWRULERS wanted=', Ord(Form.RulersWanted), ' top=', Ord(Form.RulerTop.Visible), ' left=', Ord(Form.RulerLeft.Visible), ' menu=', Ord(Form.miShowViewRulers.Checked),
              ' box=', Ord(Form.miAlignShowRulers.Checked), ' saved=', Ord(ProgramSettings.ShowViewRulers));
          end
        else if Cmd = 'rulerinfo' then
          begin
            { rulerinfo : where the rulers are (in the form) and what they show: RULERINFO ..., then RULERTICK h|v <pixel in the view> <reading> <1 if labelled> for every mark }
            Settle;
            Fp := Form.ScreenToClient(Form.RulerTop.ClientToScreen(Point(0, 0)));
            Fq := Form.ScreenToClient(Form.RulerLeft.ClientToScreen(Point(0, 0)));
            P := Form.ScreenToClient(Form.View.ClientToScreen(Point(0, 0)));
            WriteLn('RULERINFO zoom=', FormatFloat('0.######', Form.View.Zoom, DefaultFormatSettings), ' ox=', FormatFloat('0.###', Form.View.Origin.x, DefaultFormatSettings),
              ' oy=', FormatFloat('0.###', Form.View.Origin.y, DefaultFormatSettings), ' units=', Form.View.Sheet.Options.Units,
              ' top=', Fp.X, ',', Fp.Y, ',', Form.RulerTop.Width, ',', Form.RulerTop.Height, ' left=', Fq.X, ',', Fq.Y, ',', Form.RulerLeft.Width, ',', Form.RulerLeft.Height,
              ' view=', P.X, ',', P.Y, ',', Form.View.ClientWidth, ',', Form.View.ClientHeight, ' visible=', Ord(Form.RulerTop.Visible), Ord(Form.RulerLeft.Visible));
            for k := 0 to High(Form.RulerTop.Ticks) do
              with Form.RulerTop.Ticks[k] do
                WriteLn('RULERTICK h ', Pos, ' ', FormatFloat('0.####', Value, DefaultFormatSettings), ' ', Ord(Major));
            for k := 0 to High(Form.RulerLeft.Ticks) do
              with Form.RulerLeft.Ticks[k] do
                WriteLn('RULERTICK v ', Pos, ' ', FormatFloat('0.####', Value, DefaultFormatSettings), ' ', Ord(Major));
          end
        else if Cmd = 'setorigin' then
          begin
            { setorigin <x mm> <y mm> | none : a test hook: the sheet gets an origin (as a symbol being edited has), from which the position bar measures }
            if (Form.Design <> nil) and (Form.View.Sheet <> nil) then
              if LowerCase(T[1]) = 'none' then
                Form.View.Sheet.Options.Origin := DPointInvalid
              else
                Form.View.Sheet.Options.Origin := DPoint(StrToFloat(T[1], FmtDot) * UNITS_PER_MM, StrToFloat(T[2], FmtDot) * UNITS_PER_MM);
          end
        else if Cmd = 'repeatdir' then
          begin
            { repeatdir nameup | namedown | pinup | pindown : a Repeat Directions menu item is chosen }
            S := LowerCase(T[1]);
            if S = 'nameup' then
              Form.DoRepeatNameUp(Form.mRepeatNameUp)
            else if S = 'namedown' then
              Form.DoRepeatNameDown(Form.mRepeatNameDown)
            else if S = 'pinup' then
              Form.DoRepeatPinUp(Form.mRepeatPinUp)
            else if S = 'pindown' then
              Form.DoRepeatPinDown(Form.mRepeatPinDown)
            else
              WriteLn('? unknown direction ', S);
          end
        else if Cmd = 'repeatinfo' then
          WriteLn('REPEATINFO ', Form.RepeatInfo)
        else if Cmd = 'nextpin' then
          begin
            { nextpin <number> <name> : what the next pin would start with after one with that number and name, by this design's directions (for the symbol editor, not yet ported) }
            OptKey := T[1]; OptVal := T[2];
            NextPinValues(OptKey, OptVal, Form.View.PinDir, Form.View.NameDir);
            WriteLn('NEXTPIN ', OptKey, ' ', OptVal);
          end
        else if Cmd = 'gridcycle' then begin
          Form.DoToggleGridSize(Form.sbPosGridSize);
          Settle;
        end
        else if Cmd = 'positionsnap' then begin
          Form.sbPosSnap.Down := not Form.sbPosSnap.Down;
          Form.DoToggleSnap(Form.sbPosSnap);
          Settle;
        end
        else if Cmd = 'dialogoptions' then
          begin
            { dialogoptions <file> [page 0-2] : a picture of the Options dialog, as it opens now }
            OptF := TfrmOptions.Create(Form);
            try
              OptF.LoadFromData(Form.CurrentOptions);
              if T.Count > 2 then
                OptF.pcOptions.ActivePageIndex := StrToInt(T[2]);
              OptF.Show; Settle;
              SaveForm(OptF, T[1]);
              WriteLn('DIALOGOPTIONS ', T[1]);
            finally
              OptF.Free;
            end;
          end
        else if Cmd = 'optionsinfo' then
          begin
            { optionsinfo : what the open design (the sheet showing and every sheet), the program's settings and what a new design starts with hold }
            OptD := Form.CurrentOptions;
            WriteLn('OPTIONSINFO now showgrid=', Ord(OptD.ShowGrid), ' snap=', Ord(OptD.SnapGrid), ' grid=', NumberText(OptD.GridMm), ' units=', OptD.Units,
              ' autodrag=', Ord(OptD.AutoDrag), ' autosnap=', Ord(OptD.AutoSnap), ' autojunction=', Ord(OptD.AutoJunction), ' range=', OptD.AutoSnapRange);
            if Form.Design <> nil then
              for OptI := 0 to Form.Design.SheetCount - 1 do
                with Form.Design.Sheets[OptI] do
                  WriteLn('OPTIONSINFO sheet ', OptI, ' grid=', NumberText(Snap.Grid / 5), ' snap=', Snap.GridSnap, ' show=', Options.GridShow, ' units=', Options.Units,
                    ' autodrag=', Ord(Options.AutoDrag), ' autosnap=', Ord(Options.AutoSnap), ' autojunction=', Ord(Options.AutoJunction), ' range=', Options.AutoSnapRange);
            with ProgramSettings do
              WriteLn('OPTIONSINFO settings showgrid=', Ord(ShowGrid), ' snap=', Ord(SnapGrid), ' grid=', NumberText(GridMm), ' units=', Units, ' autodrag=', Ord(AutoDrag),
                ' autosnap=', Ord(AutoSnap), ' autojunction=', Ord(AutoJunction), ' range=', AutoSnapRange, ' autosave=', AutoSaveMinutes, ' reopen=', Ord(ReopenDesigns),
                ' newsheet=', Ord(NewSheetBorder), Ord(NewSheetRulers), '/', NewSheetCols, '/', NewSheetRows, '/', NumberText(NewSheetMarginMm));
            with EditDefaults do
              WriteLn('OPTIONSINFO defaults showgrid=', Ord(ShowGrid), ' snap=', Ord(SnapGrid), ' grid=', NumberText(GridMm), ' units=', Units, ' autodrag=', Ord(AutoDrag),
                ' autosnap=', Ord(AutoSnap), ' autojunction=', Ord(AutoJunction), ' range=', AutoSnapRange);
            WriteLn('OPTIONSINFO symbolfont now=', OptD.SymbolFontName, '/', OptD.SymbolFontPoints, '/', Ord(OptD.SymbolFontBold), '/', Ord(OptD.SymbolFontItalic),
              ' settings=', ProgramSettings.SymbolFontName, '/', ProgramSettings.SymbolFontPoints, '/', Ord(ProgramSettings.SymbolFontBold), '/', Ord(ProgramSettings.SymbolFontItalic));
            if Form.Design <> nil then
              for OptI := 0 to Form.Design.SheetCount - 1 do
              begin
                Form.Design.Sheets[OptI].Options.GetSymbolFont(OptKey, k, FontB, FontI);
                WriteLn('OPTIONSINFO symbolfont sheet ', OptI, ' ', OptKey, '/', k, '/', Ord(FontB), '/', Ord(FontI), ' height=',
                  (Form.Design.Sheets[OptI].Options.Fonts.Get(fPIN) as TFontResource).Height);
              end;
            WriteLn('OPTIONSINFO autosave ', Form.AutoSaveInfo);
          end
        else if Cmd = 'autosave' then
          WriteLn('AUTOSAVE ', Form.AutoSaveAll)
        else if Cmd = 'snapat' then
          begin
            { snapat <x mm> <y mm> : the grid point a pointer pressed there would snap to (in mm) }
            SnapP := Form.View.ProbeSnap(DPoint(Num(T[1]) * UNITS_PER_MM, Num(T[2]) * UNITS_PER_MM));
            WriteLn('SNAPAT ', T[1], ' ', T[2], ' ', (SnapP.x / UNITS_PER_MM):0:4, ' ', (SnapP.y / UNITS_PER_MM):0:4);
          end
        else if Cmd = 'fieldinfo' then
          begin
            { fieldinfo : each field of the one selected symbol: FIELD <n> <shown 0/1> <x> <y> <width> <height> snap <sx> <sy> <text>, the box in mm on the sheet
              (x, y is where the text sits; the box reaches right by the width and up by the height), the grid point a press at the middle of the
              box snaps to, and the symbol's own origin }
            if (Form.View.SelectedCount <> 1) or (not (Form.View.SelectedObject(0) is TDrawMethod)) then
              WriteLn('FIELDINFO none')
            else
              with TDrawMethod(Form.View.SelectedObject(0)) do
              begin
                WriteLn('FIELDINFO origin ', (PointA.x / UNITS_PER_MM):0:4, ' ', (PointA.y / UNITS_PER_MM):0:4, ' count ', Length(Fields));
                for k := 0 to High(Fields) do
                begin
                  FSize := Options.TextExtent(GetDecoratedField(k), fPIN);
                  SnapP := Form.View.ProbeSnap(DPoint(PointA.x + Fields[k].Position.x + FSize.cx / 2, PointA.y + Fields[k].Position.y - FSize.cy / 2));
                  WriteLn('FIELD ', k, ' ', Fields[k].Show, ' ', ((PointA.x + Fields[k].Position.x) / UNITS_PER_MM):0:4, ' ',
                    ((PointA.y + Fields[k].Position.y) / UNITS_PER_MM):0:4, ' ', (FSize.cx / UNITS_PER_MM):0:4, ' ', (FSize.cy / UNITS_PER_MM):0:4, ' snap ',
                    (SnapP.x / UNITS_PER_MM):0:4, ' ', (SnapP.y / UNITS_PER_MM):0:4, ' ', GetDecoratedField(k));
                end;
              end;
          end
        else if Cmd = 'cursor' then
          begin
            { cursor : the pointer the view is showing now }
            if Form.View.Cursor = crSizeNWSE then
              WriteLn('CURSOR NWSE')
            else if Form.View.Cursor = crSizeNESW then
              WriteLn('CURSOR NESW')
            else if Form.View.Cursor = crSizeNS then
              WriteLn('CURSOR NS')
            else if Form.View.Cursor = crSizeWE then
              WriteLn('CURSOR WE')
            else if Form.View.Cursor = crSizeAll then
              WriteLn('CURSOR ALL')
            else if Form.View.Cursor = crDefault then
              WriteLn('CURSOR default')
            else
              WriteLn('CURSOR ', Form.View.Cursor);
          end
        else if Cmd = 'picture' then
        begin
          { picture <file> : Insert picture: a PNG, JPEG or BMP file becomes a picture that follows the mouse until it is placed }
          WriteLn('PICTURE ', Ord(Form.InsertPicture(T[1])), ' ', T[1]);
          Settle;
        end
        else if Cmd = 'import' then
        begin
          { import <file> : Import (Ctrl+I): the file's first sheet is read into this sheet and follows the mouse until it is placed }
          WriteLn('IMPORT ', Form.ImportDesign(T[1]), ' ', T[1]);
          Settle;
        end
        else if Cmd = 'insertdesign' then
        begin
          { insertdesign <file> : Special > Insert another design as symbol: the design follows the mouse until it is clicked }
          WriteLn('INSERTDESIGN ', Ord(Form.InsertDesign(T[1])), ' ', T[1], ' status=[', Form.sbMainBar.Panels[0].Text, ']');
          Settle;
        end
        else if Cmd = 'addhier' then
        begin
          { addhier : Special > Add hierarchical symbol }
          WriteLn('ADDHIER ', Ord(Form.AddHierarchicalSymbol));
          Settle;
        end
        else if Cmd = 'shellcopy' then
        begin
          { shellcopy <from> <to> : copies a file over another (a design changed while the program runs) }
          Src := TFileStream.Create(T[1], fmOpenRead);
          try
            Dst := TFileStream.Create(T[2], fmCreate);
            try Dst.CopyFrom(Src, 0); finally Dst.Free; end;
          finally Src.Free; end;
          WriteLn('SHELLCOPY ', T[2]);
        end
        else if Cmd = 'reloaddesign' then
        begin
          { reloaddesign : Special > Reload symbol from design (the selected placed design) }
          WriteLn('RELOADDESIGN ', Ord(Form.ReloadSelectedDesign), ' status=[', Form.sbMainBar.Panels[0].Text, ']');
          Settle;
        end
        else if Cmd = 'changedesign' then
        begin
          { changedesign <file> : Special > Change design of symbol }
          WriteLn('CHANGEDESIGN ', Ord(Form.ChangeSelectedDesign(T[1])), ' ', T[1], ' status=[', Form.sbMainBar.Panels[0].Text, ']');
          Settle;
        end
        else if Cmd = 'opendesign' then
        begin
          { opendesign : Special > Open design of symbol }
          WriteLn('OPENDESIGN ', Ord(Form.OpenSelectedDesign));
          Settle;
        end
        else if Cmd = 'hiermenu' then
        begin
          { hiermenu : which hierarchical menu items are enabled, after the menus have been brought up to date }
          Form.HierarchyMenuOpen(nil);
          WriteLn('HIERMENU insert=', Ord(Form.mInsertDesign.Enabled), ' add=', Ord(Form.mAddHierSymbol.Enabled), ' addsheet=', Ord(Form.mAddHierSheet.Enabled),
            ' reload=', Ord(Form.mReloadHier.Enabled), ' change=', Ord(Form.mChangeHier.Enabled), ' open=', Ord(Form.mOpenHier.Enabled));
        end
        else if Cmd = 'copyto' then
        begin
          { copyto <file> : Copy to (Ctrl+E): the selected objects are saved as a design file }
          WriteLn('COPYTO ', Form.CopySelectionTo(T[1]), ' ', T[1]);
          Settle;
        end
        else if Cmd = 'finder' then
        begin
          { finder <text> [sheet] : the find panel is opened (Ctrl+F) and the text searched for; with 'sheet' the Search all Sheets box is cleared first }
          Form.DoFind(nil);
          Form.FindPanel.FindInAll := not ((T.Count > 2) and (LowerCase(T[2]) = 'sheet'));
          Form.RunFindPanel(T[1]);
          Settle;
          WriteLn('FINDER ', Form.FindPanelText);
        end
        else if Cmd = 'findpick' then
        begin
          { findpick <n> : the n-th entry of the list is clicked (0 is the first), through the list box's own handler }
          Form.FindPanel.lbFindResults.ItemIndex := StrToInt(T[1]);
          Form.FindPanel.lbFindResultsClick(Form.FindPanel.lbFindResults);
          Settle;
          WriteLn('FINDPICK sheet=', Form.View.SheetIndex, ' ', Form.FindPanelText);
        end
        else if Cmd = 'findclose' then
        begin
          Form.FindPanel.btnClose.Click;           // the red X
          Settle;
          WriteLn('FINDCLOSE ', Form.FindPanelText);
        end
        else if Cmd = 'findpanel' then
          WriteLn('FINDPANEL sheet=', Form.View.SheetIndex, ' ', Form.FindPanelText)
        else if Cmd = 'findhits' then
          WriteLn('FINDHITS ', Form.FindHitsText)
        else if Cmd = 'findinfo' then
          WriteLn('FINDINFO ', Form.FindInfoText)
        else if Cmd = 'finddialog' then
        begin
          { finddialog open | close : the Find and Replace dialog itself is shown and put away }
          if LowerCase(T[1]) = 'open' then
            Form.DoFindReplace(nil)
          else
            Form.ReplaceDlg.CloseDialog;
          Settle;
          WriteLn('FINDDIALOG ', T[1]);
        end
        else if Cmd = 'gridup' then begin
          Form.DoGridSizeUp(nil);
          Settle;
          WriteLn('GRIDUP');
        end
        else if Cmd = 'detailsinfo' then
          WriteLn('DETAILSINFO ', Form.DetailsInfoText)
        else if Cmd = 'details' then
        begin
          { details <field> <value> ...  or  details revadd <label> <date> <author> <approved> <notes>
            -- the Design Details dialog's own controls are set and applied through the real code }
          DF := TfrmDetails.Create(Form);
          try
            DF.LoadFromSheet(Form.View.Sheet, Form.Design, Form.View.SheetIndex);
            ApplyAll := False;
            k := 1;
            while k < T.Count do
            begin
              S := LowerCase(T[k]);
              if S = 'title' then
                DF.edTitle.Text := T[k + 1]
              else if S = 'author' then
                DF.edAuthor.Text := T[k + 1]
              else if S = 'org' then
                DF.edOrg.Text := T[k + 1]
              else if S = 'docno' then
                DF.edDocNo.Text := T[k + 1]
              else if S = 'revision' then
                DF.edRevision.Text := T[k + 1]
              else if S = 'date' then
                DF.edDate.Text := T[k + 1]
              else if S = 'sheets' then
                DF.edSheets.Text := T[k + 1]
              else if S = 'horiz' then
                DF.edHoriz.Text := T[k + 1]
              else if S = 'vert' then
                DF.edVert.Text := T[k + 1]
              else if S = 'margin' then
                DF.edMargin.Text := T[k + 1]
              else if S = 'autosheets' then begin
                DF.cbAutoSheets.Checked := T[k + 1] = '1';
                DF.StateChange(DF.cbAutoSheets);
              end
              else if S = 'visible' then
                DF.cbVisible.Checked := T[k + 1] = '1'
              else if S = 'rulers' then begin
                DF.cbRulers.Checked := T[k + 1] = '1';
                DF.StateChange(DF.cbRulers);
              end
              else if S = 'border' then begin
                DF.cbBorder.Checked := T[k + 1] = '1';
                DF.StateChange(DF.cbBorder);
              end
              else if S = 'revadd' then
              begin
                DF.AddRevisionEntry(T[k + 1], T[k + 2], T[k + 3], T[k + 4], T[k + 5]);
                Inc(k, 4);
              end
              else if S = 'ext' then
                DF.cbExtended.Checked := T[k + 1] = '1'
              else if S = 'all' then
              begin
                ApplyAll := True;     // the Apply to All button instead of OK
                Dec(k);
              end
              else if S = 'sortrev' then begin
                DF.cbSortRev.Checked := T[k + 1] = '1';
                DF.StateChange(DF.cbSortRev);
              end
              else if S = 'notes' then
                DF.memNotes.Text := StringReplace(T[k + 1], '\n', LineEnding, [rfReplaceAll])
              else if S = 'reference' then
                DF.memReference.Text := StringReplace(T[k + 1], '\n', LineEnding, [rfReplaceAll])
              else if S = 'gridadd' then
              begin
                { gridadd : the last row of the grid is clicked, which adds a revision }
                DF.GridAddRow;
                Dec(k);
              end
              else if S = 'gridset' then
              begin
                { gridset <column 0-3> <row> <text> : a cell of the grid is typed in (row 1 is the first revision) }
                DF.GridSetCell(StrToInt(T[k + 1]), StrToInt(T[k + 2]), StringReplace(T[k + 3], '\n', #10, [rfReplaceAll]));
                Inc(k, 2);
              end
              else if S = 'griddel' then
                DF.DeleteGridRow(StrToInt(T[k + 1]))
              else if S = 'revbox' then
                DF.edRevision.Text := T[k + 1]
              else
                WriteLn('? unknown details field ', S);
              Inc(k, 2);
            end;
            Err := DF.ValidationError;
            { what the dialog shows now: the Revision box (read-only, the newest), the grid of the extended information and the list of the Revisions page }
            WriteLn('DETAILSDLG revbox=', DF.edRevision.Text, ' readonly=', Ord(DF.edRevision.ReadOnly), ' rows=', DF.GridRowCount, ' list=', DF.lbRevisions.Items.Count,
              ' ext=', Ord(DF.cbExtended.Checked), ' sortrev=', Ord(DF.cbSortRev.Checked),
              ' docno=', DF.edDocNo.Text, ' docnoen=', Ord(DF.edDocNo.Enabled), ' sheets=', DF.edSheets.Text, ' sheetsen=', Ord(DF.edSheets.Enabled));
            for k := 0 to DF.GridRowCount - 1 do
              WriteLn('GRIDROW ', k, '|', DF.GridCell(0, k), '|', DF.GridCell(1, k), '|', DF.GridCell(2, k), '|', DF.GridCell(3, k));
            for k := 0 to DF.lbRevisions.Items.Count - 1 do WriteLn('REVLIST ', k, '|', DF.lbRevisions.Items[k]);
            if Err <> '' then
              WriteLn('DETAILS refused: ', Err)
            else if ApplyAll then
            begin
              { the real button: Apply to All }
              DF.OnApplyAllRequest := @Form.DetailsApplyAllRequest;
              DF.btnApplyAll.Click;
              WriteLn('DETAILS applied all');
            end
            else
              WriteLn('DETAILS applied=', Ord(Form.ApplyDesignDetails(DF)));
          finally
            DF.Free;
          end;
          Settle;
        end
        else if Cmd = 'pagesetup' then
        begin
          { pagesetup size <width mm> <height mm> [all]   |   pagesetup paper <name> <landscape|portrait> [all]
            the dialog is filled and read back the way a person would, then applied }
          PF := TfrmPageSetup.Create(Form);
          try
            PF.LoadFromSheet(Form.View.Sheet);
            if LowerCase(T[1]) = 'paper' then
            begin
              PF.SelectPaper(T[2], LowerCase(T[3]) <> 'portrait');
              PF.cbAllSheets.Checked := (T.Count > 4) and (LowerCase(T[4]) = 'all');
            end
            else
            begin
              PF.edWidth.Text := T[2];
              PF.edHeight.Text := T[3];
              PF.SizeEdited(nil);
              PF.cbAllSheets.Checked := (T.Count > 4) and (LowerCase(T[4]) = 'all');
            end;
            if PF.lbPapers.ItemIndex >= 0 then
              S := PF.lbPapers.Items[PF.lbPapers.ItemIndex]
            else
              S := '(custom)';
            Err := PF.ValidationError;
            WriteLn('PAGESETUP w=', PF.edWidth.Text, ' h=', PF.edHeight.Text, ' orient=', PF.rgOrient.Items[PF.rgOrient.ItemIndex],
              ' paper=', S, ' units=', PF.PageWidthUnits, 'x', PF.PageHeightUnits, ' err=', Err);
            if Err = '' then
              WriteLn('PAGESETUP applied=', Ord(Form.ApplyPageSetup(PF)));
          finally
            PF.Free;
          end;
          Settle;
        end
        else if Cmd = 'dialogdetails' then
        begin
          DF := TfrmDetails.Create(Form);
          try
            DF.LoadFromSheet(Form.View.Sheet, Form.Design, Form.View.SheetIndex);
            if T.Count > 2 then
              DF.pcDetails.ActivePageIndex := StrToInt(T[2]);
            DF.Show; Settle;
            SaveForm(DF, T[1]);
            WriteLn('DIALOGDETAILS ', T[1]);
          finally
            DF.Free;
          end;
        end
        else if Cmd = 'dialogpage' then
        begin
          PF := TfrmPageSetup.Create(Form);
          try
            PF.LoadFromSheet(Form.View.Sheet);
            PF.Show; Settle;
            SaveForm(PF, T[1]);
            WriteLn('DIALOGPAGE ', T[1]);
          finally
            PF.Free;
          end;
        end
        else if Cmd = 'rotate' then
        begin
          { rotate <left|right|flip> the selection }
          if LowerCase(T[1]) = 'left' then
            Form.View.RotateSelection(2)
          else if LowerCase(T[1]) = 'right' then
            Form.View.RotateSelection(3)
          else
            Form.View.RotateSelection(4);
          Settle;
          WriteLn('ROTATE ', T[1]);
        end
        else if Cmd = 'zorder' then
        begin
          if LowerCase(T[1]) = 'front' then
            Form.View.BringToFront
          else
            Form.View.SendToBack;
          Settle;
          WriteLn('ZORDER ', T[1]);
        end
        else if Cmd = 'fpuexceptions' then
          begin
            { fpuexceptions on|off : floating point invalid operations (comparing not-a-number ...) stop the program, as they do on Windows; off masks them again }
            if LowerCase(T[1]) = 'on' then
              SetExceptionMask([exPrecision, exDenormalized, exUnderflow])
            else
              SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
            WriteLn('FPUEXCEPTIONS ', T[1]);
          end
        else if Cmd = 'copy' then
          begin
            Form.View.CopyToClipboard;
            Settle;
            WriteLn('COPY ', Form.View.SelectedCount);
          end
        else if Cmd = 'cut' then
          begin
            Form.View.CutSelection; Settle;
            WriteLn('CUT ', Form.View.Sheet.Drawing.Count);
          end
        else if Cmd = 'paste' then
          begin
            Form.View.PasteFromClipboard;
            Settle;
            WriteLn('PASTE pasting=', Ord(Form.View.Pasting), ' selected=', Form.View.SelectedCount, ' objects=', Form.View.Sheet.Drawing.Count);
          end
        else if Cmd = 'duplicate' then
          begin
            Form.View.DuplicateSelection;
            Settle;
            WriteLn('DUPLICATE pasting=', Ord(Form.View.Pasting), ' selected=', Form.View.SelectedCount);
          end
        else if Cmd = 'clipset' then
          begin
            { put the contents of a file on the clipboard as TinyCAD data (as if copied in TinyCAD) }
            FS := TFileStream.Create(T[1], fmOpenRead);
            try
              SetLength(Txt, FS.Size);
              if FS.Size > 0 then
                FS.ReadBuffer(Txt[1], FS.Size);
            finally
              FS.Free;
            end;
            Form.View.SetClipboardText(Txt);
            Settle;
            WriteLn('CLIPSET ', Length(Txt));
          end
        else if Cmd = 'clipsave' then
          begin
            Txt := Form.View.ClipboardText;
            FS := TFileStream.Create(T[1], fmCreate);
            try
              if Txt <> '' then
                FS.WriteBuffer(Txt[1], Length(Txt));
            finally
              FS.Free;
            end;
            WriteLn('CLIPSAVE ', Length(Txt));
          end
        else if Cmd = 'selidx' then
          begin
            Form.View.ClearSelection;
            for m := 1 to T.Count - 1 do
              if StrToIntDef(T[m], -1) < Form.View.Sheet.Drawing.Count then
                Form.View.SelectObject(Form.View.Sheet.Drawing[StrToInt(T[m])], True);
            Settle;
            WriteLn('SELIDX ', Form.View.SelectedCount);
          end
        else if Cmd = 'selectclass' then
          begin
            Form.View.ClearSelection;
            for k := 0 to Form.View.Sheet.Drawing.Count - 1 do
              for m := 1 to T.Count - 1 do
                if SameText(Form.View.Sheet.Drawing[k].ClassName, T[m]) then
                  Form.View.SelectObject(Form.View.Sheet.Drawing[k], True);
            Settle;
            WriteLn('SELECTCLASS ', Form.View.SelectedCount);
          end
        else if Cmd = 'addtext' then
          begin
            Form.View.BeginChange('Add text');
            Tx := TDrawText.CreateKind(Form.View.Sheet.Options, xTextEx2);
            Tx.PointA := DPoint(Num(T[1]) * UNITS_PER_MM, Num(T[2]) * UNITS_PER_MM);
            Tx.PointB := Tx.PointA;
            Tx.Str := T[3];
            if T.Count > 4 then
              Tx.Dir := StrToIntDef(T[4], 3);
            Tx.UpdateLayout;
            Tx.Id := Form.Design.NextObjectId;
            Form.View.Sheet.Drawing.Add(Tx);
            Form.View.CommitChange(True);
            Settle;
          end
        else if Cmd = 'addlabel' then
          begin
            { addlabel x y text style(0 normal,1 in,2 out,3 io) dir(0 up,1 down,2 left,3 right) }
            Form.View.BeginChange('Add label');
            Lb := TDrawLabel.Create(Form.View.Sheet.Options);
            Lb.ActivePoint := DPoint(Num(T[1]) * UNITS_PER_MM, Num(T[2]) * UNITS_PER_MM);
            Lb.Str := T[3];
            Lb.LabelStyle := StrToIntDef(T[4], 0);
            Lb.Dir := StrToIntDef(T[5], 3);
            Lb.UpdateLayout;
            Lb.Id := Form.Design.NextObjectId;
            Form.View.Sheet.Drawing.Add(Lb);
            Form.View.CommitChange(True);
            Settle;
          end
        else if Cmd = 'xrefs' then
          begin
            for k := 0 to Form.View.Sheet.Drawing.Count - 1 do
              if Form.View.Sheet.Drawing[k] is TDrawRefText then
                WriteLn('XREF "', (Form.View.Sheet.Drawing[k] as TDrawRefText).DisplayText, '" mode=', (Form.View.Sheet.Drawing[k] as TDrawRefText).Mode);
          end
        else if Cmd = 'shot' then
          begin
            Form.View.SaveSnapshot(T[1]);
            WriteLn('SHOT ', T[1]);
          end
        else if Cmd = 'formshot' then
          begin
            Settle;
            SaveForm(Form, T[1]); WriteLn('FORMSHOT ', T[1]);
          end
        else if Cmd = 'dialogparts' then
          begin
            { dialogparts <png> : a picture of the parts list dialog as it first appears }
            BomF := TfrmPartsList.Create(Form);
            try
              BomF.LoadFromSettings(Form.CurrentFileName);
              BomF.Show; Settle;
              SaveForm(BomF, T[1]);
              WriteLn('DIALOGPARTS ', T[1]);
            finally
              BomF.Free;
            end;
          end
        else if Cmd = 'dialognew' then
          begin
            F := TfrmNewDoc.Create(Form);
            try
              F.SelectPaper(T[2], (T.Count < 4) or (LowerCase(T[3]) <> 'portrait'));
              F.Show; Settle;
              SaveForm(F, T[1]);
              WriteLn('DIALOGNEW ', T[1]);
            finally
              F.Free;
            end;
          end
        else if Cmd = 'dialogladder' then
          begin
            if Lad = nil then
              raise Exception.Create('no ladder yet');
            LF := TLadderForm.CreateFor(Form, Lad);
            try
              LF.Show; Settle;
              SaveForm(LF, T[1]);
              WriteLn('DIALOGLADDER ', T[1]);
            finally
              LF.Free;
            end;
          end
        else
          WriteLn('? unknown command: ', Cmd);
      except
        on E: Exception do WriteLn('ERROR line ', i + 1, ' (', Cmd, '): ', E.ClassName, ': ', E.Message);
      end;
      Flush(Output);
    end;
  finally
    T.Free;
    Lines.Free;
  end;
end;

end.
