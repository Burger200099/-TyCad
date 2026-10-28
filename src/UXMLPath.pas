// SPDX-License-Identifier: LGPL-2.1-or-later
{ File names inside a design file (CTinyCadDoc::formatXMLFilename / unformatXMLFilename).

  A design stores the files it refers to (a hierarchical symbol's design) relative to the design's own
  folder, written the way TinyCAD on Windows writes them: with backslashes and, for a file below the
  folder or beside it, a leading ".\" (what PathRelativePathTo gives). In memory the name is a full
  path in the platform's own form, so it keeps pointing at the same file when the design is saved to
  another folder. XMLPathName is the file being read or written (TinyCAD's GetXMLPathName); the
  design file's LoadFromFile / SaveToFile set it for the length of the call.

  Original: Copyright 1994-2019 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit UXMLPath;

{$mode objfpc}{$H+}

interface

var
  { the full name of the design file being loaded or saved, '' when there is none }
  XMLPathName: String = '';

{ A name read from a design file as a name in memory: backslashes become the platform's separator, a
  relative name is made relative to XMLPathName's folder, '.' and '..' parts are resolved. A Windows
  drive path (C:\x\y.dsn) is kept as it is on a platform that has no drives. }
function UnformatXMLFilename(const S: String): String;

{ A name in memory as it is written to a design file: relative to XMLPathName's folder with
  backslashes, or unchanged (but for the separators) when there is no folder or no relative form. }
function FormatXMLFilename(const S: String): String;

{ CTinyCadDoc::formatFilename: the part after the last backslash (or separator) }
function FormatDisplayFilename(const S: String): String;

{ '.' and '..' parts and doubled separators taken out of a path, as PathCanonicalize does }
function CanonicalPath(const S: String): String;

implementation

uses
  SysUtils;

{ ===========================================================================
  IsDrivePath  (function)
  Parameters:
    const S: String - text
  Returns:
    Boolean
  Notes:
    A name that is absolute on Windows whatever platform the program runs on.
  =========================================================================== }
function IsDrivePath(const S: String): Boolean;
begin
  Result := ((Length(S) >= 3) and (S[2] = ':') and (S[3] in ['\', '/']) and (UpCase(S[1]) in ['A'..'Z'])) or
            ((Length(S) >= 2) and (S[1] = '\') and (S[2] = '\'));
end;

{ ===========================================================================
  CanonicalPath  (function)
  Parameters:
    const S: String - text
  Returns:
    String
  Notes:
    A relative path keeps '..' parts it cannot cancel; an absolute path drops '..' at its root.
  =========================================================================== }
function CanonicalPath(const S: String): String;
var
  Parts: array of String;
  N, i, Start: Integer;
  Rooted: Boolean;
  Part: String;
begin
  Rooted := (S <> '') and (S[1] = PathDelim);
  if (PathDelim = '\') and (Length(S) >= 2) and (S[2] = ':') then
    Rooted := False;   // a drive: kept below as the first part
  N := 0;
  SetLength(Parts, Length(S) + 1);
  Start := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = PathDelim) then
    begin
      Part := Copy(S, Start, i - Start);
      Start := i + 1;
      if (Part = '') or (Part = '.') then
        Continue;
      if Part = '..' then
      begin
        if (N > 0) and (Parts[N - 1] <> '..') then
          Dec(N)
        else if not Rooted then
        begin
          Parts[N] := '..';
          Inc(N);
        end;
        Continue;
      end;
      Parts[N] := Part;
      Inc(N);
    end;
  Result := '';
  for i := 0 to N - 1 do
  begin
    if Result <> '' then
      Result := Result + PathDelim;
    Result := Result + Parts[i];
  end;
  if Rooted then
    Result := PathDelim + Result;
  if (Result = '') and (S <> '') then
    Result := '.';
end;

{ ===========================================================================
  UnformatXMLFilename  (function)
  Parameters:
    const S: String - text
  Returns:
    String
  Notes:
    PathCombine of the design's folder and the name. With no design file the name is only given
    the platform's separators.
  =========================================================================== }
function UnformatXMLFilename(const S: String): String;
var
  T: String;
begin
  Result := S;
  if S = '' then
    Exit;
  if IsDrivePath(S) and (PathDelim = '/') then
    Exit;      // no drives here: nothing can be done with it
  T := S;
  if PathDelim <> '\' then
    T := StringReplace(T, '\', PathDelim, [rfReplaceAll]);
  if (T[1] = PathDelim) or ((PathDelim = '\') and IsDrivePath(T)) then
  begin
    Result := CanonicalPath(T);
    Exit;
  end;
  if XMLPathName = '' then
  begin
    Result := T;
    Exit;
  end;
  Result := CanonicalPath(ExtractFilePath(ExpandFileName(XMLPathName)) + T);
end;

{ ===========================================================================
  FormatXMLFilename  (function)
  Parameters:
    const S: String - text
  Returns:
    String
  Notes:
    PathRelativePathTo from the design file to the name: "..\x.dsn" above, ".\x.dsn" beside or
    ".\sub\x.dsn" below the file's folder. Names that cannot be made relative (no design file
    yet, a Windows drive path here, another drive) are written whole.
  =========================================================================== }
function FormatXMLFilename(const S: String): String;
var
  Base, Target, Rel: String;
begin
  Result := S;
  if S = '' then
    Exit;
  if (not IsDrivePath(S)) and (XMLPathName <> '') and (ExtractFilePath(ExpandFileName(S)) <> '') then
  begin
    Base := CanonicalPath(ExtractFilePath(ExpandFileName(XMLPathName)));
    Target := CanonicalPath(ExpandFileName(S));
    Rel := ExtractRelativepath(IncludeTrailingPathDelimiter(Base), Target);
    if (Rel <> '') and not ((PathDelim = '\') and (Length(Rel) > 1) and (Rel[2] = ':')) then
    begin
      if Copy(Rel, 1, 2) <> '..' then
        Rel := '.' + PathDelim + Rel;
      Result := Rel;
    end;
  end;
  if PathDelim <> '\' then
    Result := StringReplace(Result, PathDelim, '\', [rfReplaceAll]);
end;

{ ===========================================================================
  FormatDisplayFilename  (function)
  Parameters:
    const S: String - text
  Returns:
    String
  Notes:
    CTinyCadDoc::formatFilename.
  =========================================================================== }
function FormatDisplayFilename(const S: String): String;
var
  i: Integer;
begin
  i := Length(S);
  while (i > 0) and (S[i] <> '\') and (S[i] <> PathDelim) do Dec(i);      // (not a set: on Windows both are the same character, which a set refuses)
  Result := Copy(S, i + 1, MaxInt);
end;

end.
