// SPDX-License-Identifier: LGPL-2.1-or-later
unit CSheetTabs;

{ The strip of sheet tabs at the bottom of the drawing area. It is drawn by the program (as UDocTabs is), so it keeps its own scroll position: choosing a tab, or
  rebuilding the list of names, never moves the tabs unless the current tab would be out of view. The current tab is drawn in its own (bold) font with picture 0 of
  Images (the arrow); the other tabs have no picture. When the tabs are wider than the strip two arrows appear at the right end (and the mouse wheel scrolls).

  Used like a TTabControl: Tabs (a string list), TabIndex, OnChange, IndexOfTabAt, Images, OnMouseDown, OnDblClick, PopupMenu.

  Licence: LGPL 2.1 or later, as the rest of this port. }

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, ImgList, Types, Math, ExtCtrls, LCLType, LMessages, LResources;

const
  SheetTabRepeatDelay = 500;        // ms a scroll arrow is held before it repeats
  SheetTabRepeatInterval = 50;      // ms between repeats while it is held

type
  { TSheetTabStrip }

  TSheetTabStrip = class(TCustomControl)
  private
    FTabs: TStringList;
    FTabIndex: Integer;
    FScroll: Integer;
    FImages: TCustomImageList;
    FSelFont: TFont;
    FLeft: array of Integer;
    FWidths: array of Integer;
    FTotal: Integer;
    FOnChange: TNotifyEvent;
    FBusy: Boolean;
    FMeasure: TBitmap;
    FRepeat: TTimer;
    FRepeatDir: Integer;       // -1 left arrow held, 1 right arrow held, 0 none
    function GetTabs: TStrings;
    procedure SetTabs(AValue: TStrings);
    procedure SetTabIndex(AValue: Integer);
    procedure SetImages(AValue: TCustomImageList);
    procedure TabsChanged(Sender: TObject);
    procedure Relayout;
    procedure ClampScroll;
    function ArrowsShown: Boolean;
    function ViewRight: Integer;
    function ArrowRect(ALeft: Boolean): TRect;
    function PadX: Integer;
    function TabHeight: Integer;
    procedure ScrollBy(ADelta: Integer);
    procedure RepeatTimer(Sender: TObject);
    procedure StartRepeat(ADir: Integer);
    procedure StopRepeat;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure DblClick; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure CMFontChanged(var Message: TLMessage); message CM_FONTCHANGED;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function IndexOfTabAt(X, Y: Integer): Integer;
    procedure EnsureVisible(Index: Integer);
    property Scroll: Integer read FScroll;
  published
    property Align;
    property Anchors;
    property BorderSpacing;
    property Color;
    property Constraints;
    property Cursor;
    property Enabled;
    property Font;
    property Hint;
    property Images: TCustomImageList read FImages write SetImages;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ShowHint;
    property TabIndex: Integer read FTabIndex write SetTabIndex default -1;
    property Tabs: TStrings read GetTabs write SetTabs;
    property TabOrder;
    property TabStop;
    property Visible;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Additional', [TSheetTabStrip]);
end;

constructor TSheetTabStrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  FTabs := TStringList.Create;
  FTabs.OnChange := @TabsChanged;
  FSelFont := TFont.Create;
  FRepeat := TTimer.Create(Self);
  FRepeat.Enabled := False;
  FRepeat.OnTimer := @RepeatTimer;
  FMeasure := TBitmap.Create;
  FMeasure.SetSize(8, 8);
  FTabIndex := -1;
  DoubleBuffered := True;
  Width := 400;
  Relayout;
end;

destructor TSheetTabStrip.Destroy;
begin
  FMeasure.Free;
  FSelFont.Free;
  FTabs.Free;
  inherited Destroy;
end;

function TSheetTabStrip.PadX: Integer;
begin
  Result := Scale96ToFont(7);
end;

function TSheetTabStrip.TabHeight: Integer;
begin
  FMeasure.Canvas.Font := Font;
  Result := FMeasure.Canvas.TextHeight('Ag') + Scale96ToFont(10);
  if (FImages <> nil) and (FImages.Height + 6 > Result) then
    Result := FImages.Height + 6;
end;

procedure TSheetTabStrip.Relayout;
var
  i, X, w: Integer;
