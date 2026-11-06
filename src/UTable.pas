// SPDX-License-Identifier: LGPL-2.1-or-later
{ The table object: rows and columns of text in one font, edited in the table editor window (Ftable). The cells are kept here; the painter (UPainter) draws them and
  the file format is the TABLE element. Licence: LGPL 2.1 or later, as the rest of this port. }
unit UTable;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, UDPoint, UDrawTypes, UResources, UDrawingObjects, UXMLReader, UXMLWriter, UGeometry;

const
  TABLE_PAD = 4;                  // internal units between the text and the lines of a table
  TABLE_MIN_COL = 40;             // the least a table column is wide (8 mm)

var
  { the sheet the objects on the clipboard were copied from: a table pasted on any other sheet loses its links (the objects it showed are not there) }
  TableClipSheet: TObject = nil;

type
  TTableSizes = array of Double;
  TTableRow = array of String;
  { a cell that shows the text of another object of the sheet (ObjId 0: no link). Field is the number of the field of a symbol, -1 for the text of a text, label or note }
  TTableLink = record
    ObjId, Field: Integer;
  end;
  TTableLinkRow = array of TTableLink;

  { TABLE: rows and columns of text. Row 0 holds the column titles (drawn only with ShowTitles). The size follows the font and the text until the table is
    resized by its handles (AutoSize false); then the columns and rows share the room in proportion, and the table never gets smaller than its text. }
  TDrawTable = class(TDrawingObject)
  public
    Cols, Rows: Integer;      // Rows counts the titles row
    Cells: array of TTableRow;   // [row][column]; a linked cell holds the text its object had when the links were last worked out (UTableLinks)
    Links: array of TTableLinkRow;   // [row][column]
    ShowTitles: Integer;      // BOOL: draw row 0
    GridStyle: Integer;       // 0 solid, 1 dashed, 2 hidden
    AutoSize: Boolean;        // the size is the size of the text
    FontStyle: Integer;
    FontColor: Cardinal;
    constructor Create(AOpts: TDocOptionsBase); override;
    function GetType: TObjType; override;
    function CanResize: Boolean; override;
    procedure ResizeBy(Handle: Integer; const R: TDPoint); override;
    procedure LoadXML(R: TXMLReader); override;
    procedure SaveXML(W: TXMLWriter); override;
    procedure TagResources; override;
    function Clone: TDrawingObject; override;
    function DistanceFromPoint(const P: TDPoint): Double; override;
    function IsInside(Left, Right, Top, Bottom: Double): Boolean; override;
    procedure SetSize(NCols, NRows: Integer);
    function Cell(R, C: Integer): String;
    procedure SetCell(R, C: Integer; const S: String);
    procedure InsertRow(At: Integer);
    procedure DeleteRow(At: Integer);
    procedure InsertCol(At: Integer);
    procedure DeleteCol(At: Integer);
    function IsLinked(R, C: Integer): Boolean;
    function LinkAt(R, C: Integer): TTableLink;
    procedure SetLink(R, C, ObjId, Field: Integer);
    { the text of a linked cell as the link gives it (SetCell would break the link) }
    procedure SetShown(R, C: Integer; const S: String);
    { cuts every link: the cells keep their text, or are emptied with Blank (a table pasted on another sheet) }
    procedure BreakLinks(Blank: Boolean);
    function FirstRow: Integer;
    { the widths of the columns and the heights of the rows that are drawn (from FirstRow), as the table is laid out now }
    procedure Layout(out ColW, RowH: TTableSizes);
    { makes the corners agree with the text: the size of the text when AutoSize, never less than it otherwise }
    procedure Fit;
  end;

implementation

{ ===========================================================================
  TDrawTable.Create  (constructor)
  Parameters:
    AOpts: TDocOptionsBase - the sheet options (fonts, styles, snap grid, text metrics)
  Notes:
    A table of 3 columns and a titles row with 3 rows below it, titled A, B and C, the size of its text.
  =========================================================================== }
