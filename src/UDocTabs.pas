unit UDocTabs;

{ The strip of tabs above the open documents: one tab for each document with its name, a close glyph on the right and a mark for unsaved changes. It is drawn by the
  program (the system tab control cannot show a close button on every system), so it looks and behaves the same everywhere and the test display can click on it.

  The pictures come from an image list (frmSharedControls.ilDocTabs, 18 x 18): 0 the close glyph, 1 the close glyph with the pointer over it, 2 the document has unsaved
  changes. A tab shows the close glyph; a tab whose document has unsaved changes shows the mark instead until the pointer is over the tab (then the close glyph, and
  the pointer-over picture while it is on the glyph, drawn one pixel down and right while the mouse button is held on it). There is no picture for "pressed".

  Clicking a tab makes it current (OnChange); clicking the glyph (button down and up on it) asks for the tab to be closed (OnTabClose, the owner closes it; the strip
  only reports); a middle click on a tab does the same; a right click makes the tab current before the pop-up menu shows. When the tabs are wider than the strip two
  arrows appear at its right end and the tabs scroll (the arrows, the mouse wheel, and the current tab is always brought into view).

  Licence: LGPL 2.1 or later, as the rest of this port. }

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ImgList, Types, Math, LCLType, LMessages, consts;

type
  TDocTabEvent = procedure(Sender: TObject; Index: Integer) of object;

  { what is at a point of the strip }
  TDocTabHit = (dthNone, dthTab, dthClose, dthArrowLeft, dthArrowRight);

  { TDocTabStrip }

  TDocTabStrip = class(TCustomControl)
  private
    FNames: array of String;
    FModified: array of Boolean;
    FLeft: array of Integer;           // where each tab starts when nothing is scrolled
    FWidths: array of Integer;
    FTotal: Integer;                   // the width of all the tabs
    FTabIndex: Integer;
    FHotTab: Integer;
    FHotClose: Boolean;
    FPressedClose: Integer;            // the tab whose close glyph the left button is held on, -1 for none
    FMiddleTab: Integer;               // the tab the middle button went down on
    FScroll: Integer;
    FImages: TCustomImageList;
    FMeasure: TBitmap;                 // for measuring names without a window
    FOnChange: TNotifyEvent;
    FOnTabClose: TDocTabEvent;
    function GetTabCount: Integer;
    procedure SetTabCount(AValue: Integer);
    procedure SetTabIndex(AValue: Integer);
    procedure SetImages(AValue: TCustomImageList);
    function GlyphSize: Integer;
    function TabsRight: Integer;
    procedure Relayout;
    procedure ClampScroll;
    procedure SetHot(ATab: Integer; AClose: Boolean);
    procedure ScrollTabs(ADelta: Integer);
    procedure DrawGlyph(C: TCanvas; AIndex: Integer; X, Y: Integer);
    function Blend(A, B: TColor; PercentOfB: Integer): TColor;
    function IsPressed(Index: Integer): Boolean;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseLeave; override;
    procedure CMFontChanged(var Message: TLMessage); message CM_FONTCHANGED;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    { sets what tab Index shows (the tab is made when Index is past the end of the list) }
    procedure SetTab(Index: Integer; const AName: String; AModified: Boolean);
    function TabName(Index: Integer): String;
    function TabModified(Index: Integer): Boolean;
    { where a tab is in the strip, scrolling included (may lie partly or wholly out of view); empty for a tab that is not there }
    function TabRect(Index: Integer): TRect;
    { the square the close glyph is drawn in }
    function CloseRect(Index: Integer): TRect;
    { the two scroll arrows (empty while the tabs all fit) }
    function ArrowRect(ALeft: Boolean): TRect;
    function ArrowsShown: Boolean;
    function HitTest(X, Y: Integer; out Index: Integer): TDocTabHit;
    { the tab at a point, -1 for none }
    function IndexOfTabAt(X, Y: Integer): Integer;
    { which of the pictures a tab shows: 0 close glyph, 1 pointer over it, 2 unsaved changes }
    function GlyphIndexFor(Index: Integer): Integer;
    { draws the whole strip on a canvas (Paint does this; tests draw it on a bitmap) }
    procedure DrawStrip(C: TCanvas; AWidth, AHeight: Integer);
    { one turn of the mouse wheel: scrolls the tabs by DocTabScrollStep (positive: away from the user, towards the left) }
    procedure Wheel(WheelDelta: Integer);
    { moves the tabs so a tab is in view }
    procedure EnsureVisible(Index: Integer);
    property TabCount: Integer read GetTabCount write SetTabCount;
    property TabIndex: Integer read FTabIndex write SetTabIndex;
    property Images: TCustomImageList read FImages write SetImages;
    property HotTab: Integer read FHotTab;
    property HotOnClose: Boolean read FHotClose;
    property PressedClose: Integer read FPressedClose;
    property Scroll: Integer read FScroll;
    property TotalWidth: Integer read FTotal;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnTabClose: TDocTabEvent read FOnTabClose write FOnTabClose;
  end;

