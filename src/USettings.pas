// SPDX-License-Identifier: LGPL-2.1-or-later
{ Loading and saving the program's settings (the record ProgramSettings in consts.pas) with TRegistry, under
  HKEY_CURRENT_USER\REG_HPLSOFT_KEY (Software\HPL Software\TyCAD Electrical), each field as a value of its own.
  On systems without a registry the FPC Registry unit keeps the same keys and values in a file in the user's
  configuration folder. The recently used files are the first setting: the last MRU_COUNT (4) files that were opened
  or saved, newest first.

  A failure to read or write the registry is never an error for the program: it simply starts with the defaults
  or carries on without saving.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit USettings;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Registry, consts, UDrawTypes, UResources, UPrint;

var
  { where the settings live; a test can point it somewhere else }
  SettingsRegistryKey: String = REG_HPLSOFT_KEY;

procedure SetDefaultSettings;
procedure LoadSettings;
procedure SaveSettings;
{ ---- the recently used files ---- }
function FitSavedWindow(const Saved: TRect; const Works: array of TRect; MinW, MinH: Integer; out Fit: TRect): Boolean;
procedure MRUAdd(const FileName: String);
procedure MRURemove(const FileName: String);
function MRUCount: Integer;
function MRUFile(Index: Integer): String;

implementation

var
  DotSettings: TFormatSettings;

{ ===========================================================================
  SetDefaultSettings  (procedure)
  Parameters:  none
  Notes:
    Puts every setting at its default: no recently used files.
  =========================================================================== }
procedure SetDefaultSettings;
var
  i: Integer;
begin
  for i := 0 to MRU_COUNT - 1 do ProgramSettings.MRUFiles[i] := '';
  for i := 0 to SESSION_MAX - 1 do ProgramSettings.SessionFiles[i] := '';
  for i := 0 to LIBRARY_MAX - 1 do ProgramSettings.LibraryFiles[i] := '';
  with ProgramSettings do
  begin
    SymbolFontName := DEFAULT_FONT;        // the pin font TinyCAD starts with: 10 design units high, upright
    SymbolFontPoints := 8;
    SymbolFontBold := False;
    SymbolFontItalic := False;
    NewSheetBorder := True;                // a new sheet has a border 6.35 mm (a quarter inch) from the edge, no rulers, seven columns and five rows (what New Document always gave)
    NewSheetRulers := False;
    NewSheetCols := 7;
    NewSheetRows := 5;
    NewSheetMarginMm := 6.35;
    ReopenDesigns := False;                // the designs are not opened again unless that is asked for in Options
    SessionActive := 0;
    BomType := 0;
    BomHierarchical := False;
    BomPrefix := False;
    BomAllSheets := False;
    BomAllAttrs := False;
    NetType := 0;
    NetPrefix := False;
    PartCheck := True;
    PartCheckUnresolved := 1;
    PartCheckOversized := True;
    ErcWord := $FFFF;                      // every check is on to begin with
    AnnotateType := 1;                     // un-numbered references
    AnnotateAllSheets := True;
    PrintScale := PRINT_DEFAULT_SCALE;
    PrintBandW := False;
    PrintNoSymText := False;
    PrintNoSymFields := False;
    DarkMode := False;
    NewDocPaper := 'ISO A4';
    NewDocLandscape := True;
    WinWidth := 0; WinHeight := 0; WinLeft := 0; WinTop := 0; WinMaximized := False;      // nothing kept: the window starts as designed
    SplitLeftWidth := 0; SplitPreviewHeight := 0;
    ExportType := 0;
    ExportScale := 100;
    ExportRotate := False;
    ShowGrid := True;
    SnapGrid := True;
    GridMm := 2.0;
    Units := 0;
    AutoDrag := True;
    AutoSnap := True;
    AutoJunction := True;
    AutoSnapRange := 15;
    AutoSaveMinutes := 10;                 // TinyCAD saves a copy every ten minutes unless it is turned off
    ShowPosition := True;                  // the Position bar is shown to begin with
    LastPartsFile := '';
    PartsWarningOff := False;              // the warning about parts is shown until the person turns it off
    RulerUnits := -1;                      // the rulers use the sheet's units until the person chooses
    ShowViewRulers := True;                // so are the rulers round the drawing area (TinyCAD shows them)
  end;
  for i := UC_WIRE to UC_NOTETEXT_TEXT do UserColorOverride[i] := -1;
end;

{ ===========================================================================
  FitSavedWindow  (function)
  Parameters:
    const Saved: TRect
    const Works: array of TRect
    MinW: Integer - whole number
    MinH: Integer - whole number
    out Fit: TRect - out: set by the call
  Returns:
    Boolean
  Notes:
    The size is raised to MinW x MinH and cut down to the work area the window is mostly on. The
    window can go where it was when the top strip of it (the title bar, 30 pixels high) overlaps
    a work area by 100 pixels or more, so a monitor that has been unplugged does not leave the
    window out of reach. When it cannot, Fit is at 0, 0 with that size.
  =========================================================================== }
function FitSavedWindow(const Saved: TRect; const Works: array of TRect; MinW, MinH: Integer; out Fit: TRect): Boolean;
var
  i, W, H, Best, BestArea, A: Integer;
  Strip, Isect: TRect;
begin
  W := Saved.Right - Saved.Left;
  H := Saved.Bottom - Saved.Top;
  if W < MinW then
    W := MinW;
  if H < MinH then
    H := MinH;
  Fit := Rect(0, 0, W, H);
  Result := False;
  Best := -1;
  BestArea := 0;
  Strip := Rect(Saved.Left, Saved.Top, Saved.Left + W, Saved.Top + 30);
  for i := 0 to High(Works) do
    if IntersectRect(Isect, Strip, Works[i]) and (Isect.Right - Isect.Left >= 100) then
    begin
      A := (Isect.Right - Isect.Left) * (Isect.Bottom - Isect.Top);
      if A > BestArea then
      begin
        BestArea := A;
        Best := i;
      end;
    end;
  if Best < 0 then
    Exit;
  if W > Works[Best].Right - Works[Best].Left then
    W := Works[Best].Right - Works[Best].Left;
  if H > Works[Best].Bottom - Works[Best].Top then
    H := Works[Best].Bottom - Works[Best].Top;
  Fit := Rect(Saved.Left, Saved.Top, Saved.Left + W, Saved.Top + H);
  Result := True;
end;

{ ===========================================================================
  ReadIntSafe  (function)
  Parameters:
    R: TRegistry - the XML reader, positioned on this element
    const Name: String - the name
    Default: Integer - whole number
  Returns:
    Integer
  Notes:
    Reads a number whether it was stored as a number or as text, and never fails: a value that
    is the wrong kind of thing, or text that is not a number, gives the default, so one damaged
    value cannot take the others with it.
  =========================================================================== }
function ReadIntSafe(R: TRegistry; const Name: String; Default: Integer): Integer;
begin
  Result := Default;
  try
    if not R.ValueExists(Name) then
      Exit;
    case R.GetDataType(Name) of
      rdInteger: Result := R.ReadInteger(Name);
      rdString, rdExpandString: Result := StrToIntDef(Trim(R.ReadString(Name)), Default);
    end;
  except
    Result := Default;
  end;
end;

{ ===========================================================================
  ReadBoolSafe  (function)
  Parameters:
    R: TRegistry - the open registry key
    const Name: String - the value's name
    Default: Boolean - what to give if it is not there
  Returns:
    Boolean - the value
  Notes:
    Reads a yes/no value from the registry; the default if it is missing or cannot be read.
  =========================================================================== }
function ReadBoolSafe(R: TRegistry; const Name: String; Default: Boolean): Boolean;
begin
  Result := ReadIntSafe(R, Name, Ord(Default)) <> 0;
end;

{ ===========================================================================
  ReadTextSafe  (function)
  Parameters:
    R: TRegistry - the open registry key
    const Name: String - the value's name
    const Default: String - what to give if it is not there
  Returns:
    String - the text
  Notes:
    Reads a text value from the registry; the default if it is missing or cannot be read.
  =========================================================================== }
function ReadTextSafe(R: TRegistry; const Name: String; const Default: String): String;
begin
  Result := Default;
  try
    if R.ValueExists(Name) then
      Result := R.ReadString(Name);
  except
    Result := Default;
  end;
end;

{ ===========================================================================
  LoadSettings  (procedure)
  Parameters:  none
  Notes:
    Reads the settings from the registry into ProgramSettings, starting from the defaults, so a
    value that is missing (the first run, or a new setting) keeps its default. The recently used
    files are read from MRU1 to MRU4 and packed to the front if any entry was empty. Any
    registry error leaves the defaults.
  =========================================================================== }
procedure LoadSettings;
var
  R: TRegistry;
  i, n: Integer;
  S: String;
begin
  SetDefaultSettings;
  try
    R := TRegistry.Create;
    try
      R.RootKey := HKEY_CURRENT_USER;
      if R.OpenKeyReadOnly(SettingsRegistryKey) then
      begin
        n := 0;
        for i := 1 to MRU_COUNT do
          if R.ValueExists(REG_MRU + IntToStr(i)) then
          begin
            S := ReadTextSafe(R, REG_MRU + IntToStr(i), '');
            if S <> '' then
            begin
              ProgramSettings.MRUFiles[n] := S;
              Inc(n);
            end;
          end;
        { the designs that were open: Session1 ... in order, packed to the front, and which of them was showing }
        n := 0;
        for i := 1 to SESSION_MAX do
          if R.ValueExists(REG_SESSION + IntToStr(i)) then
          begin
            S := ReadTextSafe(R, REG_SESSION + IntToStr(i), '');
            if S <> '' then
            begin
              ProgramSettings.SessionFiles[n] := S;
              Inc(n);
            end;
          end;
        { the symbol libraries in use: Library1 ... in order, packed to the front }
        n := 0;
        for i := 1 to LIBRARY_MAX do
          if R.ValueExists(REG_LIBRARY + IntToStr(i)) then
          begin
            S := ReadTextSafe(R, REG_LIBRARY + IntToStr(i), '');
            if S <> '' then
            begin
              ProgramSettings.LibraryFiles[n] := S;
              Inc(n);
            end;
          end;
        { the options: a value that is missing keeps its default }
        with ProgramSettings do
        begin
          ShowGrid := ReadBoolSafe(R, REG_SHOWGRID, ShowGrid);
          SnapGrid := ReadBoolSafe(R, REG_SNAPGRID, SnapGrid);
          GridMm := StrToFloatDef(Trim(ReadTextSafe(R, REG_GRID, '')), GridMm, DotSettings);
          Units := ReadIntSafe(R, REG_UNITS, Units);
          AutoDrag := ReadBoolSafe(R, REG_AUTODRAG, AutoDrag);
          AutoSnap := ReadBoolSafe(R, REG_AUTOSNAP, AutoSnap);
          AutoJunction := ReadBoolSafe(R, REG_AUTOJUNC, AutoJunction);
          AutoSnapRange := ReadIntSafe(R, REG_AUTOSNAPRANGE, AutoSnapRange);
          AutoSaveMinutes := ReadIntSafe(R, REG_AUTOSAVE, AutoSaveMinutes);
          ShowPosition := ReadBoolSafe(R, REG_SHOWPOSITION, ShowPosition);
          LastPartsFile := ReadTextSafe(R, REG_PARTSFILE, LastPartsFile);
          PartsWarningOff := ReadBoolSafe(R, REG_PARTSWARNING, PartsWarningOff);
          RulerUnits := ReadIntSafe(R, REG_RULERUNITS, RulerUnits);
          if (RulerUnits < -1) or (RulerUnits > 1) then
            RulerUnits := -1;
          ShowViewRulers := ReadBoolSafe(R, REG_SHOWVIEWRULERS, ShowViewRulers);
          ReopenDesigns := ReadBoolSafe(R, REG_REOPEN, ReopenDesigns);
          SymbolFontName := ReadTextSafe(R, REG_SYMFONTNAME, SymbolFontName);
          SymbolFontPoints := ReadIntSafe(R, REG_SYMFONTPOINTS, SymbolFontPoints);
          SymbolFontBold := ReadBoolSafe(R, REG_SYMFONTBOLD, SymbolFontBold);
          SymbolFontItalic := ReadBoolSafe(R, REG_SYMFONTITALIC, SymbolFontItalic);
          NewSheetBorder := ReadBoolSafe(R, REG_NEWSHEETBORDER, NewSheetBorder);
          NewSheetRulers := ReadBoolSafe(R, REG_NEWSHEETRULERS, NewSheetRulers);
          NewSheetCols := ReadIntSafe(R, REG_NEWSHEETCOLS, NewSheetCols);
          NewSheetRows := ReadIntSafe(R, REG_NEWSHEETROWS, NewSheetRows);
          NewSheetMarginMm := StrToFloatDef(Trim(ReadTextSafe(R, REG_NEWSHEETMARGIN, '')), NewSheetMarginMm, DotSettings);
          SessionActive := ReadIntSafe(R, REG_SESSIONACTIVE, SessionActive);
          BomType := ReadIntSafe(R, REG_BOMTYPE, BomType);
          BomHierarchical := ReadBoolSafe(R, REG_BOMHIER, BomHierarchical);
          BomPrefix := ReadBoolSafe(R, REG_BOMPREFIX, BomPrefix);
          BomAllSheets := ReadBoolSafe(R, REG_BOMSHEETS, BomAllSheets);
          BomAllAttrs := ReadBoolSafe(R, REG_BOMATTRS, BomAllAttrs);
          NetType := ReadIntSafe(R, REG_NETTYPE, NetType);
          NetPrefix := ReadBoolSafe(R, REG_NETPREFIX, NetPrefix);
          PartCheck := ReadBoolSafe(R, REG_PARTCHECK, PartCheck);
          PartCheckUnresolved := ReadIntSafe(R, REG_PARTCHECKUNRES, PartCheckUnresolved);
          if (PartCheckUnresolved < 0) or (PartCheckUnresolved > 2) then
            PartCheckUnresolved := 1;
          PartCheckOversized := ReadBoolSafe(R, REG_PARTCHECKOVER, PartCheckOversized);
          ErcWord := ReadIntSafe(R, REG_ERC, ErcWord) and $FFFF;      // (WORD) of the value, as TinyCAD reads it
          AnnotateType := ReadIntSafe(R, REG_ANNOTATE_TYPE, AnnotateType);
          AnnotateAllSheets := ReadBoolSafe(R, REG_ANNOTATE_SHEETS, AnnotateAllSheets);
          if (AnnotateType < 0) or (AnnotateType > 2) then
            AnnotateType := 1;
          PrintBandW := ReadBoolSafe(R, REG_PRINT_BANDW, PrintBandW);
          PrintNoSymText := ReadBoolSafe(R, REG_PRINT_NOSYMTEXT, PrintNoSymText);
          PrintNoSymFields := ReadBoolSafe(R, REG_PRINT_NOSYMFIELDS, PrintNoSymFields);
          DarkMode := ReadBoolSafe(R, REG_DARK_MODE, DarkMode);
          NewDocPaper := Trim(ReadTextSafe(R, REG_NEWDOC_PAPER, NewDocPaper));
          if NewDocPaper = '' then
            NewDocPaper := 'ISO A4';
          NewDocLandscape := ReadBoolSafe(R, REG_NEWDOC_LANDSCAPE, NewDocLandscape);
          WinLeft := ReadIntSafe(R, REG_WIN_LEFT, WinLeft);
          WinTop := ReadIntSafe(R, REG_WIN_TOP, WinTop);
          WinWidth := ReadIntSafe(R, REG_WIN_WIDTH, WinWidth);
          WinHeight := ReadIntSafe(R, REG_WIN_HEIGHT, WinHeight);
          WinMaximized := ReadBoolSafe(R, REG_WIN_MAXIMIZED, WinMaximized);
          SplitLeftWidth := ReadIntSafe(R, REG_SPLIT_LEFT, SplitLeftWidth);
          SplitPreviewHeight := ReadIntSafe(R, REG_SPLIT_PREVIEW, SplitPreviewHeight);
          ExportType := ReadIntSafe(R, REG_BITMAP_TYPE, ExportType);
          ExportScale := ReadIntSafe(R, REG_BITMAP_SCALING, ExportScale);
          ExportRotate := ReadBoolSafe(R, REG_BITMAP_ROTATION, ExportRotate);
          if (ExportType < 0) or (ExportType > 3) then
            ExportType := 0;
          if (ExportScale < 1) or (ExportScale > 1000) then
            ExportScale := 100;
          { the scale is kept as text, as TinyCAD's GetDouble reads it (atof); a missing value, or one that is no use, is the default }
          if R.ValueExists(REG_PRINT_SCALE) then
          begin
            try
              PrintScale := PrintScaleValue(R.ReadString(REG_PRINT_SCALE));
            except
              PrintScale := PRINT_DEFAULT_SCALE;
            end;
          end;
          if (PrintScale <= 0) or (PrintScale > PRINT_MAX_SCALE) then
            PrintScale := PRINT_DEFAULT_SCALE;     // (a scale of 0 would fail printing)
          if (BomType < 0) or (BomType > 2) then
            BomType := 0;
          if (NetType < 0) or (NetType > 6) then
            NetType := 0;
          { what could not be right is put right: a grid has a size, the units are one of the two, the interval is 0 or 1 to 60 minutes }
          if GridMm <= 0 then
            GridMm := 2.0;
          if (Units < 0) or (Units > 1) then
            Units := 0;
          if AutoSnapRange < 1 then
            AutoSnapRange := 15;
          if (NewSheetCols < 1) or (NewSheetCols > 26) then
            NewSheetCols := 7;
          if (NewSheetRows < 1) or (NewSheetRows > 26) then
            NewSheetRows := 5;
          if (NewSheetMarginMm < 0) or (NewSheetMarginMm > 100) then
            NewSheetMarginMm := 6.35;
          if AutoSaveMinutes < 0 then
            AutoSaveMinutes := 0;
          if AutoSaveMinutes > 60 then
            AutoSaveMinutes := 60;
        end;
        { the colors the user has changed (only those are kept, as TinyCAD does) }
        for i := UC_WIRE to UC_NOTETEXT_TEXT do
          if R.ValueExists(TUserColors.TagNameOf(i)) then
            UserColorOverride[i] := Int64(Cardinal(ReadIntSafe(R, TUserColors.TagNameOf(i), 0)) and $FFFFFF);
        R.CloseKey;
      end;
    finally
      R.Free;
    end;
  except
    SetDefaultSettings;
  end;
end;

{ ===========================================================================
  SaveSettings  (procedure)
  Parameters:  none
  Notes:
    Writes every field of ProgramSettings to the registry, creating the key if it is not there:
    the recently used files as MRU1 to MRU4 (a value is deleted when its entry is empty). A
    registry error is ignored.
  =========================================================================== }
procedure SaveSettings;
var
  R: TRegistry;
  i, n: Integer;
  Name: String;
begin
  try
    R := TRegistry.Create;
    try
      R.RootKey := HKEY_CURRENT_USER;
      if R.OpenKey(SettingsRegistryKey, True) then
      begin
        for i := 0 to MRU_COUNT - 1 do
        begin
          Name := REG_MRU + IntToStr(i + 1);
          if ProgramSettings.MRUFiles[i] <> '' then
            R.WriteString(Name, ProgramSettings.MRUFiles[i])
          else if R.ValueExists(Name) then
            R.DeleteValue(Name);
        end;
        with ProgramSettings do
        begin
          R.WriteBool(REG_SHOWGRID, ShowGrid);
          R.WriteBool(REG_SNAPGRID, SnapGrid);
          R.WriteString(REG_GRID, FloatToStr(GridMm, DotSettings));
          R.WriteInteger(REG_UNITS, Units);
          R.WriteBool(REG_AUTODRAG, AutoDrag);
          R.WriteBool(REG_AUTOSNAP, AutoSnap);
          R.WriteBool(REG_AUTOJUNC, AutoJunction);
          R.WriteInteger(REG_AUTOSNAPRANGE, AutoSnapRange);
          R.WriteInteger(REG_AUTOSAVE, AutoSaveMinutes);
          R.WriteBool(REG_SHOWPOSITION, ShowPosition);
          R.WriteString(REG_PARTSFILE, LastPartsFile);
          R.WriteBool(REG_PARTSWARNING, PartsWarningOff);
          R.WriteInteger(REG_RULERUNITS, RulerUnits);
          R.WriteBool(REG_SHOWVIEWRULERS, ShowViewRulers);
          R.WriteBool(REG_REOPEN, ReopenDesigns);
          R.WriteString(REG_SYMFONTNAME, SymbolFontName);
          R.WriteInteger(REG_SYMFONTPOINTS, SymbolFontPoints);
          R.WriteBool(REG_SYMFONTBOLD, SymbolFontBold);
          R.WriteBool(REG_SYMFONTITALIC, SymbolFontItalic);
          R.WriteBool(REG_NEWSHEETBORDER, NewSheetBorder);
          R.WriteBool(REG_NEWSHEETRULERS, NewSheetRulers);
          R.WriteInteger(REG_NEWSHEETCOLS, NewSheetCols);
          R.WriteInteger(REG_NEWSHEETROWS, NewSheetRows);
          R.WriteString(REG_NEWSHEETMARGIN, FloatToStr(NewSheetMarginMm, DotSettings));
          R.WriteInteger(REG_BOMTYPE, BomType);
          R.WriteBool(REG_BOMHIER, BomHierarchical);
          R.WriteBool(REG_BOMPREFIX, BomPrefix);
          R.WriteBool(REG_BOMSHEETS, BomAllSheets);
          R.WriteBool(REG_BOMATTRS, BomAllAttrs);
          R.WriteInteger(REG_NETTYPE, NetType);
          R.WriteBool(REG_NETPREFIX, NetPrefix);
          R.WriteBool(REG_PARTCHECK, PartCheck);
          R.WriteInteger(REG_PARTCHECKUNRES, PartCheckUnresolved);
          R.WriteBool(REG_PARTCHECKOVER, PartCheckOversized);
          R.WriteInteger(REG_ERC, ErcWord);
          R.WriteInteger(REG_ANNOTATE_TYPE, AnnotateType);
          R.WriteBool(REG_ANNOTATE_SHEETS, AnnotateAllSheets);
          R.WriteBool(REG_PRINT_BANDW, PrintBandW);
          R.WriteBool(REG_PRINT_NOSYMTEXT, PrintNoSymText);
          R.WriteBool(REG_PRINT_NOSYMFIELDS, PrintNoSymFields);
          R.WriteBool(REG_DARK_MODE, DarkMode);
          R.WriteString(REG_NEWDOC_PAPER, NewDocPaper);
          R.WriteBool(REG_NEWDOC_LANDSCAPE, NewDocLandscape);
          R.WriteInteger(REG_WIN_LEFT, WinLeft);
          R.WriteInteger(REG_WIN_TOP, WinTop);
          R.WriteInteger(REG_WIN_WIDTH, WinWidth);
          R.WriteInteger(REG_WIN_HEIGHT, WinHeight);
          R.WriteBool(REG_WIN_MAXIMIZED, WinMaximized);
          R.WriteInteger(REG_SPLIT_LEFT, SplitLeftWidth);
          R.WriteInteger(REG_SPLIT_PREVIEW, SplitPreviewHeight);
          R.WriteInteger(REG_BITMAP_TYPE, ExportType);
          R.WriteInteger(REG_BITMAP_SCALING, ExportScale);
          R.WriteBool(REG_BITMAP_ROTATION, ExportRotate);
          R.WriteString(REG_PRINT_SCALE, FormatCG(PrintScale, 6, 0));      // (printf "%lg")
        end;
        { the designs that were open: written packed to the front, and the values of the slots no longer used taken away }
        n := 0;
        for i := 0 to SESSION_MAX - 1 do
          if ProgramSettings.SessionFiles[i] <> '' then
          begin
            Inc(n);
            R.WriteString(REG_SESSION + IntToStr(n), ProgramSettings.SessionFiles[i]);
          end;
        for i := n + 1 to SESSION_MAX do
          if R.ValueExists(REG_SESSION + IntToStr(i)) then
            R.DeleteValue(REG_SESSION + IntToStr(i));
        if (n > 0) and (ProgramSettings.SessionActive > 0) then
          R.WriteInteger(REG_SESSIONACTIVE, ProgramSettings.SessionActive)
        else if R.ValueExists(REG_SESSIONACTIVE) then
          R.DeleteValue(REG_SESSIONACTIVE);
        { the symbol libraries in use, packed to the front, the values of the slots no longer used taken away }
        n := 0;
        for i := 0 to LIBRARY_MAX - 1 do
          if ProgramSettings.LibraryFiles[i] <> '' then
          begin
            Inc(n);
            R.WriteString(REG_LIBRARY + IntToStr(n), ProgramSettings.LibraryFiles[i]);
          end;
        for i := n + 1 to LIBRARY_MAX do
          if R.ValueExists(REG_LIBRARY + IntToStr(i)) then
            R.DeleteValue(REG_LIBRARY + IntToStr(i));
        for i := UC_WIRE to UC_NOTETEXT_TEXT do
        begin
          Name := TUserColors.TagNameOf(i);
          if UserColorOverride[i] >= 0 then
            R.WriteInteger(Name, Integer(UserColorOverride[i]))
          else if R.ValueExists(Name) then
            R.DeleteValue(Name);
        end;
        R.CloseKey;
      end;
    finally
      R.Free;
    end;
  except
    { not being able to save the settings is not worth stopping the program for }
  end;
end;

{ ===========================================================================
  MRUCount  (function)
  Parameters:  none
  Returns:
    Integer - a number from 0 to MRU_COUNT (4)
  Notes:
    How many recently used files there are.
  =========================================================================== }
function MRUCount: Integer;
begin
  Result := 0;
  while (Result < MRU_COUNT) and (ProgramSettings.MRUFiles[Result] <> '') do Inc(Result);
end;

{ ===========================================================================
  MRUFile  (function)
  Parameters:
    Index: Integer - position in the list, 0 for the newest
  Returns:
    String - its full name, or empty if there is none at that place
  Notes:
    One of the recently used files.
  =========================================================================== }
function MRUFile(Index: Integer): String;
begin
  if (Index >= 0) and (Index < MRU_COUNT) then
    Result := ProgramSettings.MRUFiles[Index]
  else
    Result := '';
end;

{ ===========================================================================
  MRURemove  (procedure)
  Parameters:
    const FileName: String - path of the file
  Notes:
    Takes a file out of the recently used list (names are compared as the system compares file
    names) and closes the gap. Does nothing if it is not there.
  =========================================================================== }
procedure MRURemove(const FileName: String);
var
  i, n: Integer;
  Keep: array[0..MRU_COUNT - 1] of String;
begin
  n := 0;
  for i := 0 to MRU_COUNT - 1 do
    if (ProgramSettings.MRUFiles[i] <> '') and (not SameFileName(ProgramSettings.MRUFiles[i], ExpandFileName(FileName))) then
    begin
      Keep[n] := ProgramSettings.MRUFiles[i];
      Inc(n);
    end;
  for i := 0 to MRU_COUNT - 1 do
    if i < n then
      ProgramSettings.MRUFiles[i] := Keep[i]
    else
      ProgramSettings.MRUFiles[i] := '';
end;

{ ===========================================================================
  MRUAdd  (procedure)
  Parameters:
    const FileName: String - path of the file
  Notes:
    Puts a file at the top of the recently used list. If it was in the list it moves up instead
    of being listed twice; the oldest file drops off the end when the list is full. A file
    without a name is ignored.
  =========================================================================== }
procedure MRUAdd(const FileName: String);
var
  i: Integer;
  Full: String;
begin
  if Trim(FileName) = '' then
    Exit;
  Full := ExpandFileName(FileName);
  MRURemove(Full);
  for i := MRU_COUNT - 1 downto 1 do ProgramSettings.MRUFiles[i] := ProgramSettings.MRUFiles[i - 1];
  ProgramSettings.MRUFiles[0] := Full;
end;

initialization
  DotSettings := DefaultFormatSettings;
  DotSettings.DecimalSeparator := '.';

end.