begin
  SetLength(FLeft, FTabs.Count);
  SetLength(FWidths, FTabs.Count);
  FMeasure.Canvas.Font := Font;
  FSelFont.Assign(Font);
  FSelFont.Style := FSelFont.Style + [fsBold];
  X := 0;
  for i := 0 to FTabs.Count - 1 do
  begin
    { the current tab is bold and has the arrow, so it is the wider one; the others are as wide as their name }
    if i = FTabIndex then
    begin
      FMeasure.Canvas.Font := FSelFont;
      w := FMeasure.Canvas.TextWidth(FTabs[i]) + 2 * PadX;
      if FImages <> nil then
        w := w + FImages.Width + Scale96ToFont(2);
    end
    else
    begin
      FMeasure.Canvas.Font := Font;
      w := FMeasure.Canvas.TextWidth(FTabs[i]) + 2 * PadX;
    end;
    FLeft[i] := X;
    FWidths[i] := w;
    X := X + w;
  end;
  FTotal := X;
  Constraints.MinHeight := TabHeight;
  Constraints.MaxHeight := TabHeight;
  Height := TabHeight;
  ClampScroll;
  Invalidate;
end;

function TSheetTabStrip.ArrowsShown: Boolean;
begin
  Result := FTotal > ClientWidth;
end;

function TSheetTabStrip.ViewRight: Integer;
begin
  if ArrowsShown then
    Result := ClientWidth - 2 * Scale96ToFont(18)
  else
    Result := ClientWidth;
end;

function TSheetTabStrip.ArrowRect(ALeft: Boolean): TRect;
var
  a: Integer;
begin
  a := Scale96ToFont(18);
  if not ArrowsShown then
    Exit(Rect(0, 0, 0, 0));
  if ALeft then
    Result := Rect(ClientWidth - 2 * a, 0, ClientWidth - a, ClientHeight)
  else
    Result := Rect(ClientWidth - a, 0, ClientWidth, ClientHeight);
end;

procedure TSheetTabStrip.ClampScroll;
begin
  if not ArrowsShown then
    FScroll := 0
  else
    FScroll := Max(0, Min(FScroll, FTotal - ViewRight));
end;

procedure TSheetTabStrip.ScrollBy(ADelta: Integer);
var
  o: Integer;
begin
  o := FScroll;
  FScroll := FScroll + ADelta;
  ClampScroll;
  if FScroll <> o then
    Invalidate;
end;

procedure TSheetTabStrip.RepeatTimer(Sender: TObject);
var
  o: Integer;
begin
  { the first tick is the wait before the repeat; from then on every SheetTabRepeatInterval }
  FRepeat.Interval := SheetTabRepeatInterval;
  o := FScroll;
  ScrollBy(FRepeatDir * Scale96ToFont(80));
  if FScroll = o then
    StopRepeat;      // at the end
end;

procedure TSheetTabStrip.StartRepeat(ADir: Integer);
begin
  FRepeatDir := ADir;
  FRepeat.Enabled := False;
  FRepeat.Interval := SheetTabRepeatDelay;
  FRepeat.Enabled := True;
end;

procedure TSheetTabStrip.StopRepeat;
begin
  FRepeat.Enabled := False;
  FRepeatDir := 0;
end;

procedure TSheetTabStrip.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  StopRepeat;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TSheetTabStrip.MouseLeave;
begin
  StopRepeat;
  inherited MouseLeave;
end;

procedure TSheetTabStrip.EnsureVisible(Index: Integer);
var
  o: Integer;
begin
  if (Index < 0) or (Index >= FTabs.Count) then
    Exit;
  o := FScroll;
  if FLeft[Index] < FScroll then
    FScroll := FLeft[Index]
  else if FLeft[Index] + FWidths[Index] > FScroll + ViewRight then
    FScroll := FLeft[Index] + FWidths[Index] - ViewRight;
  ClampScroll;
  if FScroll <> o then
    Invalidate;
end;

procedure TSheetTabStrip.TabsChanged(Sender: TObject);
begin
  if FTabIndex >= FTabs.Count then
    FTabIndex := FTabs.Count - 1;
  Relayout;      { the scroll position is kept (only clamped) }
end;

function TSheetTabStrip.GetTabs: TStrings;
begin
  Result := FTabs;
end;

procedure TSheetTabStrip.SetTabs(AValue: TStrings);
begin
  FTabs.Assign(AValue);
end;

procedure TSheetTabStrip.SetTabIndex(AValue: Integer);
begin
  if AValue >= FTabs.Count then
    AValue := FTabs.Count - 1;
  if AValue < -1 then
    AValue := -1;
  if AValue = FTabIndex then
    Exit;
  FTabIndex := AValue;
  Relayout;
  EnsureVisible(FTabIndex);
  Invalidate;
  if (not FBusy) and Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TSheetTabStrip.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then
    Exit;
  FImages := AValue;
  Relayout;
end;