implementation

{ ===========================================================================
  TDocTabStrip.Create  (constructor)
  Parameters:
    AOwner: TComponent
  Notes:
    An empty strip, two pixels taller than the tabs, with no current tab.
  =========================================================================== }
constructor TDocTabStrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FTabIndex := -1;
  FHotTab := -1;
  FPressedClose := -1;
  FMiddleTab := -1;
  FMeasure := TBitmap.Create;
  FMeasure.SetSize(8, 8);
  Height := DocTabHeight + 2;
  Constraints.MinHeight := DocTabHeight + 2;
  Constraints.MaxHeight := DocTabHeight + 2;
  Width := 400;
  DoubleBuffered := True;
end;

{ ===========================================================================
  TDocTabStrip.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the bitmap names are measured on.
  =========================================================================== }
destructor TDocTabStrip.Destroy;
begin
  FMeasure.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TDocTabStrip.GetTabCount  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    Number of tabs.
  =========================================================================== }
function TDocTabStrip.GetTabCount: Integer;
begin
  Result := Length(FNames);
end;

{ ===========================================================================
  TDocTabStrip.SetTabCount  (procedure)
  Parameters:
    AValue: Integer - the value
  Notes:
    Makes the list shorter (the current tab is kept in range) or longer (new tabs have no name
    and no unsaved changes).
  =========================================================================== }
