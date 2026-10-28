// SPDX-License-Identifier: LGPL-2.1-or-later
unit URibbon;

{ The strip of tab headings above the ribbon (Home, Sheet, View, Draw ...), drawn by the program on a paint box: the system's own headings are not shown (the page control
  that holds the ribbon's pages is only used for its pages). The strip knows the page control, so each page's caption is a tab, the active page is drawn as the selected tab
  and the one under the pointer in the hover colour; the colours come from the light / dark theme (consts.RibbonThemes).

  The strip only reports a click (OnChoose, with the page's caption): what choosing a ribbon tab does beyond showing the page belongs to the main form.

  Licence: LGPL 2.1 or later, as the rest of this port. }

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ExtCtrls, ComCtrls, Forms, Types, consts;

type
  TRibbonChooseEvent = procedure(const ATitle: String) of object;

  { TRibbonTabStrip }

  TRibbonTabStrip = class(TComponent)
  private
    FBox: TPaintBox;
    FRibbon: TPageControl;
    FHot: Integer;
    FPaints: Integer;
    FTheme: TLDTheme;
    FOnChoose: TRibbonChooseEvent;
    function Scale(AValue: Integer): Integer;
    procedure SetTheme(AValue: TLDTheme);
  public
    { ABox is the paint box the strip is drawn on, ARibbon the page control whose pages are the tabs; the owner frees the strip }
    constructor Create(AOwner: TComponent; ABox: TPaintBox; ARibbon: TPageControl); reintroduce;
    { the rectangle of one tab in the strip, empty for an index that is not a page }
    function TabRect(Index: Integer): TRect;
    { the tab at a point, -1 for none }
    function TabAt(X, Y: Integer): Integer;
    { the paint box's OnPaint, OnMouseMove, OnMouseLeave and OnMouseDown (the main form's handlers call these) }
    procedure Paint;
    procedure MouseMove(X, Y: Integer);
    procedure MouseLeave;
    procedure MouseDown(Button: TMouseButton; X, Y: Integer);
    { draws the strip again (the page was changed in code, which does not fire the page control's OnChange) }
    procedure Invalidate;
    property Theme: TLDTheme read FTheme write SetTheme;
    { the tab under the pointer, -1 for none }
    property HotTab: Integer read FHot;
    { how many times the strip has been painted (tests check it is repainted when a tab is chosen from code) }
    property Paints: Integer read FPaints;
    property OnChoose: TRibbonChooseEvent read FOnChoose write FOnChoose;
  end;

implementation

{ ===========================================================================
  TRibbonTabStrip.Create  (constructor)
  Parameters:
    AOwner: TComponent
    ABox: TPaintBox
    ARibbon: TPageControl
  Notes:
    No tab is under the pointer and the light theme is used until Theme is set. The paint box's
    own events are not hooked up here: the main form's handlers (the ones named in its form
    file) call Paint, MouseMove, MouseLeave and MouseDown.
  =========================================================================== }
constructor TRibbonTabStrip.Create(AOwner: TComponent; ABox: TPaintBox; ARibbon: TPageControl);
begin
  inherited Create(AOwner);
  FBox := ABox;
  FRibbon := ARibbon;
  FHot := -1;
  FTheme := themeLight;
end;

{ ===========================================================================
  TRibbonTabStrip.Scale  (function)
  Parameters:
    AValue: Integer - the value
  Returns:
    Integer
  Notes:
    The padding and offsets of the strip follow the screen's scale as the rest of the form does.
  =========================================================================== }
function TRibbonTabStrip.Scale(AValue: Integer): Integer;
var
  F: TCustomForm;
begin
  F := GetParentForm(FBox);
  if F <> nil then
    Result := F.Scale96ToForm(AValue)
  else
    Result := AValue;
end;

{ ===========================================================================
  TRibbonTabStrip.SetTheme  (procedure)
  Parameters:
    AValue: TLDTheme - the value
  Notes:
    Chooses the colours and draws the strip again.
  =========================================================================== }
procedure TRibbonTabStrip.SetTheme(AValue: TLDTheme);
begin
  FTheme := AValue;
  FBox.Invalidate;
end;

{ ===========================================================================
  TRibbonTabStrip.Invalidate  (procedure)
  Parameters:  none
  Notes:
    Has the strip painted again.
  =========================================================================== }
procedure TRibbonTabStrip.Invalidate;
begin
  FBox.Invalidate;
end;

{ ===========================================================================
  TRibbonTabStrip.TabRect  (function)
  Parameters:
    Index: Integer - zero-based index
  Returns:
    TRect
  Notes:
    The rectangle of one ribbon tab in the painted tab strip: tabs sit side by side, each as
    wide as its caption plus padding, starting a little in from the left.
  =========================================================================== }
function TRibbonTabStrip.TabRect(Index: Integer): TRect;
var
  I, X, W, Padding: Integer;
begin
  FBox.Canvas.Font.Assign(FBox.Font);
  Padding := Scale(28);
  X := Scale(8);
  for I := 0 to Index do
  begin
    if I >= FRibbon.PageCount then
      Break;
    W := FBox.Canvas.TextWidth(FRibbon.Pages[I].Caption) + Padding;
    if I = Index then
      Exit(Rect(X, 0, X + W, FBox.Height));
    Inc(X, W);
  end;
  Result := Rect(0, 0, 0, 0);
end;

{ ===========================================================================
  TRibbonTabStrip.TabAt  (function)
  Parameters:
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
  Returns:
    Integer
  Notes:
    Which painted ribbon tab is under a point.
  =========================================================================== }
function TRibbonTabStrip.TabAt(X, Y: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FRibbon.PageCount - 1 do
    if PtInRect(TabRect(I), Point(X, Y)) then
      Exit(I);
end;

{ ===========================================================================
  TRibbonTabStrip.Paint  (procedure)
  Parameters:  none
  Notes:
    Paints the ribbon tab strip: the header color as background, each page caption as a tab, the
    active tab highlighted (and 3 pixels lower, so it looks joined to the page) and the one
    under the mouse in the hover color, all from the current theme.
  =========================================================================== }
procedure TRibbonTabStrip.Paint;
var
  C: TCanvas;
  R: TRect;
  I, TX, TY: Integer;
  Selected: Boolean;
  cText: string;
  Colors: TRibbonTheme;
begin
  Inc(FPaints);
  Colors := RibbonThemes[shortint(FTheme)];
  C := FBox.Canvas;
  C.Font.Assign(FBox.Font);
  C.Brush.Style := bsSolid;
  C.Brush.Color := Colors.HeaderColor;
  C.FillRect(FBox.ClientRect);
  for I := 0 to FRibbon.PageCount - 1 do
  begin
    R := TabRect(I);
    cText := FRibbon.Pages[I].Caption;
    Selected := FRibbon.ActivePage = FRibbon.Pages[I];
    C.Brush.Style := bsSolid;
    if Selected then
    begin
      R.Top := Scale(3);
      C.Brush.Color := Colors.SelectedColor;
      C.Font.Color := Colors.SelectedTextColor;
    end
    else
    begin
      if I = FHot then
        C.Brush.Color := Colors.HoverColor
      else
        C.Brush.Color := Colors.HeaderColor;
      C.Font.Color := Colors.TextColor;
    end;
    C.FillRect(R);
    TX := R.Left + (R.Right - R.Left - C.TextWidth(cText)) div 2;
    TY := R.Top + (R.Bottom - R.Top - C.TextHeight(cText)) div 2;
    C.Brush.Style := bsClear;
    C.TextOut(TX, TY, cText);
    C.Brush.Style := bsSolid;
  end;
  C.Brush.Style := bsSolid;
end;

{ ===========================================================================
  TRibbonTabStrip.MouseMove  (procedure)
  Parameters:
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
  Notes:
    Remembers which tab the mouse is over and repaints the strip when that changes.
  =========================================================================== }
procedure TRibbonTabStrip.MouseMove(X, Y: Integer);
var
  N: Integer;
begin
  N := TabAt(X, Y);
  if N <> FHot then
  begin
    FHot := N;
    FBox.Invalidate;
  end;
end;

{ ===========================================================================
  TRibbonTabStrip.MouseLeave  (procedure)
  Parameters:  none
  Notes:
    The mouse left the tab strip: no tab is hot any more.
  =========================================================================== }
procedure TRibbonTabStrip.MouseLeave;
begin
  FHot := -1;
  FBox.Invalidate;
end;

{ ===========================================================================
  TRibbonTabStrip.MouseDown  (procedure)
  Parameters:
    Button: TMouseButton - which mouse button
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
  Notes:
    A left click on a tab asks for that ribbon page to be shown (OnChoose, with the page's
    caption); the main form brings the page forward. Other buttons and clicks off the tabs do
    nothing.
  =========================================================================== }
procedure TRibbonTabStrip.MouseDown(Button: TMouseButton; X, Y: Integer);
var
  N: Integer;
begin
  if Button <> mbLeft then
    Exit;
  N := TabAt(X, Y);
  if (N >= 0) and Assigned(FOnChoose) then
    FOnChoose(FRibbon.Pages[N].Caption);
end;

end.
