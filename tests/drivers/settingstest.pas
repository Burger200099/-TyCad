{ Test driver for the program settings (USettings): every call loads the settings first and saves them last, as
  separate runs of the program do, so what is checked is what really is kept in the registry.
    settingstest show                     print the recently used files
    settingstest add <file> ...           open (add to the list) the files in turn, then save
    settingstest remove <file>            take a file off the list, then save
    settingstest put <name> <value>       write one raw value in the settings key (to make a damaged state), no load / save of the list
    settingstest del <name>               delete one raw value
    settingstest opts                     print the options and the colors the user has changed
    settingstest setopts name=value ...   change options (showgrid snapgrid grid units autodrag autosnap autojunc range autosave), then save
    settingstest setcolor <id> <value>    keep color <id> (1 to 12) as the user's own (a number), then save
    settingstest clearcolor <id>          go back to the factory color <id>, then save
    settingstest key <registry key> ...   use another key for the commands that follow }
program settingstest;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cwstring,{$ENDIF}
  SysUtils, Registry, consts, UDrawTypes, UResources, USettings;

{ ===========================================================================
  Show  (procedure)
  Parameters:  none
  Notes:
    Prints the recently used files the settings hold.
  =========================================================================== }
procedure Show;
var
  i: Integer;
begin
  Write('MRU ', MRUCount);
  for i := 0 to MRU_COUNT - 1 do Write(' [', ProgramSettings.MRUFiles[i], ']');
  WriteLn;
end;

{ ===========================================================================
  ShowOptions  (procedure)
  Parameters:  none
  Notes:
    Test driver: prints the options in the settings and the colors the user has changed.
  =========================================================================== }
procedure ShowOptions;
var
  i: Integer;
  S: String;
begin
  with ProgramSettings do
    WriteLn('OPTS showgrid=', Ord(ShowGrid), ' snapgrid=', Ord(SnapGrid), ' grid=', FloatToStr(GridMm, DefaultFormatSettings), ' units=', Units, ' autodrag=', Ord(AutoDrag),
      ' autosnap=', Ord(AutoSnap), ' autojunc=', Ord(AutoJunction), ' range=', AutoSnapRange, ' autosave=', AutoSaveMinutes);
  S := '';
  for i := UC_WIRE to UC_NOTETEXT_TEXT do S := S + ' ' + IntToStr(i) + '=' + IntToStr(UserColorOverride[i]);
  WriteLn('COLORS', S);
end;

var
  i, k, p: Integer;
  R: TRegistry;
  Arg, Nm, Vl: String;
begin
  DefaultFormatSettings.DecimalSeparator := '.';
  i := 1;
  if (ParamStr(i) = 'key') then
  begin
    SettingsRegistryKey := ParamStr(i + 1);
    Inc(i, 2);
  end;
  if ParamStr(i) = 'put' then
  begin
    R := TRegistry.Create;
    try
      R.RootKey := HKEY_CURRENT_USER;
      R.OpenKey(SettingsRegistryKey, True);
      R.WriteString(ParamStr(i + 1), ParamStr(i + 2));
      R.CloseKey;
    finally
      R.Free;
    end;
    Exit;
  end;
  if ParamStr(i) = 'del' then
  begin
    R := TRegistry.Create;
    try
      R.RootKey := HKEY_CURRENT_USER;
      if R.OpenKey(SettingsRegistryKey, False) then
      begin
        R.DeleteValue(ParamStr(i + 1));
        R.CloseKey;
      end;
    finally
      R.Free;
    end;
    Exit;
  end;
  LoadSettings;
  if ParamStr(i) = 'opts' then
  begin
    ShowOptions;
    Exit;
  end;
  if ParamStr(i) = 'setopts' then
  begin
    for k := i + 1 to ParamCount do
    begin
      Arg := ParamStr(k);
      p := Pos('=', Arg);
      Nm := LowerCase(Copy(Arg, 1, p - 1));
      Vl := Copy(Arg, p + 1, MaxInt);
      with ProgramSettings do
        if Nm = 'showgrid' then ShowGrid := Vl = '1'
        else if Nm = 'snapgrid' then SnapGrid := Vl = '1'
        else if Nm = 'grid' then GridMm := StrToFloat(Vl)
        else if Nm = 'units' then Units := StrToInt(Vl)
        else if Nm = 'autodrag' then AutoDrag := Vl = '1'
        else if Nm = 'autosnap' then AutoSnap := Vl = '1'
        else if Nm = 'autojunc' then AutoJunction := Vl = '1'
        else if Nm = 'range' then AutoSnapRange := StrToInt(Vl)
        else if Nm = 'autosave' then AutoSaveMinutes := StrToInt(Vl);
    end;
    SaveSettings;
    ShowOptions;
    Exit;
  end;
  if ParamStr(i) = 'setcolor' then
  begin
    UserColorOverride[StrToInt(ParamStr(i + 1))] := StrToInt64(ParamStr(i + 2));
    SaveSettings;
    ShowOptions;
    Exit;
  end;
  if ParamStr(i) = 'clearcolor' then
  begin
    UserColorOverride[StrToInt(ParamStr(i + 1))] := -1;
    SaveSettings;
    ShowOptions;
    Exit;
  end;
  if ParamStr(i) = 'add' then
  begin
    Inc(i);
    while i <= ParamCount do
    begin
      MRUAdd(ParamStr(i));
      Inc(i);
    end;
    SaveSettings;
  end
  else if ParamStr(i) = 'remove' then
  begin
    MRURemove(ParamStr(i + 1));
    SaveSettings;
  end;
  Show;
end.