procedure TDocTabStrip.SetTabCount(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  if AValue = Length(FNames) then
    Exit;
  SetLength(FNames, AValue);
  SetLength(FModified, AValue);
  if FTabIndex >= AValue then
    FTabIndex := AValue - 1;
  if FHotTab >= AValue then
    SetHot(-1, False);
  if FPressedClose >= AValue then
    FPressedClose := -1;
  Relayout;
end;

{ ===========================================================================
  TDocTabStrip.SetTab  (procedure)
  Parameters:
    Index: Integer - zero-based index
    const AName: String - the name
    AModified: Boolean - flag
  Notes:
    Sets what a tab shows; the strip is only drawn again when something changed.
  =========================================================================== }
procedure TDocTabStrip.SetTab(Index: Integer; const AName: String; AModified: Boolean);
begin
  if Index < 0 then
    Exit;
  if Index >= Length(FNames) then
    SetTabCount(Index + 1);
  if (FNames[Index] = AName) and (FModified[Index] = AModified) then
    Exit;
  FNames[Index] := AName;
  FModified[Index] := AModified;
  Relayout;
end;

{ ===========================================================================
  TDocTabStrip.TabName  (function)
  Parameters:
    Index: Integer - zero-based index
  Returns:
    String
  Notes:
    The name a tab shows.
  =========================================================================== }
function TDocTabStrip.TabName(Index: Integer): String;
begin
  if (Index >= 0) and (Index < Length(FNames)) then
    Result := FNames[Index]
  else
    Result := '';
end;

{ ===========================================================================
  TDocTabStrip.TabModified  (function)
  Parameters:
    Index: Integer - zero-based index
  Returns:
    Boolean
  Notes:
    The unsaved-changes flag of a tab (False for no such tab).
  =========================================================================== }
function TDocTabStrip.TabModified(Index: Integer): Boolean;
begin
  Result := (Index >= 0) and (Index < Length(FModified)) and FModified[Index];
end;

{ ===========================================================================
  TDocTabStrip.SetTabIndex  (procedure)
  Parameters:
    AValue: Integer - the value
  Notes:
    Makes a tab current and brings it into view. OnChange is not called: it tells that a person
    chose a tab.
  =========================================================================== }
procedure TDocTabStrip.SetTabIndex(AValue: Integer);
begin
  if AValue >= Length(FNames) then
    AValue := Length(FNames) - 1;
  if AValue < -1 then
    AValue := -1;
  if AValue = FTabIndex then
    Exit;
  FTabIndex := AValue;
  EnsureVisible(AValue);
  Invalidate;
end;

{ ===========================================================================
  TDocTabStrip.SetImages  (procedure)
  Parameters:
    AValue: TCustomImageList - the value
  Notes:
    Sets the pictures and measures the tabs again, as the glyph's size decides their width.
  =========================================================================== }
procedure TDocTabStrip.SetImages(AValue: TCustomImageList);
begin
  FImages := AValue;
  Relayout;
end;

{ ===========================================================================
  TDocTabStrip.GlyphSize  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    The size of the pictures, 18 pixels when there are none.
  =========================================================================== }
function TDocTabStrip.GlyphSize: Integer;
begin
  if (FImages <> nil) and (FImages.Width > 0) then
    Result := FImages.Width
  else
    Result := 18;
end;

{ ===========================================================================
  TDocTabStrip.ArrowsShown  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    Whether the tabs scroll.
  =========================================================================== }
function TDocTabStrip.ArrowsShown: Boolean;
begin
  Result := FTotal > Width;
end;

{ ===========================================================================
  TDocTabStrip.TabsRight  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    The right edge of the room the tabs have.
  =========================================================================== }
function TDocTabStrip.TabsRight: Integer;
begin
  if ArrowsShown then
    Result := Width - 2 * DocTabArrowWidth
  else
    Result := Width;
end;

{ ===========================================================================
  TDocTabStrip.Relayout  (procedure)
  Parameters:  none
  Notes:
    Measures every name and works out where each tab starts and how wide it is: the name, the
    gap and the glyph with the padding round them, never narrower than DocTabMinWidth or wider
    than DocTabMaxWidth. The scroll is kept in range and the strip is drawn again.
  =========================================================================== }
procedure TDocTabStrip.Relayout;
var
  i, W, X: Integer;
begin
  FMeasure.Canvas.Font.Assign(Font);
  SetLength(FLeft, Length(FNames));
  SetLength(FWidths, Length(FNames));
  X := 0;
  for i := 0 to High(FNames) do
  begin
    W := DocTabPadLeft + FMeasure.Canvas.TextWidth(FNames[i]) + DocTabGap + GlyphSize + DocTabPadRight;
    W := Max(DocTabMinWidth, Min(DocTabMaxWidth, W));
    FLeft[i] := X;
    FWidths[i] := W;
    Inc(X, W);
  end;
  FTotal := X;
  ClampScroll;
  EnsureVisible(FTabIndex);
  Invalidate;
end;

{ ===========================================================================
  TDocTabStrip.ClampScroll  (procedure)
  Parameters:  none
  Notes:
    Keeps the scroll between 0 and the most that shows the last tab at the right edge.
  =========================================================================== }
procedure TDocTabStrip.ClampScroll;
begin
  if not ArrowsShown then
    FScroll := 0
  else
    FScroll := Max(0, Min(FScroll, FTotal - TabsRight));
end;

{ ===========================================================================
  TDocTabStrip.ScrollTabs  (procedure)
  Parameters:
    ADelta: Integer - whole number
  Notes:
    Scrolls the tabs, within their limits.
  =========================================================================== }
procedure TDocTabStrip.ScrollTabs(ADelta: Integer);
var
  Was: Integer;
begin
  Was := FScroll;
  FScroll := FScroll + ADelta;
  ClampScroll;
  if FScroll <> Was then
    Invalidate;
end;

{ ===========================================================================
  TDocTabStrip.EnsureVisible  (procedure)
  Parameters:
    Index: Integer - zero-based index
  Notes:
    Scrolls just far enough for the whole tab to be in view (a tab wider than the room shows its
    left end).
  =========================================================================== }
procedure TDocTabStrip.EnsureVisible(Index: Integer);
var
  Was: Integer;
begin
  if (Index < 0) or (Index >= Length(FLeft)) or (not ArrowsShown) then
    Exit;
  Was := FScroll;
  if FLeft[Index] < FScroll then
    FScroll := FLeft[Index]
  else if FLeft[Index] + FWidths[Index] > FScroll + TabsRight then
    FScroll := FLeft[Index] + FWidths[Index] - TabsRight;
  ClampScroll;
  if FScroll <> Was then
    Invalidate;
end;

{ ===========================================================================
  TDocTabStrip.TabRect  (function)
  Parameters:
    Index: Integer - zero-based index
  Returns:
    TRect
  Notes:
    The tabs stand on the bottom of the strip, DocTabHeight high. A tab that is not there gives
    an empty rectangle.
  =========================================================================== }
function TDocTabStrip.TabRect(Index: Integer): TRect;
begin
  if (Index < 0) or (Index >= Length(FLeft)) then
    Exit(Rect(0, 0, 0, 0));
  Result := Rect(FLeft[Index] - FScroll, Height - DocTabHeight, FLeft[Index] - FScroll + FWidths[Index], Height);
end;

{ ===========================================================================
  TDocTabStrip.CloseRect  (function)
  Parameters:
    Index: Integer - zero-based index
  Returns:
    TRect
  Notes:
    At the right end of the tab (DocTabPadRight from its edge), centred up and down.
  =========================================================================== }
function TDocTabStrip.CloseRect(Index: Integer): TRect;
var
  T: TRect;
  G: Integer;
begin
  T := TabRect(Index);
  if T.Right <= T.Left then
    Exit(Rect(0, 0, 0, 0));
  G := GlyphSize;
  Result := Rect(T.Right - DocTabPadRight - G, T.Top + (DocTabHeight - G) div 2, T.Right - DocTabPadRight, T.Top + (DocTabHeight - G) div 2 + G);
end;

{ ===========================================================================
  TDocTabStrip.ArrowRect  (function)
  Parameters:
    ALeft: Boolean - flag
  Returns:
    TRect
  Notes:
    The two arrows sit side by side at the right end of the strip, DocTabArrowWidth wide each.
  =========================================================================== }
function TDocTabStrip.ArrowRect(ALeft: Boolean): TRect;
begin
  if not ArrowsShown then
    Exit(Rect(0, 0, 0, 0));
  if ALeft then
    Result := Rect(Width - 2 * DocTabArrowWidth, Height - DocTabHeight, Width - DocTabArrowWidth, Height)
  else
    Result := Rect(Width - DocTabArrowWidth, Height - DocTabHeight, Width, Height);
end;

{ ===========================================================================
  TDocTabStrip.HitTest  (function)
  Parameters:
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
    out Index: Integer - zero-based index (out: set by the call)
  Returns:
    TDocTabHit
  Notes:
    The close glyph counts first, then the rest of the tab. Part of a tab hidden behind the
    arrows or past the strip's end is not hit, and the 2-pixel gap above the tabs is no tab.
  =========================================================================== }
function TDocTabStrip.HitTest(X, Y: Integer; out Index: Integer): TDocTabHit;
var
  i: Integer;
  P: TPoint;
begin
  Index := -1;
  Result := dthNone;
  P := Point(X, Y);
  if ArrowsShown then
  begin
    if PtInRect(ArrowRect(True), P) then
      Exit(dthArrowLeft);
    if PtInRect(ArrowRect(False), P) then
      Exit(dthArrowRight);
  end;
  if (X < 0) or (X >= TabsRight) or (Y < Height - DocTabHeight) or (Y >= Height) then
    Exit;
  for i := 0 to High(FLeft) do
    if PtInRect(TabRect(i), P) then
    begin
      Index := i;
      if PtInRect(CloseRect(i), P) then
        Exit(dthClose);
      Exit(dthTab);
    end;
end;

{ ===========================================================================
  TDocTabStrip.IndexOfTabAt  (function)
  Parameters:
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
  Returns:
    Integer
  Notes:
    Which tab a point is on (its glyph included).
  =========================================================================== }
function TDocTabStrip.IndexOfTabAt(X, Y: Integer): Integer;
var
  Hit: TDocTabHit;
begin
  Hit := HitTest(X, Y, Result);
  if not (Hit in [dthTab, dthClose]) then
    Result := -1;
end;

{ ===========================================================================
  TDocTabStrip.GlyphIndexFor  (function)
  Parameters:
    Index: Integer - zero-based index
  Returns:
    Integer
  Notes:
    What a tab shows at the right end: while the pointer is over the tab the glyph, which is the
    pointer-over picture when the pointer is on it; otherwise the mark when the document has
    unsaved changes, else the glyph. While the mouse button is held on a glyph it is the
    pointer-over picture (drawn one pixel down and right) only while the pointer is still on
    that glyph; moved off it, the tab shows what it shows with no button held, and moved back on
    it is pressed again.
  =========================================================================== }
function TDocTabStrip.GlyphIndexFor(Index: Integer): Integer;
begin
  Result := 0;
  if IsPressed(Index) then
    Result := 1
  else if Index = FHotTab then
  begin
    if FHotClose then
      Result := 1;
  end
  else if TabModified(Index) then
    Result := 2;
end;

{ ===========================================================================
  TDocTabStrip.IsPressed  (function)
  Parameters:
    Index: Integer - zero-based index
  Returns:
    Boolean
  Notes:
    The state that draws the glyph pressed. It ends as the pointer leaves the glyph (the button
    may still be held) and starts again if the pointer comes back while the button is still
    held.
  =========================================================================== }
function TDocTabStrip.IsPressed(Index: Integer): Boolean;
begin
  Result := (Index >= 0) and (Index = FPressedClose) and (Index = FHotTab) and FHotClose;
end;

{ ===========================================================================
  TDocTabStrip.SetHot  (procedure)
  Parameters:
    ATab: Integer - whole number
    AClose: Boolean - flag
  Notes:
    Remembers where the pointer is and draws the strip again if that changed what is shown.
  =========================================================================== }
procedure TDocTabStrip.SetHot(ATab: Integer; AClose: Boolean);
begin
  if (ATab = FHotTab) and (AClose = FHotClose) then
    Exit;
  FHotTab := ATab;
  FHotClose := AClose;
  Invalidate;
end;

{ ===========================================================================
  TDocTabStrip.MouseMove  (procedure)
  Parameters:
    Shift: TShiftState - modifier keys held down
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
  Notes:
    Follows the pointer: which tab it is on and whether it is on the close glyph (while the left
    button is held on a glyph the glyph stays pressed, and the tab is marked as under the
    pointer only while the pointer is still on it).
  =========================================================================== }
procedure TDocTabStrip.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  Hit: TDocTabHit;
begin
  inherited MouseMove(Shift, X, Y);
  Hit := HitTest(X, Y, I);
  if Hit in [dthTab, dthClose] then
    SetHot(I, Hit = dthClose)
  else
    SetHot(-1, False);
end;

{ ===========================================================================
  TDocTabStrip.MouseLeave  (procedure)
  Parameters:  none
  Notes:
    The pointer left the strip: nothing is under it any more.
  =========================================================================== }
procedure TDocTabStrip.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1, False);
end;

