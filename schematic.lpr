// SPDX-License-Identifier: LGPL-2.1-or-later
program schematic;

{$mode objfpc}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, SysUtils, MainForm, UScript, consts, Fnewdoc, Fbase, Fabout, QLibPanel,
  QPropBase, QPropWire, FPropTester, QPropText, QPowerSym, QRectCircle,
  QPropNote, QCloudNote, QMeasure, FSharedCtls, FFillDropDown, QPolygon, QArc,
  QBus, FDetailsDropDown, qsymbols, QLadder, QRungs, FSymDDD, UTextMetrics, QPin, LCLTranslator;

type
  { in script mode an unhandled exception is printed and ends the run instead of opening a dialog
    that nothing can click }
  TScriptCatcher = class
    procedure Handle(Sender: TObject; E: Exception);
  end;

{ ===========================================================================
  TScriptCatcher.Handle  (procedure)
  Parameters:
    Sender: TObject - where it was raised
    E: Exception - the exception
  Notes:
    In script mode: prints an unhandled exception and its backtrace to the error output and ends
    the program, instead of showing a dialog nothing can click.
  =========================================================================== }
procedure TScriptCatcher.Handle(Sender: TObject; E: Exception);
begin
  WriteLn(StdErr, 'Unhandled exception: ', E.ClassName, ': ', E.Message);
  DumpExceptionBackTrace(StdErr);
  Halt(4);
end;

{ ===========================================================================
  SetupLanguage  (procedure)
  Parameters:
    AScript: Boolean - running a script (a test)
  Notes:
    Chooses the language of the texts: the one named by --lang xx (or --lang=xx), else by the environment variable TYCAD_LANG, else the language of the system.
    The translation is languages/schematic.<lang>.po next to the program (or in the project's languages folder) (LCLTranslator also looks in a folder named for the language, and in locale/); with none
    for the language the texts stay English. A script (a test) is always English unless a language is named, so that a test does not depend on the machine.
    Called before any window is made, so that the captions and hints of the forms are translated as they are read.
  =========================================================================== }
procedure SetupLanguage(AScript: Boolean);
var
  Lang, Dir, AppDir: String;
  k: Integer;
  Named: Boolean;
begin
  Lang := GetEnvironmentVariable('TYCAD_LANG');
  Named := Lang <> '';
  for k := 1 to ParamCount do
    if (ParamStr(k) = '--lang') or (ParamStr(k) = '-l') or (Copy(ParamStr(k), 1, 7) = '--lang=') then
      Named := True;
  if AScript and not Named then
    Exit;
  { the .po files are in a folder 'languages' next to the program; when it is not there, the one of the project (the program is in its bin folder) is used }
  AppDir := ExtractFilePath(ParamStr(0));
  Dir := 'languages';
  if (not DirectoryExists(AppDir + 'languages')) and DirectoryExists(AppDir + '..' + PathDelim + 'languages') then
    Dir := '..' + PathDelim + 'languages';
  SetDefaultLang(Lang, Dir, 'schematic', False);
end;

var
  AppForm: TfrmMain;
  Catcher: TScriptCatcher;
  i: Integer;
  ScriptFile, OpenFile: String;

{$R *.res}

begin
  ScriptFile := '';
  OpenFile := '';
  for i := 1 to ParamCount do
  begin
    if (ParamStr(i) = '--script') and (i < ParamCount) then
      ScriptFile := ParamStr(i + 1);
    if (ParamStr(i) = '--open') and (i < ParamCount) then
      OpenFile := ParamStr(i + 1);
  end;
  { the program measures text with the real fonts (a text's box is as wide as the text); scripts keep the table of Arial widths so that sizes do not depend on the machine's fonts }
  UseRealTextMetrics(ScriptFile = '');
  SetupLanguage(ScriptFile <> '');
  Application.Scaled:=True;
  Application.Title := lAppName;
  Application.Initialize;
  if ScriptFile <> '' then
  begin
    Catcher := TScriptCatcher.Create;
    Application.OnException := @Catcher.Handle;
  end;
  try
    frmSharedControls := TfrmSharedControls.Create(Application);      // first: the dialogs and image lists every form uses (not by CreateForm: the first form made that way is the main form)
    Application.CreateForm(TfrmMain, AppForm);
  except
    on E: Exception do
    begin
      { show the real reason on the console instead of waiting on an error dialog }
      WriteLn(StdErr, 'Startup error: ', E.ClassName, ': ', E.Message);
      DumpExceptionBackTrace(StdErr);
      Halt(3);
    end;
  end;
  if ScriptFile = '' then
    AppForm.RestoreLibraries;                   // the symbol libraries in use last time
  if ScriptFile = '' then
    AppForm.RestoreSession;                     // the designs that were open last time, if Options says so
  if OpenFile <> '' then
    AppForm.OpenDesignFile(OpenFile);
  if ScriptFile <> '' then
  begin
    RunScript(AppForm, ScriptFile);
    Halt(0);
  end;
  Application.Run;
end.