function TSheetTabStrip.IndexOfTabAt(X, Y: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  if (X < 0) or (X >= ViewRight) or (Y < 0) or (Y >= ClientHeight) then
    Exit;
  for i := 0 to FTabs.Count - 1 do
    if (X + FScroll >= FLeft[i]) and (X + FScroll < FLeft[i] + FWidths[i]) then
      Exit(i);
end;

procedure TSheetTabStrip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  if ArrowsShown and PtInRect(ArrowRect(True), Point(X, Y)) then
  begin
    ScrollBy(-Scale96ToFont(80));
    StartRepeat(-1);
  end
  else if ArrowsShown and PtInRect(ArrowRect(False), Point(X, Y)) then
  begin
    ScrollBy(Scale96ToFont(80));
    StartRepeat(1);
  end
  else
  begin
    i := IndexOfTabAt(X, Y);
    if i >= 0 then
      SetTabIndex(i);
  end;
end;

function TSheetTabStrip.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  ScrollBy(-Sign(WheelDelta) * Scale96ToFont(80));
  Result := True;
end;

{ A double click on a scroll arrow is two quick clicks on it: it scrolls again and is not a double click on a tab (OnDblClick renames the sheet). }
procedure TSheetTabStrip.DblClick;
var
  P: TPoint;
begin
  P := ScreenToClient(Mouse.CursorPos);
  if ArrowsShown and PtInRect(ArrowRect(True), P) then
    ScrollBy(-Scale96ToFont(80))
  else if ArrowsShown and PtInRect(ArrowRect(False), P) then
    ScrollBy(Scale96ToFont(80))
  else if IndexOfTabAt(P.X, P.Y) >= 0 then
    inherited DblClick;
end;

procedure TSheetTabStrip.Resize;
begin
  inherited Resize;
  ClampScroll;
  if FTabIndex >= 0 then
    EnsureVisible(FTabIndex);
end;

procedure TSheetTabStrip.CMFontChanged(var Message: TLMessage);
begin
  inherited;
  Relayout;
end;

procedure TSheetTabStrip.Paint;
var
  i, x0, tw, ty: Integer;
  R, A: TRect;
  cur: Boolean;
  C: TCanvas;
begin
  C := Canvas;
  C.Brush.Color := clBtnFace;
  C.FillRect(0, 0, ClientWidth, ClientHeight);
  C.Pen.Color := clBtnShadow;
  C.Line(0, 0, ClientWidth, 0);
  for i := 0 to FTabs.Count - 1 do
  begin
    x0 := FLeft[i] - FScroll;
    if (x0 + FWidths[i] <= 0) or (x0 >= ViewRight) then
      Continue;
    cur := i = FTabIndex;
    R := Rect(x0, 0, x0 + FWidths[i], ClientHeight);
    C.ClipRect := Rect(0, 0, ViewRight, ClientHeight);
    C.Clipping := True;
    if cur then
    begin
      C.Brush.Color := clWindow;
      C.Font := FSelFont;
    end
    else
    begin
      C.Brush.Color := clBtnFace;
      C.Font := Font;
    end;
    C.FillRect(R);
    C.Pen.Color := clBtnShadow;
    C.Line(R.Right - 1, 3, R.Right - 1, ClientHeight - 3);
    if cur then
      C.Line(R.Left, 0, R.Right, 0);
    ty := (ClientHeight - C.TextHeight(FTabs[i])) div 2;
    tw := PadX;
    if cur and (FImages <> nil) then
      FImages.Draw(C, R.Left + PadX div 2, (ClientHeight - FImages.Height) div 2, 0);
    if cur and (FImages <> nil) then
      tw := tw + FImages.Width + Scale96ToFont(2) - PadX div 2;
    C.Font.Color := clWindowText;
    C.TextOut(R.Left + tw, ty, FTabs[i]);
    C.Clipping := False;
  end;
  if ArrowsShown then
  begin
    C.Font := Font;
    C.Brush.Color := clBtnFace;
    A := ArrowRect(True);
    C.FillRect(A);
    C.Brush.Color := clWindowText;
    C.Pen.Color := clWindowText;
    C.Polygon([Point(A.Left + 11, A.Top + ClientHeight div 2 - 5), Point(A.Left + 11, A.Top + ClientHeight div 2 + 5), Point(A.Left + 5, A.Top + ClientHeight div 2)]);
    C.Brush.Color := clBtnFace;
    A := ArrowRect(False);
    C.FillRect(A);
    C.Brush.Color := clWindowText;
    C.Polygon([Point(A.Left + 5, A.Top + ClientHeight div 2 - 5), Point(A.Left + 5, A.Top + ClientHeight div 2 + 5), Point(A.Left + 11, A.Top + ClientHeight div 2)]);
  end;
end;

initialization
  RegisterClass(TSheetTabStrip);
  {$I CSheetTabs.lrs}
end.