{ ===========================================================================
  TDocTabStrip.MouseDown  (procedure)
  Parameters:
    Button: TMouseButton - which mouse button
    Shift: TShiftState - modifier keys held down
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
  Notes:
    Left on a glyph holds the glyph pressed (the tab is closed when the button is let go on it);
    left on a tab makes it current; left on an arrow scrolls. Right on a tab makes it current
    (so the pop-up menu is about it). Middle on a tab is remembered for the button being let go.
  =========================================================================== }
procedure TDocTabStrip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  Hit: TDocTabHit;
begin
  inherited MouseDown(Button, Shift, X, Y);
  Hit := HitTest(X, Y, I);
  if Hit in [dthTab, dthClose] then
    SetHot(I, Hit = dthClose)
  else
    SetHot(-1, False);
  case Button of
    mbLeft:
      case Hit of
        dthClose:
          begin
            FPressedClose := I;
            Invalidate;
          end;
        dthTab:
          begin
            if I <> FTabIndex then
            begin
              SetTabIndex(I);
              if Assigned(FOnChange) then
                FOnChange(Self);
            end;
          end;
        dthArrowLeft:
          ScrollTabs(-DocTabScrollStep);
        dthArrowRight:
          ScrollTabs(DocTabScrollStep);
      end;
    mbRight:
      if (Hit in [dthTab, dthClose]) and (I <> FTabIndex) then
      begin
        SetTabIndex(I);
        if Assigned(FOnChange) then
          FOnChange(Self);
      end;
    mbMiddle:
      if Hit in [dthTab, dthClose] then
        FMiddleTab := I;
  end;