constructor TDrawTable.Create(AOpts: TDocOptionsBase);
var
  c: Integer;
begin
  inherited Create(AOpts);
  PointA := DPoint(0, 0);
  PointB := DPoint(0, 0);
  ShowTitles := 1;
  GridStyle := 0;
  AutoSize := True;
  FontStyle := fTEXT;
  FontColor := RGB(0, 0, 0);
  SetSize(3, 4);
  for c := 0 to 2 do
    Cells[0][c] := Chr(Ord('A') + c);
end;

{ ===========================================================================
  TDrawTable.GetType  (function)
  Returns:
    TObjType - xTable
  =========================================================================== }
function TDrawTable.GetType: TObjType;
begin Result := xTable; end;

{ ===========================================================================
  TDrawTable.CanResize  (function)
  Returns:
    Boolean - True: the eight handles of the rectangle (ResizeBy makes the table fit its text again)
  =========================================================================== }
function TDrawTable.CanResize: Boolean;
begin
  Result := True;
end;

{ ===========================================================================
  TDrawTable.ResizeBy  (procedure)
  Parameters:
    Handle: Integer - the handle
    const R: TDPoint - how far it was dragged
  Notes:
    Dragging a handle ends the size-of-the-text mode (moving the whole table does not); the table keeps at least the size of its text.
  =========================================================================== }
procedure TDrawTable.ResizeBy(Handle: Integer; const R: TDPoint);
begin
  inherited ResizeBy(Handle, R);
  if (Handle <> 8) and (Handle <> 11) then
    AutoSize := False;
  Fit;
end;

{ ===========================================================================
  TDrawTable.SetSize  (procedure)
  Parameters:
    NCols, NRows: Integer - the new numbers (at least 1; NRows counts the titles row)
  Notes:
    Keeps the cells that are still there and makes the new ones empty.
  =========================================================================== }
procedure TDrawTable.SetSize(NCols, NRows: Integer);
var
  r, c: Integer;
begin
  NCols := Max(1, NCols); NRows := Max(1, NRows);
  SetLength(Cells, NRows);
  SetLength(Links, NRows);
  for r := 0 to NRows - 1 do
  begin
    SetLength(Cells[r], NCols);
    SetLength(Links[r], NCols);
    if r >= Rows then
      for c := 0 to NCols - 1 do
      begin
        Cells[r][c] := '';
        Links[r][c].ObjId := 0; Links[r][c].Field := -1;
      end;
    if r < Rows then
      for c := Cols to NCols - 1 do
      begin
        Cells[r][c] := '';
        Links[r][c].ObjId := 0; Links[r][c].Field := -1;
      end;
  end;
  Cols := NCols; Rows := NRows;
end;

{ ===========================================================================
  TDrawTable.Cell  (function)
  Parameters:
    R, C: Integer - row (0 is the titles) and column
  Returns:
    String - the text, empty outside the table
  =========================================================================== }
function TDrawTable.Cell(R, C: Integer): String;
begin
  if (R >= 0) and (R < Rows) and (C >= 0) and (C < Cols) then
    Result := Cells[R][C]
  else
    Result := '';
end;

{ ===========================================================================
  TDrawTable.SetCell  (procedure)
  Parameters:
    R, C: Integer - row and column
    const S: String - the text (one line: tabs and line ends become spaces)
  =========================================================================== }
