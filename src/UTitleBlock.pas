{ Where everything of the extended title block goes, worked out from the page alone, so that the painter only has to draw it and a test can check the numbers.

  The standard block is TinyCAD's: 400 units wide and 9 lines of 18 units high in the bottom right corner of the page (set in from the edge by the width of the
  rulers when they are on). The extended information adds:
    - a revision table to the LEFT of it, as high as the block, six rows (a heading and the five newest revisions: REV, DATE, DESCRIPTION, BY), each a line and a
      half high, 560 units wide (or what room the page leaves, never less than 100) shared 50 : 100 : 330 : 80 between the four columns
    - a cell ABOVE the two together, as wide as both and as high as the Title cell (two block lines), divided into two equal halves for NOTES (left) and REFERENCE (right)

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UTitleBlock;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, UGeometry, UDrawingObjects;

const
  TB_BOX_WIDTH = 400;        // CDetails::M_NBOXWIDTH: the width of the standard block
  TB_LINE_HEIGHT = 18;       // M_NLINEHEIGHT: the standard block is 9 of these high
  TB_RULER_HEIGHT = 15;      // M_NRULERHEIGHT
  TB_TABLE_WIDTH = 560;      // the revision table's width when the page has room
  TB_TABLE_MIN = 100;        // and the least it is drawn at
  TB_ROWS = 6;               // heading and five revisions
  TB_NOTES_HEIGHT = 36;      // the height of the notes and reference cell: two block lines, the same as the Title cell
  TB_COLUMN_SHARE: array[0..3] of Integer = (50, 100, 330, 80);    // REV, DATE, DESCRIPTION, BY