end;

{ ===========================================================================
  TDocTabStrip.MouseUp  (procedure)
  Parameters:
    Button: TMouseButton - which mouse button
    Shift: TShiftState - modifier keys held down
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
  Notes:
    Left let go on the glyph it went down on, or middle let go on the tab it went down on, asks
    for that tab to be closed (OnTabClose). Let go anywhere else, the press is dropped.
  =========================================================================== }
procedure TDocTabStrip.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I, Was: Integer;
  Hit: TDocTabHit;
begin
  inherited MouseUp(Button, Shift, X, Y);
  Hit := HitTest(X, Y, I);
  if Button = mbLeft then
  begin
    Was := FPressedClose;
    FPressedClose := -1;
    Invalidate;
    if (Was >= 0) and (Hit = dthClose) and (I = Was) and Assigned(FOnTabClose) then
      FOnTabClose(Self, Was);
  end
  else if Button = mbMiddle then
  begin
    Was := FMiddleTab;
    FMiddleTab := -1;
    if (Was >= 0) and (Hit in [dthTab, dthClose]) and (I = Was) and Assigned(FOnTabClose) then
      FOnTabClose(Self, Was);
  end;
end;

{ ===========================================================================
  TDocTabStrip.DoMouseWheel  (function)
  Parameters:
    Shift: TShiftState - modifier keys held down
    WheelDelta: Integer - whole number
    MousePos: TPoint
  Returns:
    Boolean
  Notes:
    Turning the wheel over the strip scrolls the tabs by DocTabScrollStep a notch (towards the
    left for a turn away).
  =========================================================================== }
