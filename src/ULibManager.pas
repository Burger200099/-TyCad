// SPDX-License-Identifier: LGPL-2.1-or-later
{ The rules of the library manager (TinyCAD's CDlgLibraryBox, Library > Libraries...) without any window: what a library is called in the list, which file a name
  stands for, checking that a file is a library, making a new empty library, and cleaning one up (SQLite VACUUM). Every function reports a problem as the text the
  dialog shows. The dialog and the library panel keep the list; this unit knows only files.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit ULibManager;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, ULibrary;

const
  LIB_EXTENSION = '.TCLib';
  { TinyCAD's IDS_NODELETE and IDS_NOCLEANUP }
  MSG_LIB_NODELETE = 'Cannot delete a library while it is being edited or while you are creating a new symbol for it.  Close the editing windows and try again';
  MSG_LIB_NOCLEANUP = 'Cannot cleanup a library while it is being edited or while you are creating a new symbol for it.  Close the editing windows and try again';

{ the name the list shows for a library: the file name without its folder and extension }
function LibraryName(const FileName: String): String;
{ True when the file name has the .TCLib extension (in any case) }
function LibraryHasExtension(const FileName: String): Boolean;
{ the file a New library is made in: the name chosen with its extension changed to .TCLib (TinyCAD takes the extension off and puts .TCLib on) }
function LibraryNewFileName(const Chosen: String): String;
{ checks that a file opens as a library; Err is the reason when it does not }
function LibraryCheck(const FileName: String; out Err: String): Boolean;
{ makes a new empty library file; it is not replaced when it exists }
function LibraryCreate(const FileName: String; out Err: String): Boolean;
{ runs the cleanup (VACUUM) on an open library }
function LibraryCleanup(ALib: TSymbolLibrary; out Err: String): Boolean;

implementation


uses UStrings;

{ ===========================================================================
  LibraryName  (function)
  Parameters:
    const FileName: String - path of the file
  Returns:
    String - the name
  Notes:
    What the Libraries list shows for a library (TinyCAD shows the path without the extension;
    the name alone keeps the list short and the folder is in the hint).
  =========================================================================== }
function LibraryName(const FileName: String): String;
begin
  Result := ChangeFileExt(ExtractFileName(FileName), '');
end;

{ ===========================================================================
  LibraryHasExtension  (function)
  Parameters:
    const FileName: String - path of the file
  Returns:
    Boolean - True for .TCLib in any case
  Notes:
    Tells a symbol library from another file by its extension.
  =========================================================================== }
function LibraryHasExtension(const FileName: String): Boolean;
begin
  Result := SameText(ExtractFileExt(FileName), LIB_EXTENSION);
end;

{ ===========================================================================
  LibraryNewFileName  (function)
  Parameters:
    const Chosen: String - text
  Returns:
    String - the file to make
  Notes:
    A name without .TCLib gets it (an other extension is replaced), as TinyCAD's New does. A
    .tclib typed in lower case is kept as typed.
  =========================================================================== }
function LibraryNewFileName(const Chosen: String): String;
begin
  if LibraryHasExtension(Chosen) then
    Result := Chosen
  else
    Result := ChangeFileExt(Chosen, '') + LIB_EXTENSION;
end;

{ ===========================================================================
  LibraryCheck  (function)
  Parameters:
    const FileName: String - path of the file
    out Err: String - text (out: set by the call)
  Returns:
    Boolean - True when it opens as a symbol library
  Notes:
    TinyCAD's Attach: the file is opened and its symbols read. A file with another extension is
    refused (the old .mdb and .idx libraries are not read by this port).
  =========================================================================== }
function LibraryCheck(const FileName: String; out Err: String): Boolean;
var
  L: TSymbolLibrary;
begin
  Result := False;
  Err := '';
  if not FileExists(FileName) then
  begin
    Err := Format(rsTheFileIsNotThere, [FileName]);
    Exit;
  end;
  if not LibraryHasExtension(FileName) then
  begin
    Err := Format(rsIsNotATCLibLibrary, [FileName]);
    Exit;
  end;
  L := TSymbolLibrary.Create;
  try
    try
      L.Open(FileName);
      Result := True;
    except
      on E: Exception do Err := Format(rsCannotOpenLibrary2, [FileName, E.Message]);
    end;
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  LibraryCreate  (function)
  Parameters:
    const FileName: String - path of the file
    out Err: String - text (out: set by the call)
  Returns:
    Boolean - True when the file was made
  Notes:
    Makes an empty library with TinyCAD's tables. A file that is already there is left alone
    (TinyCAD's CREATE TABLE fails on it) and the message is TinyCAD's "Cannot create library".
  =========================================================================== }
function LibraryCreate(const FileName: String; out Err: String): Boolean;
var
  L: TSymbolLibrary;
begin
  Result := False;
  Err := '';
  if FileExists(FileName) then
  begin
    Err := Format(rsCannotCreateLibraryTheFile, [LibraryName(FileName), FileName]);
    Exit;
  end;
  L := TSymbolLibrary.Create;
  try
    try
      L.CreateNew(FileName);
      Result := True;
    except
      on E: Exception do
      begin
        Err := Format(rsCannotCreateLibrary2, [LibraryName(FileName), E.Message]);
        L.Free;
        L := nil;
        if FileExists(FileName) then
          DeleteFile(FileName);       // (nothing half made is left behind)
      end;
    end;
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  LibraryCleanup  (function)
  Parameters:
    ALib: TSymbolLibrary - the open library
    out Err: String - text (out: set by the call)
  Returns:
    Boolean - True when the file was compacted
  Notes:
    TinyCAD's Cleanup: runs VACUUM on the library's database.
  =========================================================================== }
function LibraryCleanup(ALib: TSymbolLibrary; out Err: String): Boolean;
begin
  Result := False;
  Err := '';
  try
    ALib.Cleanup;
    Result := True;
  except
    on E: Exception do Err := Format(rsCannotCleanUpLibrary, [LibraryName(ALib.FileName), E.Message]);
  end;
end;

end.