procedure TDrawTable.SetCell(R, C: Integer; const S: String);
begin
  if (R >= 0) and (R < Rows) and (C >= 0) and (C < Cols) then
  begin
    Links[R][C].ObjId := 0;          // (typing in a cell cuts its link)
    Cells[R][C] := StringReplace(StringReplace(StringReplace(S, #9, ' ', [rfReplaceAll]), #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  end;
end;

{ ===========================================================================
  TDrawTable.InsertRow  (procedure)
  Parameters:
    At: Integer - the new row goes before this one (Rows for the end); the titles row stays first
  =========================================================================== }
procedure TDrawTable.InsertRow(At: Integer);
var
  r, c: Integer;
begin
  At := Max(1, Min(At, Rows));
  SetSize(Cols, Rows + 1);
  for r := Rows - 1 downto At + 1 do
    for c := 0 to Cols - 1 do
    begin
      Cells[r][c] := Cells[r - 1][c];
      Links[r][c] := Links[r - 1][c];
    end;
  for c := 0 to Cols - 1 do
  begin
    Cells[At][c] := '';
    Links[At][c].ObjId := 0;
  end;
end;

{ ===========================================================================
  TDrawTable.DeleteRow  (procedure)
  Parameters:
    At: Integer - the row; the titles row and the last row left cannot be deleted
  =========================================================================== }
procedure TDrawTable.DeleteRow(At: Integer);
var
  r, c: Integer;
begin
  if (At < 1) or (At >= Rows) or (Rows <= 2) then
    Exit;
  for r := At to Rows - 2 do
    for c := 0 to Cols - 1 do
    begin
      Cells[r][c] := Cells[r + 1][c];
      Links[r][c] := Links[r + 1][c];
    end;
  SetSize(Cols, Rows - 1);
end;

{ ===========================================================================
  TDrawTable.InsertCol  (procedure)
  Parameters:
    At: Integer - the new column goes before this one (Cols for the end)
  =========================================================================== }
procedure TDrawTable.InsertCol(At: Integer);
var
  r, c: Integer;
begin
  At := Max(0, Min(At, Cols));
  SetSize(Cols + 1, Rows);
  for r := 0 to Rows - 1 do
  begin
    for c := Cols - 1 downto At + 1 do
    begin
      Cells[r][c] := Cells[r][c - 1];
      Links[r][c] := Links[r][c - 1];
    end;
    Cells[r][At] := '';
    Links[r][At].ObjId := 0;
  end;
end;

{ ===========================================================================
  TDrawTable.DeleteCol  (procedure)
  Parameters:
    At: Integer - the column; the last column left cannot be deleted
  =========================================================================== }
procedure TDrawTable.DeleteCol(At: Integer);
var
  r, c: Integer;
begin
  if (At < 0) or (At >= Cols) or (Cols <= 1) then
    Exit;
  for r := 0 to Rows - 1 do
    for c := At to Cols - 2 do
    begin
      Cells[r][c] := Cells[r][c + 1];
      Links[r][c] := Links[r][c + 1];
    end;
  SetSize(Cols - 1, Rows);
end;

{ ===========================================================================
  TDrawTable.IsLinked / LinkAt / SetLink / SetShown / BreakLinks
  Notes:
    A linked cell shows the text of another object of the sheet (or of one field of a symbol); UTableLinks works the text out whenever the drawing changes.
  =========================================================================== }
function TDrawTable.IsLinked(R, C: Integer): Boolean;
begin
  Result := (R >= 0) and (R < Rows) and (C >= 0) and (C < Cols) and (Links[R][C].ObjId <> 0);
end;

function TDrawTable.LinkAt(R, C: Integer): TTableLink;
begin
  if (R >= 0) and (R < Rows) and (C >= 0) and (C < Cols) then
    Result := Links[R][C]
  else
  begin
    Result.ObjId := 0; Result.Field := -1;
  end;
end;

procedure TDrawTable.SetLink(R, C, ObjId, Field: Integer);
begin
  if (R >= 0) and (R < Rows) and (C >= 0) and (C < Cols) then
  begin
    Links[R][C].ObjId := ObjId;
    Links[R][C].Field := Field;
  end;
end;

procedure TDrawTable.SetShown(R, C: Integer; const S: String);
begin
  if (R >= 0) and (R < Rows) and (C >= 0) and (C < Cols) then
    Cells[R][C] := StringReplace(StringReplace(StringReplace(S, #9, ' ', [rfReplaceAll]), #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
end;

procedure TDrawTable.BreakLinks(Blank: Boolean);
var
  r, c: Integer;
begin
  for r := 0 to Rows - 1 do
    for c := 0 to Cols - 1 do
      if Links[r][c].ObjId <> 0 then
      begin
        Links[r][c].ObjId := 0;
        if Blank then
          Cells[r][c] := '';
      end;
end;

{ ===========================================================================
  TDrawTable.FirstRow  (function)
  Returns:
    Integer - 0 when the titles are shown, else 1
  =========================================================================== }
function TDrawTable.FirstRow: Integer;
begin
  if ShowTitles <> 0 then
    Result := 0
  else
    Result := 1;
end;

{ ===========================================================================
  TDrawTable.Layout  (procedure)
  Parameters:
    out ColW: TTableSizes - the width of each column
    out RowH: TTableSizes - the height of each drawn row
  Notes:
    The size of the text (the widest cell of each column, the tallest line of each row, with TABLE_PAD round it) is the least; when the corners are further apart
    the columns and the rows grow in proportion.
  =========================================================================== }
procedure TDrawTable.Layout(out ColW, RowH: TTableSizes);
var
  r, c, r0: Integer;
  Sz: TDSize;
  NatW, NatH, W, H, Lh: Double;
begin
  r0 := FirstRow;
  SetLength(ColW, Cols); SetLength(RowH, Rows - r0);
  Lh := FOpts.TextExtent('Ag', FontStyle).cy;
  NatW := 0; NatH := 0;
  for c := 0 to Cols - 1 do
  begin
    ColW[c] := TABLE_MIN_COL;
    for r := r0 to Rows - 1 do
      if Cells[r][c] <> '' then
      begin
        Sz := FOpts.TextExtent(Cells[r][c], FontStyle);
        ColW[c] := Max(ColW[c], Sz.cx + 2 * TABLE_PAD);
      end;
    NatW := NatW + ColW[c];
  end;
  for r := r0 to Rows - 1 do
  begin
    RowH[r - r0] := Lh + 2 * TABLE_PAD;
    for c := 0 to Cols - 1 do
      if Cells[r][c] <> '' then
        RowH[r - r0] := Max(RowH[r - r0], FOpts.TextExtent(Cells[r][c], FontStyle).cy + 2 * TABLE_PAD);
    NatH := NatH + RowH[r - r0];
  end;
  W := Abs(PointB.x - PointA.x); H := Abs(PointB.y - PointA.y);
  if (not AutoSize) and (W > NatW) and (NatW > 0) then
    for c := 0 to Cols - 1 do
      ColW[c] := ColW[c] * W / NatW;
  if (not AutoSize) and (H > NatH) and (NatH > 0) then
    for r := 0 to High(RowH) do
      RowH[r] := RowH[r] * H / NatH;
end;

{ ===========================================================================
  TDrawTable.Fit  (procedure)
  Notes:
    Puts the corners where the layout says (A at the top left); the table is the size of its text when AutoSize, else the size it was given but not less than its text.
  =========================================================================== }
procedure TDrawTable.Fit;
var
  ColW, RowH: TTableSizes;
  L, T, W, H, NatW, NatH: Double;
  i: Integer;
  Keep: Boolean;
begin
  L := Min(PointA.x, PointB.x); T := Min(PointA.y, PointB.y);
  W := Abs(PointB.x - PointA.x); H := Abs(PointB.y - PointA.y);
  Keep := AutoSize;
  AutoSize := True;                 // (Layout gives the size of the text)
  PointA := DPoint(L, T); PointB := DPoint(L, T);
  Layout(ColW, RowH);
  AutoSize := Keep;
  NatW := 0; NatH := 0;
  for i := 0 to High(ColW) do NatW := NatW + ColW[i];
  for i := 0 to High(RowH) do NatH := NatH + RowH[i];
  if Keep then
  begin
    W := NatW; H := NatH;
  end
  else
  begin
    W := Max(W, NatW); H := Max(H, NatH);
  end;
  PointA := DPoint(L, T);
  PointB := DPoint(L + W, T + H);
end;

{ ===========================================================================
  TDrawTable.TagResources  (procedure)
  =========================================================================== }
procedure TDrawTable.TagResources;
begin
  FOpts.Fonts.Tag(FontStyle);
end;

{ the cells as one text: a tab after each cell but the last of a row, the characters \ tab and line end written as \\ \t \n, and a row ends with \n }
function TableCellsToText(T: TDrawTable): String;
var
  r, c: Integer;
begin
  Result := '';
  for r := 0 to T.Rows - 1 do
  begin
    for c := 0 to T.Cols - 1 do
    begin
      Result := Result + StringReplace(StringReplace(T.Cells[r][c], '\', '\\', [rfReplaceAll]), #9, '\t', [rfReplaceAll]);
      if c < T.Cols - 1 then
        Result := Result + '\t';
    end;
    Result := Result + '\n';
  end;
end;

procedure TableCellsFromText(T: TDrawTable; const S: String);
var
  r, c, i: Integer;
  Cur: String;
begin
  r := 0; c := 0; Cur := '';
  T.SetSize(T.Cols, Max(T.Rows, 1));
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '\') and (i < Length(S)) then
    begin
      Inc(i);
      case S[i] of
        't': begin T.SetCell(r, c, Cur); Cur := ''; Inc(c); end;
        'n': begin T.SetCell(r, c, Cur); Cur := ''; Inc(r); c := 0; end;
      else
        Cur := Cur + S[i];
      end;
    end
    else
      Cur := Cur + S[i];
    Inc(i);
  end;
end;

{ ===========================================================================
  TDrawTable.SaveXML  (procedure)
  Parameters:
    W: TXMLWriter - the XML writer to save into
  Notes:
    <TABLE a= b= cols= rows= titles= grid= auto= font= color= data=>: the cells are one text, see TableCellsToText.
  =========================================================================== }
procedure TDrawTable.SaveXML(W: TXMLWriter);
var
  r, c: Integer;
  Lk: String;
begin
  BeginTag(W, 'TABLE');
  W.AddAttribute('a', PointA);
  W.AddAttribute('b', PointB);
  W.AddAttribute('cols', Cols);
  W.AddAttribute('rows', Rows);
  W.AddAttribute('titles', ShowTitles);
  W.AddAttribute('grid', GridStyle);
  if not AutoSize then
    W.AddAttribute('auto', 0);
  W.AddAttribute('font', FontStyle);
  W.AddAttributeColor('color', FontColor);
  W.AddAttribute('data', TableCellsToText(Self));
  Lk := '';
  for r := 0 to Rows - 1 do
    for c := 0 to Cols - 1 do
      if Links[r][c].ObjId <> 0 then
        Lk := Lk + IfThen(Lk <> '', ';', '') + Format('%d:%d:%d:%d', [r, c, Links[r][c].ObjId, Links[r][c].Field]);
  if Lk <> '' then
    W.AddAttribute('links', Lk);
  W.CloseTag;
end;

{ ===========================================================================
  TDrawTable.LoadXML  (procedure)
  Parameters:
    R: TXMLReader - the XML reader, positioned on this element
  =========================================================================== }
procedure TDrawTable.LoadXML(R: TXMLReader);
var
  F, NC, NR, A: Integer;
  S: String;
  L, P: TStringList;
begin
  R.GetAttribute('a', PointA);
  R.GetAttribute('b', PointB);
  NC := Cols; NR := Rows;
  R.GetAttribute('cols', NC);
  R.GetAttribute('rows', NR);
  Cols := 0; Rows := 0; SetLength(Cells, 0);
  SetSize(NC, NR);
  R.GetAttribute('titles', ShowTitles);
  R.GetAttribute('grid', GridStyle);
  A := 1;
  R.GetAttribute('auto', A);
  AutoSize := A <> 0;
  F := FontStyle;
  R.GetAttribute('font', F);
  R.GetAttributeColor('color', FontColor);
  FontStyle := FOpts.Fonts.ConvertOld(Integer(SmallInt(F and $FFFF)));
  S := '';
  if R.GetAttribute('data', S) then
    TableCellsFromText(Self, S);
  S := '';
  if R.GetAttribute('links', S) then
  begin
    L := TStringList.Create;
    try
      L.Delimiter := ';'; L.StrictDelimiter := True; L.DelimitedText := S;
      for A := 0 to L.Count - 1 do
      begin
        P := TStringList.Create;
        try
          P.Delimiter := ':'; P.StrictDelimiter := True; P.DelimitedText := L[A];
          if P.Count = 4 then
            SetLink(StrToIntDef(P[0], -1), StrToIntDef(P[1], -1), StrToIntDef(P[2], 0), StrToIntDef(P[3], -1));
        finally
          P.Free;
        end;
      end;
    finally
      L.Free;
    end;
  end;
end;

{ ===========================================================================
  TDrawTable.Clone  (function)
  Returns:
    TDrawingObject - an independent copy
  =========================================================================== }
function TDrawTable.Clone: TDrawingObject;
var
  O: TDrawTable;
  r: Integer;
begin
  O := TDrawTable.Create(FOpts);
  O.PointA := PointA; O.PointB := PointB;
  O.SetSize(Cols, Rows);
  for r := 0 to Rows - 1 do
    begin
      O.Cells[r] := Copy(Cells[r], 0, Cols);
      O.Links[r] := Copy(Links[r], 0, Cols);
    end;
  O.ShowTitles := ShowTitles; O.GridStyle := GridStyle; O.AutoSize := AutoSize;
  O.FontStyle := FontStyle; O.FontColor := FontColor;
  Result := O;
end;

{ ===========================================================================
  TDrawTable.DistanceFromPoint  (function)
  Parameters:
    const P: TDPoint - a point, in design units
  Returns:
    Double - 0 inside the table, else the distance to its edge
  =========================================================================== }
function TDrawTable.DistanceFromPoint(const P: TDPoint): Double;
var
  L, T, R, B, Dx, Dy: Double;
begin
  L := Min(PointA.x, PointB.x); R := Max(PointA.x, PointB.x);
  T := Min(PointA.y, PointB.y); B := Max(PointA.y, PointB.y);
  Dx := Max(Max(L - P.x, 0), P.x - R);
  Dy := Max(Max(T - P.y, 0), P.y - B);
  Result := Min(100.0, Hypot(Dx, Dy));
end;

{ ===========================================================================
  TDrawTable.IsInside  (function)
  Parameters:
    Left, Right, Top, Bottom: Double - the rectangle (a point for a click)
  Returns:
    Boolean - True if the table touches the rectangle
  =========================================================================== }
function TDrawTable.IsInside(Left, Right, Top, Bottom: Double): Boolean;
begin
  if (Left = Right) and (Top = Bottom) then
    Result := DistanceFromPoint(DPoint(Left, Top)) < 3 / FOpts.ZoomFactor
  else
    Result := not ((Max(PointA.x, PointB.x) < Left) or (Min(PointA.x, PointB.x) > Right) or (Max(PointA.y, PointB.y) < Top) or (Min(PointA.y, PointB.y) > Bottom));
end;

{ makes an empty table for the TABLE element of a file }
function MakeTable(Opts: TDocOptionsBase): TDrawingObject;
begin
  Result := TDrawTable.Create(Opts);
end;

initialization
  RegisterObjectTag('TABLE', @MakeTable);
end.