function TDocTabStrip.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := ArrowsShown;
  if Result then
    Wheel(WheelDelta);
end;

{ ===========================================================================
  TDocTabStrip.Wheel  (procedure)
  Parameters:
    WheelDelta: Integer - whole number
  Notes:
    Scrolls the tabs one step for a turn of either sign (positive towards the left, as a
    document would scroll up); nothing when the tabs all fit.
  =========================================================================== }
procedure TDocTabStrip.Wheel(WheelDelta: Integer);
begin
  if ArrowsShown then
    ScrollTabs(-Sign(WheelDelta) * DocTabScrollStep);
end;

{ ===========================================================================
  TDocTabStrip.Resize  (procedure)
  Parameters:  none
  Notes:
    The room for the tabs changed: the arrows may appear or go, and the current tab is brought
    into view.
  =========================================================================== }
procedure TDocTabStrip.Resize;
begin
  inherited Resize;
  ClampScroll;
  EnsureVisible(FTabIndex);
  Invalidate;
end;

{ ===========================================================================
  TDocTabStrip.CMFontChanged  (procedure)
  Parameters:
    var Message: TLMessage - in/out: changed by the call
  Notes:
    A new font changes the width of the names.
  =========================================================================== }
procedure TDocTabStrip.CMFontChanged(var Message: TLMessage);
begin
  inherited;
  Relayout;
