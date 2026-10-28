{ The Library Setup dialog (TinyCAD's CDlgLibraryBox, Library > Libraries...): the libraries in use, sorted by name, with Add (several .TCLib files at once), Remove,
  New (an empty library file), Cleanup (compacts the file) and OK. Add, Remove and New act at once on the library panel, as in TinyCAD, where OK only closes the
  window (the list is kept by the main form each time the panel changes). Remove and Cleanup are refused with TinyCAD's messages while a library is in use (being
  edited); the owner says which are (OnInUse). Edit (the symbol editor) and Upgrade (the old .mdb and .idx formats) are in the window and dimmed: they are not ported.
  Problems are reported through OnProblem so the owner decides how they are shown.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Flibraries;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, QLibPanel, ULibrary, ULibManager;

type
  TLibraryInUseEvent = function(const FileName: String): Boolean of object;
  TLibraryProblemEvent = procedure(const Msg: String) of object;

  { TfrmLibraries }

  TfrmLibraries = class(TfrmBase)
    btnAdd: TButton;
    btnCleanup: TButton;
    btnEdit: TButton;
    btnNew: TButton;
    btnRemove: TButton;
    btnUpgrade: TButton;
    lbLibs: TListBox;
    lblLibs: TLabel;
    procedure AddClick(Sender: TObject);
    procedure CleanupClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ListSelect(Sender: TObject; User: Boolean);
    procedure NewClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
  private
    FPanel: TfrLibraryPanel;
    FOnInUse: TLibraryInUseEvent;
    FOnProblem: TLibraryProblemEvent;
    procedure LibrariesActivate(Sender: TObject);
    procedure Problem(const Msg: String);
    function SelectedIndex: Integer;
  public
    { the panel whose libraries the dialog edits; the list is filled from it }
    procedure Attach(APanel: TfrLibraryPanel);
    procedure RefreshList;
    procedure UpdateButtons;
    { what the buttons do, with the files given (the buttons ask for them with the file dialogs) }
    procedure AddFiles(Files: TStrings);
    function NewLibrary(const Chosen: String): Boolean;
    procedure RemoveSelected;
    procedure CleanupSelected;
    { choose a library in the list by name (the first of that name); False when there is none }
    function SelectByName(const AName: String): Boolean;
    function ItemCount: Integer;
    function ItemText(Index: Integer): String;
    { the file of the library selected in the list, '' for none }
    function SelectedFile: String;
    property OnInUse: TLibraryInUseEvent read FOnInUse write FOnInUse;
    property OnProblem: TLibraryProblemEvent read FOnProblem write FOnProblem;
  end;

var
  frmLibraries: TfrmLibraries;

implementation

uses UStrings, FSharedCtls;

{$R *.lfm}

{ ===========================================================================
  TfrmLibraries.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The window only has OK (TinyCAD's has no Cancel: its changes are made as they are asked
    for), and Edit and Upgrade are dimmed with the reason in their hints.
  =========================================================================== }
procedure TfrmLibraries.FormCreate(Sender: TObject);
begin
  OnActivate := @LibrariesActivate;
  SetButtons([fcbOK]);
  btnEdit.Enabled := False;
  btnUpgrade.Enabled := False;
  UpdateButtons;
end;

{ ===========================================================================
  TfrmLibraries.LibrariesActivate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Shows OK alone (the base form's handler would show OK and Cancel).
  =========================================================================== }
procedure TfrmLibraries.LibrariesActivate(Sender: TObject);
begin
  SetButtons([fcbOK]);
end;

{ ===========================================================================
  TfrmLibraries.Problem  (procedure)
  Parameters:
    const Msg: String - the message
  Notes:
    Passes a problem to the owner, or shows it when there is no owner handler.
  =========================================================================== }
procedure TfrmLibraries.Problem(const Msg: String);
begin
  if Assigned(FOnProblem) then
    FOnProblem(Msg)
  else
    MessageDlg(Caption, Msg, mtWarning, [mbOK], 0);
end;

{ ===========================================================================
  TfrmLibraries.Attach  (procedure)
  Parameters:
    APanel: TfrLibraryPanel - the library panel
  Notes:
    Takes the panel whose libraries are edited and lists them.
  =========================================================================== }
procedure TfrmLibraries.Attach(APanel: TfrLibraryPanel);
begin
  FPanel := APanel;
  RefreshList;
end;

{ ===========================================================================
  TfrmLibraries.RefreshList  (procedure)
  Parameters:  none
  Notes:
    Fills the list with the names of the libraries in use, sorted by name (TinyCAD's list is
    sorted). Each item remembers its library's place in the panel. Nothing is selected
    afterwards, so Remove and Cleanup are dimmed.
  =========================================================================== }
procedure TfrmLibraries.RefreshList;
var
  i: Integer;
begin
  lbLibs.Items.BeginUpdate;
  try
    lbLibs.Items.Clear;
    if FPanel <> nil then
      for i := 0 to FPanel.LibCount - 1 do
        lbLibs.Items.AddObject(LibraryName(FPanel.LibFileName(i)), TObject(PtrInt(i)));
  finally
    lbLibs.Items.EndUpdate;
  end;
  lbLibs.ItemIndex := -1;
  UpdateButtons;
end;

{ ===========================================================================
  TfrmLibraries.UpdateButtons  (procedure)
  Parameters:  none
  Notes:
    Remove and Cleanup need a selected library (TinyCAD's RefreshComponents); Edit and Upgrade
    stay dimmed.
  =========================================================================== }
procedure TfrmLibraries.UpdateButtons;
var
  Sel: Boolean;
begin
  Sel := SelectedIndex >= 0;
  btnRemove.Enabled := Sel;
  btnCleanup.Enabled := Sel;
  if Sel then
    lbLibs.Hint := SelectedFile
  else
    lbLibs.Hint := rsTheSymbolLibrariesInUse;
end;

{ ===========================================================================
  TfrmLibraries.SelectedIndex  (function)
  Parameters:  none
  Returns:
    Integer - the library's position in the panel, -1 when nothing is selected
  Notes:
    Which panel library the selected item stands for.
  =========================================================================== }
function TfrmLibraries.SelectedIndex: Integer;
begin
  if (FPanel = nil) or (lbLibs.ItemIndex < 0) then
    Result := -1
  else
    Result := PtrInt(lbLibs.Items.Objects[lbLibs.ItemIndex]);
end;

{ ===========================================================================
  TfrmLibraries.SelectedFile  (function)
  Parameters:  none
  Returns:
    String - the path, or '' for none
  Notes:
    The file of the selected library.
  =========================================================================== }
function TfrmLibraries.SelectedFile: String;
begin
  if SelectedIndex >= 0 then
    Result := FPanel.LibFileName(SelectedIndex)
  else
    Result := '';
end;

{ ===========================================================================
  TfrmLibraries.ItemCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many libraries the list shows.
  =========================================================================== }
function TfrmLibraries.ItemCount: Integer;
begin
  Result := lbLibs.Items.Count;
end;

{ ===========================================================================
  TfrmLibraries.ItemText  (function)
  Parameters:
    Index: Integer - position in the list
  Returns:
    String - the name, '' when out of range
  Notes:
    A line of the list.
  =========================================================================== }
function TfrmLibraries.ItemText(Index: Integer): String;
begin
  if (Index >= 0) and (Index < lbLibs.Items.Count) then
    Result := lbLibs.Items[Index]
  else
    Result := '';
end;

{ ===========================================================================
  TfrmLibraries.SelectByName  (function)
  Parameters:
    const AName: String - the name
  Returns:
    Boolean - True when there was one
  Notes:
    Selects the first library of that name, as clicking it does.
  =========================================================================== }
function TfrmLibraries.SelectByName(const AName: String): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to lbLibs.Items.Count - 1 do
    if SameText(lbLibs.Items[i], AName) then
    begin
      lbLibs.ItemIndex := i;
      UpdateButtons;
      Result := True;
      Exit;
    end;
end;

{ ===========================================================================
  TfrmLibraries.ListSelect  (procedure)
  Parameters:
    Sender: TObject - the list
    User: Boolean - True when the person chose
  Notes:
    A click on the list: the buttons are dimmed or not.
  =========================================================================== }
procedure TfrmLibraries.ListSelect(Sender: TObject; User: Boolean);
begin
  UpdateButtons;
end;

{ ===========================================================================
  TfrmLibraries.AddFiles  (procedure)
  Parameters:
    Files: TStrings - paths of the files chosen
  Notes:
    TinyCAD's OnAdd: each file is checked and, if it is a library not in use already, added to
    the libraries in use. A file that is not a library gives a message and the others go on. A
    library that is already in use is left as it is.
  =========================================================================== }
procedure TfrmLibraries.AddFiles(Files: TStrings);
var
  i: Integer;
  Err: String;
begin
  if FPanel = nil then
    Exit;
  for i := 0 to Files.Count - 1 do
  begin
    if FPanel.IndexOfFile(Files[i]) >= 0 then
      Continue;
    if not LibraryCheck(Files[i], Err) then
    begin
      Problem(Err);
      Continue;
    end;
    try
      FPanel.OpenLibrary(Files[i]);
    except
      on E: Exception do Problem(Format(rsCannotOpenLibrary2, [Files[i], E.Message]));
    end;
  end;
  RefreshList;
end;

{ ===========================================================================
  TfrmLibraries.AddClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Add: asks for one or more .TCLib files and adds them.
  =========================================================================== }
procedure TfrmLibraries.AddClick(Sender: TObject);
begin
  if frmSharedControls.dlgLibAdd.Execute then
    AddFiles(frmSharedControls.dlgLibAdd.Files);
end;

{ ===========================================================================
  TfrmLibraries.NewLibrary  (function)
  Parameters:
    const Chosen: String - text
  Returns:
    Boolean - True when the library was made and added
  Notes:
    TinyCAD's OnNew: an empty library file (.TCLib) is made and added to the libraries in use. A
    file that is there already is not touched and a message says so.
  =========================================================================== }
function TfrmLibraries.NewLibrary(const Chosen: String): Boolean;
var
  F, Err: String;
begin
  Result := False;
  if FPanel = nil then
    Exit;
  F := ExpandFileName(LibraryNewFileName(Chosen));
  if not LibraryCreate(F, Err) then
  begin
    Problem(Err);
    Exit;
  end;
  try
    FPanel.OpenLibrary(F);
    Result := True;
  except
    on E: Exception do Problem(Format(rsCannotOpenLibrary2, [F, E.Message]));
  end;
  RefreshList;
end;

{ ===========================================================================
  TfrmLibraries.NewClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    New: asks for the name of the library file and makes it.
  =========================================================================== }
procedure TfrmLibraries.NewClick(Sender: TObject);
begin
  if frmSharedControls.dlgLibNew.Execute then
    NewLibrary(frmSharedControls.dlgLibNew.FileName);
end;

{ ===========================================================================
  TfrmLibraries.RemoveSelected  (procedure)
  Parameters:  none
  Notes:
    TinyCAD's OnRemove: takes the selected library out of the libraries in use (the file is not
    deleted), unless it is in use, which gives IDS_NODELETE and changes nothing.
  =========================================================================== }
procedure TfrmLibraries.RemoveSelected;
var
  I: Integer;
begin
  I := SelectedIndex;
  if I < 0 then
    Exit;
  if Assigned(FOnInUse) and FOnInUse(FPanel.LibFileName(I)) then
  begin
    Problem(MSG_LIB_NODELETE);
    Exit;
  end;
  FPanel.CloseLibrary(I);
  RefreshList;
end;

{ ===========================================================================
  TfrmLibraries.RemoveClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Remove.
  =========================================================================== }
procedure TfrmLibraries.RemoveClick(Sender: TObject);
begin
  RemoveSelected;
end;

{ ===========================================================================
  TfrmLibraries.CleanupSelected  (procedure)
  Parameters:  none
  Notes:
    TinyCAD's OnCleanup: compacts the selected library's file, unless it is in use, which gives
    IDS_NOCLEANUP. The selection stays.
  =========================================================================== }
procedure TfrmLibraries.CleanupSelected;
var
  I: Integer;
  Err: String;
begin
  I := SelectedIndex;
  if I < 0 then
    Exit;
  if Assigned(FOnInUse) and FOnInUse(FPanel.LibFileName(I)) then
  begin
    Problem(MSG_LIB_NOCLEANUP);
    Exit;
  end;
  if not LibraryCleanup(FPanel.LibAt(I), Err) then
    Problem(Err);
end;

{ ===========================================================================
  TfrmLibraries.CleanupClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    Cleanup.
  =========================================================================== }
procedure TfrmLibraries.CleanupClick(Sender: TObject);
begin
  CleanupSelected;
end;

end.
