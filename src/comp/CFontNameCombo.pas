{ CFontNameCombo - a drop-down list of the fonts installed on the computer, each name drawn in its own typeface.
    - FontName: the font chosen (read and set it by name; a name that is not installed, as in a design made on another computer, is added to the list so that the box shows it);
    - it is a list to choose from (the box is not typed into): typing chooses the font whose name starts with what was typed; a key pressed within a second of the one before adds to it
      (C, O, U finds "Cou..." - Courier New), a key after a longer pause starts again with that key alone;
    - ShowSample: draw each name in its own typeface (the default); False gives a plain list;
    - SampleSize: the size, in points, the names are drawn at (the height of the rows follows it).
  The list is made when the box is first shown (Screen.Fonts, without the names that start with @, the vertical fonts of Windows) and RefreshFonts makes it again.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit CFontNameCombo;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, StdCtrls, LCLType, LResources, Forms;

type
  { TFontNameCombo }

  TFontNameCombo = class(TComboBox)
  private
    FShowSample: Boolean;
    FSampleSize: Integer;
    FLoaded: Boolean;
    FTyped: String;            // what has been typed for the search
    FTypedAt: QWord;           // when the last key was typed (GetTickCount64)
    function GetFontName: String;
    procedure SetFontName(const AValue: String);
    procedure SetShowSample(AValue: Boolean);
    procedure SetSampleSize(AValue: Integer);
    procedure FitRows;
  protected
    procedure DrawItem(Index: Integer; ARect: TRect; State: TOwnerDrawState); override;
    procedure Loaded; override;
    procedure KeyPress(var Key: Char); override;
  public
    constructor Create(AOwner: TComponent); override;
    { lists the installed fonts again }
    procedure RefreshFonts;
    { type-ahead: a letter typed at time Ticks (milliseconds); chooses the font that starts with the letters typed within the second before }
    function TypeAhead(C: Char; Ticks: QWord): Boolean;
  published
    property FontName: String read GetFontName write SetFontName;
    property ShowSample: Boolean read FShowSample write SetShowSample default True;
    property SampleSize: Integer read FSampleSize write SetSampleSize default 11;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Additional', [TFontNameCombo]);
end;

{ ===========================================================================
  TFontNameCombo.Create  (constructor)
  Notes:
    An owner drawn, fixed height list (csOwnerDrawFixed), listing the fonts at once (so the box also works when it is made in code).
  =========================================================================== }
constructor TFontNameCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowSample := True;
  FSampleSize := 11;
  Style := csOwnerDrawFixed;
  if not (csDesigning in ComponentState) then
    RefreshFonts;
  FitRows;
end;

procedure TFontNameCombo.Loaded;
begin
  inherited Loaded;
  FLoaded := True;
  if not (csDesigning in ComponentState) and (Items.Count = 0) then
    RefreshFonts;
end;

{ ===========================================================================
  TFontNameCombo.TypeAhead  (function)
  Parameters:
    C: Char - the character typed
    Ticks: QWord - the time it was typed, in milliseconds
  Returns:
    Boolean - True if a font was chosen
  Notes:
    The search of the old font drop-downs: a character typed within 1000 ms of the one before is
    added to what was typed (C, O, U look for "COU"), a character after a longer pause is searched
    for alone. The first font whose name starts with the letters typed (any case) is chosen. If
    none does, the new character is tried alone; if that finds nothing the choice stays as it was.
    Characters that are not printable (Esc, Enter, Backspace ...) are not searched for.
  =========================================================================== }
function TFontNameCombo.TypeAhead(C: Char; Ticks: QWord): Boolean;
  function Find(const Prefix: String): Integer;
  var
    i: Integer;
  begin
    for i := 0 to Items.Count - 1 do
      if SameText(Copy(Items[i], 1, Length(Prefix)), Prefix) then
        Exit(i);
    Result := -1;
  end;
var
  At: Integer;
begin
  Result := False;
  if C < ' ' then
    Exit;
  if (FTyped <> '') and (Ticks >= FTypedAt) and (Ticks - FTypedAt <= 1000) then
    FTyped := FTyped + C
  else
    FTyped := C;
  FTypedAt := Ticks;
  At := Find(FTyped);
  if (At < 0) and (Length(FTyped) > 1) then
  begin
    FTyped := C;
    At := Find(FTyped);
  end;
  if At < 0 then
    Exit;
  Result := True;
  if ItemIndex <> At then
  begin
    ItemIndex := At;
    Change;
    Select;
  end;
end;

{ ===========================================================================
  TFontNameCombo.KeyPress  (procedure)
  Parameters:
    var Key: Char - the key (set to #0 when it was used)
  Notes:
    Printable keys go to TypeAhead with the time now; the box has no text to type into.
  =========================================================================== }
procedure TFontNameCombo.KeyPress(var Key: Char);
begin
  inherited KeyPress(Key);
  if (Key >= ' ') and TypeAhead(Key, GetTickCount64) then
    Key := #0;
end;

{ ===========================================================================
  TFontNameCombo.RefreshFonts  (procedure)
  Notes:
    Lists the fonts of the screen, sorted, without the names that start with @ (the Windows fonts for text written downwards). The font chosen stays chosen when it is still there.
  =========================================================================== }
procedure TFontNameCombo.RefreshFonts;
var
  Keep: String;
  L: TStringList;
  i: Integer;
begin
  Keep := GetFontName;
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.Duplicates := dupIgnore;
    L.CaseSensitive := False;
    for i := 0 to Screen.Fonts.Count - 1 do
      if (Screen.Fonts[i] <> '') and (Screen.Fonts[i][1] <> '@') then
        L.Add(Screen.Fonts[i]);
    Items.Assign(L);
  finally
    L.Free;
  end;
  SetFontName(Keep);
end;

{ ===========================================================================
  TFontNameCombo.FitRows  (procedure)
  Notes:
    The rows are as high as a line of text at SampleSize points, measured on a bitmap (the box's own canvas needs a window, which the box has not got until it is shown).
  =========================================================================== }
procedure TFontNameCombo.FitRows;
var
  B: TBitmap;
begin
  if not FShowSample then
    Exit;
  B := TBitmap.Create;
  try
    B.Canvas.Font.Assign(Font);
    B.Canvas.Font.Size := FSampleSize;
    ItemHeight := B.Canvas.TextHeight('Ag') + 6;
  finally
    B.Free;
  end;
end;

function TFontNameCombo.GetFontName: String;
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    Result := Items[ItemIndex]
  else
    Result := Text;
end;

{ ===========================================================================
  TFontNameCombo.SetFontName  (procedure)
  Parameters:
    const AValue: String - the name of a font
  Notes:
    Chooses the font in the list (any case); a name that is not listed (a font the computer has not got) is added to the list, so the box can show it and a design keeps its font.
  =========================================================================== }
procedure TFontNameCombo.SetFontName(const AValue: String);
var
  i: Integer;
begin
  i := Items.IndexOf(AValue);
  if i >= 0 then
    ItemIndex := i
  else if AValue <> '' then
    ItemIndex := Items.Add(AValue)
  else
    ItemIndex := -1;
end;

procedure TFontNameCombo.SetShowSample(AValue: Boolean);
begin
  if FShowSample = AValue then
    Exit;
  FShowSample := AValue;
  if FShowSample then
    Style := csOwnerDrawFixed
  else
    Style := csDropDownList;
  FitRows;
  Invalidate;
end;

procedure TFontNameCombo.SetSampleSize(AValue: Integer);
begin
  if (AValue < 6) or (AValue = FSampleSize) then
    Exit;
  FSampleSize := AValue;
  FitRows;
  Invalidate;
end;

{ ===========================================================================
  TFontNameCombo.DrawItem  (procedure)
  Parameters:
    Index: Integer - the row
    ARect: TRect - where it is
    State: TOwnerDrawState
  Notes:
    The font's name in the font itself, at SampleSize points, centred up and down in the row; the selected row is drawn in the highlight colors.
  =========================================================================== }
procedure TFontNameCombo.DrawItem(Index: Integer; ARect: TRect; State: TOwnerDrawState);
var
  S: String;
begin
  if not FShowSample then
  begin
    inherited DrawItem(Index, ARect, State);
    Exit;
  end;
  if odSelected in State then
  begin
    Canvas.Brush.Color := clHighlight;
    Canvas.Font.Color := clHighlightText;
  end
  else
  begin
    Canvas.Brush.Color := clWindow;
    Canvas.Font.Color := clWindowText;
  end;
  Canvas.FillRect(ARect);
  if (Index < 0) or (Index >= Items.Count) then
    Exit;
  S := Items[Index];
  Canvas.Font.Name := S;
  Canvas.Font.Size := FSampleSize;
  Canvas.TextOut(ARect.Left + 4, ARect.Top + (ARect.Bottom - ARect.Top - Canvas.TextHeight(S)) div 2, S);
end;

initialization
  RegisterClass(TFontNameCombo);      { (so a form file that names it can be read where the package's Register is not run) }

end.