end;

{ ===========================================================================
  TDocTabStrip.Blend  (function)
  Parameters:
    A: TColor - a point, in design units
    B: TColor - a point, in design units
    PercentOfB: Integer - whole number
  Returns:
    TColor
  Notes:
    Mixes two colours (system colours are turned into RGB first).
  =========================================================================== }
function TDocTabStrip.Blend(A, B: TColor; PercentOfB: Integer): TColor;
var
  RA, RB: LongInt;
  function Mix(CA, CB: Integer): Integer;
  begin
    Result := (CA * (100 - PercentOfB) + CB * PercentOfB) div 100;
  end;
begin
  RA := ColorToRGB(A);
  RB := ColorToRGB(B);
  Result := RGBToColor(Mix(Red(RA), Red(RB)), Mix(Green(RA), Green(RB)), Mix(Blue(RA), Blue(RB)));
end;

{ ===========================================================================
  TDocTabStrip.DrawGlyph  (procedure)
  Parameters:
    C: TCanvas
    AIndex: Integer - whole number
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
  Notes:
    Draws the picture from the image list; with no list (or too short a list) draws a plain
    cross, a red cross while the pointer is over it, or a small dot.
  =========================================================================== }
procedure TDocTabStrip.DrawGlyph(C: TCanvas; AIndex: Integer; X, Y: Integer);
var
  G: Integer;
begin
  if (FImages <> nil) and (AIndex < FImages.Count) then
  begin
    FImages.Draw(C, X, Y, AIndex);
    Exit;
  end;
  G := GlyphSize;
  case AIndex of
    2:
      begin
        C.Brush.Color := clGray;
        C.Pen.Color := clGray;
        C.Ellipse(X + G div 2 - 3, Y + G div 2 - 3, X + G div 2 + 4, Y + G div 2 + 4);
      end;
  else
    begin
      if AIndex = 1 then
        C.Pen.Color := clRed
      else
        C.Pen.Color := clGray;
      C.Pen.Width := 2;
      C.Line(X + 5, Y + 5, X + G - 5, Y + G - 5);
      C.Line(X + G - 6, Y + 5, X + 4, Y + G - 5);
      C.Pen.Width := 1;
    end;
  end;
end;

{ ===========================================================================
  TDocTabStrip.DrawStrip  (procedure)
  Parameters:
    C: TCanvas
    AWidth: Integer - whole number
    AHeight: Integer - whole number
  Notes:
    The face colour behind, the tabs (the current one in the window colour with a line of the
    highlight colour along its top and no line under it, the others a little darker, the one
    under the pointer lighter), each with its name cut with ... if it does not fit and its
    glyph, a line under the other tabs, and the two scroll arrows when the tabs do not all fit.
    Tabs are clipped at the arrows. A glyph held pressed is drawn one pixel down and right.
  =========================================================================== }