type
  TExtendedLayout = record
    { the standard block (what CDetails::DisplayBox draws) }
    BlockLeft, BlockTop, BlockRight, BlockBottom: Double;
    { the revision table: the x of the five vertical edges (left edge, three dividers, right edge = the block's left) and the y of the seven horizontal ones }
    ColX: array[0..4] of Double;
    RowY: array[0..TB_ROWS] of Double;
    RowHeight: Double;
    { the notes and reference cell }
    NotesLeft, NotesTop, NotesRight, NotesBottom, NotesMid: Double;
  end;
  TStringArray = array of String;

{ the layout for a page of that size (design units), with or without the rulers }
function ExtendedLayout(PageWidth, PageHeight: Integer; HasRulers: Boolean): TExtendedLayout;
{ Text cut into lines no wider than MaxWidth (by the metrics of that font), at most MaxLines of them: lines break at the LF line ends and between words, a word that is
  wider than a line is broken, and if there is more than fits the last line ends with "...". Blank lines are kept. }
function WrapToWidth(const Text: String; MaxWidth: Double; Opts: TDocOptionsBase; FontNumber, MaxLines: Integer): TStringArray;

implementation

{ ===========================================================================
  ExtendedLayout  (function)
  Parameters:
    PageWidth: Integer - whole number
    PageHeight: Integer - whole number
    HasRulers: Boolean - flag
  Returns:
    TExtendedLayout
  Notes:
    The standard block is as CDetails::DisplayBox places it (2 units in from the page edge, and
    the width of the rulers further in when they are on). The table fills the height of the
    block, so each of its six rows is a line and a half; it is 560 wide if the page has room
    between the block and the left edge (or the inner border of the rulers), otherwise as wide
    as the room allows but at least 100. The notes cell (the height of the Title cell) stands on the block's top edge and the
    table's, and reaches to the block's right.
  =========================================================================== }
function ExtendedLayout(PageWidth, PageHeight: Integer; HasRulers: Boolean): TExtendedLayout;
var
  Room, W, Share, X: Double;
  i, Total: Integer;
begin
  Result.BlockLeft := PageWidth - TB_BOX_WIDTH - 2;
  Result.BlockTop := PageHeight - TB_LINE_HEIGHT * 9 - 2;
  Result.BlockRight := PageWidth - 2;
  Result.BlockBottom := PageHeight - 2;
  if HasRulers then
  begin
    Result.BlockLeft := Result.BlockLeft - TB_RULER_HEIGHT;
    Result.BlockTop := Result.BlockTop - TB_RULER_HEIGHT;
    Result.BlockRight := Result.BlockRight - TB_RULER_HEIGHT;
    Result.BlockBottom := Result.BlockBottom - TB_RULER_HEIGHT;
    Room := Result.BlockLeft - (TB_RULER_HEIGHT + 2);
  end
  else
    Room := Result.BlockLeft - 2;
  W := TB_TABLE_WIDTH;
  if Room < W then
    W := Room;
  if W < TB_TABLE_MIN then
    W := TB_TABLE_MIN;
  Total := 0;
  for i := 0 to 3 do Total := Total + TB_COLUMN_SHARE[i];
  X := Result.BlockLeft - W;
  Result.ColX[0] := X;
  Share := 0;
  for i := 0 to 3 do
  begin
    Share := Share + TB_COLUMN_SHARE[i];
    Result.ColX[i + 1] := X + W * Share / Total;
  end;
  Result.ColX[4] := Result.BlockLeft;                  // (exactly the block's left edge, whatever the rounding)
  Result.RowHeight := (Result.BlockBottom - Result.BlockTop) / TB_ROWS;
  for i := 0 to TB_ROWS do Result.RowY[i] := Result.BlockTop + Result.RowHeight * i;
  Result.NotesLeft := Result.ColX[0];
  Result.NotesRight := Result.BlockRight;
  Result.NotesBottom := Result.BlockTop;
  Result.NotesTop := Result.BlockTop - TB_NOTES_HEIGHT;
  Result.NotesMid := (Result.NotesLeft + Result.NotesRight) / 2;
end;

{ ===========================================================================
  WrapToWidth  (function)
  Parameters:
    const Text: String - the text
    MaxWidth: Double - number
    Opts: TDocOptionsBase - the sheet options
    FontNumber: Integer - whole number
    MaxLines: Integer - whole number
  Returns:
    TStringArray
  Notes:
    Each line of the text is filled word by word; spaces where a line breaks are dropped, blank
    lines are kept, and a word wider than MaxWidth is cut where it no longer fits. When there is
    more text than room the last line is shortened and ends with "..." so it can be seen that
    something was left out.
  =========================================================================== }
function WrapToWidth(const Text: String; MaxWidth: Double; Opts: TDocOptionsBase; FontNumber, MaxLines: Integer): TStringArray;
var
  Lines: array of String;
  Paras: TStringArray;
  P, W, Cur, Cand: String;
  i, k, n, Start: Integer;
  procedure Emit(const S: String);
  begin
    SetLength(Lines, Length(Lines) + 1);
    Lines[High(Lines)] := S;
  end;
  function Wide(const S: String): Double;
  begin
    if S = '' then
      Result := 0
    else
      Result := Opts.TextExtent(S, FontNumber).cx;
  end;
begin
  SetLength(Result, 0);
  if MaxLines <= 0 then
    Exit;
  { the paragraphs, at the LF line ends }
  n := 0; Start := 1;
  SetLength(Paras, 0);
  P := StringReplace(Text, #13, '', [rfReplaceAll]);
  for i := 1 to Length(P) + 1 do
    if (i > Length(P)) or (P[i] = #10) then
    begin
      SetLength(Paras, n + 1);
      Paras[n] := Copy(P, Start, i - Start);
      Inc(n);
      Start := i + 1;
    end;
  if (Length(Paras) = 1) and (Paras[0] = '') then
    Exit;
  for k := 0 to High(Paras) do
  begin
    P := Paras[k];
    if Trim(P) = '' then begin
      Emit('');
      Continue;
    end;
    Cur := '';
    i := 1;
    while i <= Length(P) do
    begin
      { the next word, with the spaces before it }
      while (i <= Length(P)) and (P[i] = ' ') do Inc(i);
      if i > Length(P) then
        Break;
      W := '';
      while (i <= Length(P)) and (P[i] <> ' ') do begin
        W := W + P[i];
        Inc(i);
      end;
      if Cur = '' then
        Cand := W
      else
        Cand := Cur + ' ' + W;
      if Wide(Cand) <= MaxWidth then
        Cur := Cand
      else
      begin
        if Cur <> '' then begin
          Emit(Cur);
          Cur := '';
        end;
        { a word on its own: cut it where it stops fitting }
        while (W <> '') and (Wide(W) > MaxWidth) do
        begin
          n := Length(W);
          while (n > 1) and (Wide(Copy(W, 1, n)) > MaxWidth) do Dec(n);
          Emit(Copy(W, 1, n));
          W := Copy(W, n + 1, MaxInt);
        end;
        Cur := W;
      end;
    end;
    if Cur <> '' then
      Emit(Cur);
  end;
  if Length(Lines) > MaxLines then
  begin
    SetLength(Lines, MaxLines);
    { the last line gives up its end to say there is more }
    Cur := Lines[MaxLines - 1];
    while (Cur <> '') and (Wide(Cur + '...') > MaxWidth) do SetLength(Cur, Length(Cur) - 1);
    Lines[MaxLines - 1] := Cur + '...';
  end;
  SetLength(Result, Length(Lines));
  for i := 0 to High(Lines) do Result[i] := Lines[i];
end;

end.
