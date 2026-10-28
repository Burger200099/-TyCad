{ Copy and paste of drawing objects, in TinyCAD's own clipboard format.

  TinyCAD puts the selection on the clipboard under the registered format name "TinyCAD Design"
  (CLIPBOARD_FORMAT). The data is the XML a sheet save writes, with the header, resources and symbol
  definitions the selected objects use, but only the selected objects (CTinyCadDoc::SaveXML with
  Details and SaveSelect). Paste reads that XML back into the sheet, merging fonts, line styles,
  fills and symbol definitions with the sheet's own, adds the objects and selects them; the block
  then follows the mouse until it is dropped.

  This unit does the part that does not need a window: writing the selection to a stream, reading a
  stream into a sheet, and working out the block's reference point. Because the format is exactly the
  sheet file format, a single-sheet .dsn file is also valid clipboard data.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UClip;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, UDPoint, UDrawTypes, UGeometry, UDrawingObjects, UDesign, UXMLReader,
  UXMLWriter, UXMLException;

const
  CLIPBOARD_FORMAT_NAME = 'TinyCAD Design';   // the registered clipboard format
  CLIPBOARD_SYMBOL_FORMAT_NAME = 'TinyCAD Symbol';   // used by the library editor (not handled here)

{ Write the selected objects of a sheet as clipboard data. Returns how many objects were written. }
function CopySelection(Sheet: TDesignSheet; Selected: TList; Dest: TStream): Integer;
{ Read clipboard data (or any single sheet of a .dsn) into a sheet. The new objects are added to the
  sheet with new object ids and are returned in Imported (not owned). False if the data is not a
  TinyCAD drawing; the sheet is then unchanged. }
function PasteStream(Design: TDesignFile; Sheet: TDesignSheet; Src: TStream; Imported: TList): Boolean;
{ The point of a pasted block that follows the mouse: the snapped far corner (largest x and y of
  all the objects' points), as CDrawBlockImport::Import works it out. }
function BlockReference(Sheet: TDesignSheet; Imported: TList): TDPoint;

implementation

{ ===========================================================================
  CopySelection  (function)
  Parameters:
    Sheet: TDesignSheet - the sheet the objects are on
    Selected: TList - the objects to copy
    Dest: TStream - where to write the data
  Returns:
    Integer - the number of objects written (0 writes nothing)
  Notes:
    Writes the selected objects of a sheet as clipboard data: the sheet XML with its header,
    resources and symbol definitions but only the selected objects, which is what TinyCAD puts
    on the clipboard under "TinyCAD Design". Only the resources the selected objects use are
    written.
  =========================================================================== }
function CopySelection(Sheet: TDesignSheet; Selected: TList; Dest: TStream): Integer;
var
  W: TXMLWriter;
  i: Integer;
begin
  Result := 0;
  for i := 0 to Sheet.Drawing.Count - 1 do
    if (Selected.IndexOf(Sheet.Drawing[i]) >= 0) and (Sheet.Drawing[i].GetType <> xOrigin) then
      Inc(Result);
  if Result = 0 then
    Exit;
  Sheet.Options.UnTagAll;
  W := TXMLWriter.Create(Dest);
  try
    Sheet.SaveXMLEx(W, True, True, False, Selected);
  finally
    W.Free;
  end;
end;

{ ===========================================================================
  PasteStream  (function)
  Parameters:
    Design: TDesignFile - the design (new objects get their ids from it)
    Sheet: TDesignSheet - the sheet to paste into
    Src: TStream - the clipboard data
    Imported: TList - receives the new objects (not owned)
  Returns:
    Boolean - True if objects were pasted
  Notes:
    Reads clipboard data (or any sheet of a .dsn file) into a sheet the way TinyCAD's Import
    does: the data's fonts, line styles, fills and symbols are merged with the sheet's own, the
    objects are added with new ids and nothing else of the sheet changes. Trailing zero bytes
    (Windows rounds clipboard blocks up) are ignored; data that is not a TinyCAD drawing is
    refused and leaves the sheet unchanged.
  =========================================================================== }
function PasteStream(Design: TDesignFile; Sheet: TDesignSheet; Src: TStream; Imported: TList): Boolean;
var
  Raw: String;
  MS: TMemoryStream;
  R: TXMLReader;
  Tag: String;
  Temp: TDrawingList;
  i, n: Integer;
  Obj: TDrawingObject;
begin
  Result := False;
  Imported.Clear;
  n := Src.Size - Src.Position;
  if n <= 0 then
    Exit;
  SetLength(Raw, n);
  Src.ReadBuffer(Raw[1], n);
  while (Length(Raw) > 0) and (Raw[Length(Raw)] = #0) do SetLength(Raw, Length(Raw) - 1);
  if Pos('<', Raw) = 0 then
    Exit;
  MS := TMemoryStream.Create;
  Temp := TDrawingList.Create;
  try
    MS.WriteBuffer(Raw[1], Length(Raw));
    MS.Position := 0;
    try
      R := TXMLReader.Create(MS);
    except
      on EXMLException do Exit;
    end;
    try
      try
        R.NextTag(Tag);
        if Tag = 'TinyCADSheets' then
        begin
          R.IntoTag;
          repeat until (not R.NextTag(Tag)) or (Tag = 'TinyCAD');
        end;
        if Tag <> 'TinyCAD' then
          Exit;
        Sheet.LoadXMLInto(R, Temp, False, False);
      except
        on EXMLException do Exit;
      end;
    finally
      R.Free;
    end;
    { hand the objects over to the sheet (the list owns what it holds, so take them out first) }
    for i := 0 to Temp.Count - 1 do
    begin
      Obj := Temp[i];
      if Obj.GetType = xOrigin then
        Continue;
      Obj.Id := Design.NextObjectId;
      Sheet.Drawing.Add(Obj);
      Imported.Add(Obj);
    end;
    Temp.OwnsObjects := False;
    Result := Imported.Count > 0;
    Sheet.UpdateLayout;
  finally
    Temp.Free;
    MS.Free;
  end;
end;

{ ===========================================================================
  BlockReference  (function)
  Parameters:
    Sheet: TDesignSheet - the sheet (its grid snaps the result)
    Imported: TList - the pasted objects
  Returns:
    TDPoint - the reference point
  Notes:
    The point of a pasted block that follows the mouse: the largest x and y over the objects'
    points, snapped to the grid (the block's bottom-right corner), as CDrawBlockImport::Import
    works it out.
  =========================================================================== }
function BlockReference(Sheet: TDesignSheet; Imported: TList): TDPoint;
var
  i: Integer;
  O: TDrawingObject;
begin
  Result := DPoint(0, 0);
  for i := 0 to Imported.Count - 1 do
  begin
    O := TDrawingObject(Imported[i]);
    if not HasCorners(O) then
      Continue;
    Result.x := Max(Result.x, Max(O.PointA.x, O.PointB.x));
    Result.y := Max(Result.y, Max(O.PointA.y, O.PointB.y));
  end;
  Result := Sheet.Snap.Snap(Result);
end;

end.