procedure TDocTabStrip.DrawStrip(C: TCanvas; AWidth, AHeight: Integer);
var
  i, G, GI, Off: Integer;
  T, Clip, R: TRect;
  Face, TabCol: TColor;
  Style: TTextStyle;
  Cur: Boolean;
  procedure Arrow(const AR: TRect; ALeft, AEnabled: Boolean);
  var
    cx, cy: Integer;
  begin
    C.Brush.Color := Face;
    C.FillRect(AR);
    if AEnabled then
      C.Brush.Color := clWindowText
    else
      C.Brush.Color := clBtnShadow;
    C.Pen.Color := C.Brush.Color;
    cx := (AR.Left + AR.Right) div 2;
    cy := (AR.Top + AR.Bottom) div 2;
    if ALeft then
      C.Polygon([Point(cx + 3, cy - 5), Point(cx + 3, cy + 5), Point(cx - 3, cy)])
    else
      C.Polygon([Point(cx - 3, cy - 5), Point(cx - 3, cy + 5), Point(cx + 3, cy)]);
  end;
begin
  Face := clBtnFace;
  C.Brush.Color := Face;
  C.FillRect(0, 0, AWidth, AHeight);
  C.Font.Assign(Font);
  G := GlyphSize;
  Clip := Rect(0, 0, TabsRight, AHeight);
  C.Pen.Color := clBtnShadow;
  C.Line(0, AHeight - 1, AWidth, AHeight - 1);
  Style := C.TextStyle;
  Style.EndEllipsis := True;
  Style.Layout := tlCenter;
  Style.Wordbreak := False;
  Style.SingleLine := True;
  for i := 0 to High(FNames) do
  begin
    T := TabRect(i);
    if (T.Right <= 0) or (T.Left >= Clip.Right) then
      Continue;
    C.ClipRect := Clip;
    C.Clipping := True;
    Cur := i = FTabIndex;
    if Cur then
      TabCol := clWindow
    else if i = FHotTab then
      TabCol := Blend(clBtnFace, clWindow, 55)
    else
      TabCol := Blend(clBtnFace, clBtnShadow, 12);
    C.Brush.Color := TabCol;
    C.Pen.Color := clBtnShadow;
    C.Rectangle(T.Left, T.Top, T.Right, T.Bottom + 1);
    if Cur then
    begin
      C.Brush.Color := clWindow;
      C.FillRect(T.Left + 1, T.Bottom - 1, T.Right - 1, T.Bottom + 1);       { opens the tab to the drawing below it }
      C.Brush.Color := clHighlight;
      C.FillRect(T.Left + 1, T.Top + 1, T.Right - 1, T.Top + 3);
    end;
    C.Brush.Style := bsClear;
    C.Font.Color := clWindowText;
    R := Rect(T.Left + DocTabPadLeft, T.Top, T.Right - DocTabPadRight - G - DocTabGap, T.Bottom);
    C.TextRect(R, R.Left, R.Top, FNames[i], Style);
    C.Brush.Style := bsSolid;
    GI := GlyphIndexFor(i);
    R := CloseRect(i);
    if IsPressed(i) then
      Off := 1
    else
      Off := 0;
    DrawGlyph(C, GI, R.Left + Off, R.Top + Off);
    C.Clipping := False;
  end;
  if ArrowsShown then
  begin
    Arrow(ArrowRect(True), True, FScroll > 0);
    Arrow(ArrowRect(False), False, FScroll < FTotal - TabsRight);
  end;
end;

{ ===========================================================================
  TDocTabStrip.Paint  (procedure)
  Parameters:  none
  Notes:
    Draws the strip (see DrawStrip).
  =========================================================================== }
procedure TDocTabStrip.Paint;
begin
  DrawStrip(Canvas, Width, Height);
end;

end.
