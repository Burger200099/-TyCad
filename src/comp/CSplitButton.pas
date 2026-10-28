{ CSplitButton - a split button: clicking the main part runs the button's action (OnClick), clicking the arrow part opens a pop-up menu (DownArrowPopup).
  Drawn with the platform theme (ThemeServices) so it looks like the other buttons; the arrow is a small triangle drawn here, so no symbol font is needed.
  Made in code (TSplitButton.Create(Owner); Parent := ...) or put on the palette by registering the unit in a package.
  Like a TSpeedButton it has no window of its own: it can be see-through (Transparent) and it never takes the keyboard focus. Licence: LGPL 2.1 or later, as the rest of this port. }
unit CSplitButton;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Menus, ImgList, Themes, LCLType, LCLIntf,
  LResources;

type
  TSplitPart = (spNone, spMain, spArrow);

  { TSplitButton }
  TSplitButton = class(TGraphicControl)
  private
    FDownArrowPopup: TPopupMenu;
    FImages: TCustomImageList;
    FImageIndex: Integer;
    FImageWidth: Integer;
    FArrowWidth: Integer;
    FFlat: Boolean;
    FChecked, FAutoCheck: Boolean;
    FTransparent: Boolean;
    FHot, FDown: TSplitPart;
    FOnDropDown: TNotifyEvent;
    FOnDropDownClick: TNotifyEvent;
    FShowing: Boolean;
    FAllowClick: Boolean;       // OnClick may run: only for the release on the main part (the control style also sends a Click for a release on the arrow)
    FArrowPending: Boolean;     // the arrow was pressed and the drop-down form opens when it is released
    procedure SetDownArrowPopup(AValue: TPopupMenu);
    procedure SetImages(AValue: TCustomImageList);
    procedure SetImageIndex(AValue: Integer);
    procedure SetImageWidth(AValue: Integer);
    procedure SetArrowWidth(AValue: Integer);
    procedure SetFlat(AValue: Boolean);
    procedure SetChecked(AValue: Boolean);
    procedure SetTransparent(AValue: Boolean);
    procedure SetHot(AValue: TSplitPart);
    function PartAt(X: Integer): TSplitPart;
    function MainRect: TRect;
    function ArrowRect: TRect;
    procedure DrawPart(const R: TRect; Part: TSplitPart);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure TextChanged; override;
    procedure CMEnabledChanged(var Msg); message CM_ENABLEDCHANGED;
    class function GetControlClassDefaultSize: TSize; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Opens the menu under the button (does nothing without a DownArrowPopup). }
    procedure DropDown;
    { runs OnClick only for a click on the main part (a release on the arrow opens the drop-down and is not a click) }
    procedure Click; override;
    { Where DownArrowPopup opens, in the button's own coordinates: the left edge of the arrow part, 1 pixel below the bottom. }
    function DropDownPoint: TPoint;
    property HotPart: TSplitPart read FHot;
    property DownPart: TSplitPart read FDown;
  published
    property Action;
    property Align;
    property Anchors;
    property BorderSpacing;
    property Caption;
    property Color;
    property Constraints;
    { The menu the arrow part opens on a left click. It is separate from PopupMenu (the right click menu). }
    property DownArrowPopup: TPopupMenu read FDownArrowPopup write SetDownArrowPopup;
    property Enabled;
    property Font;
    property Hint;
    property ImageIndex: Integer read FImageIndex write SetImageIndex default -1;
    property Images: TCustomImageList read FImages write SetImages;
    { Which size of the image list to draw from (a list can hold several, say 24 x 24 and 32 x 32): the image width in pixels. 0 = the list's own width. }
    property ImageWidth: Integer read FImageWidth write SetImageWidth default 0;
    property ArrowWidth: Integer read FArrowWidth write SetArrowWidth default 16;
    { Flat: no frame until the mouse is over the button or it is pressed, as a flat TSpeedButton (the toolbar look). }
    property Flat: Boolean read FFlat write SetFlat default False;
    { Checked: the main part is shown pressed in (the on state of a toggle button), also on a flat button, until it is set False again. }
    property Checked: Boolean read FChecked write SetChecked default False;
    { AutoCheck: a click on the main part turns Checked over (before OnClick runs). }
    property AutoCheck: Boolean read FAutoCheck write FAutoCheck default False;
    { Transparent (the default): nothing is painted behind the button, the parent shows through (a flat button at rest is just its image and text). False: the button is filled with Color first. }
    property Transparent: Boolean read FTransparent write SetTransparent default True;
    property ParentColor;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ShowHint;
    property Visible;
    property OnClick;
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
    { the arrow part was clicked: for an owner that shows a form instead of a pop-up menu (assign no DownArrowPopup then); fires after OnDropDown }
    property OnDropDownClick: TNotifyEvent read FOnDropDownClick write FOnDropDownClick;
    property OnMouseDown;
    property OnMouseUp;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Additional', [TSplitButton]);
end;

{ ===========================================================================
  TSplitButton.Create  (constructor)
  Parameters:
    AOwner: TComponent - the owner
  Notes:
    Makes a split button 100 x 25 with a 16 pixel arrow part. Like a TSpeedButton it has no window of its own, so it can be see-through and does not take the focus.
  =========================================================================== }
constructor TSplitButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csCaptureMouse, csClickEvents, csSetCaption, csDoubleClicks] - [csOpaque];
  FImageIndex := -1;
  FTransparent := True;
  ParentColor := True;
  FArrowWidth := 16;
  FHot := spNone;
  FDown := spNone;
  SetInitialBounds(0, 0, 100, 25);
end;

class function TSplitButton.GetControlClassDefaultSize: TSize;
begin
  Result.cx := 100;
  Result.cy := 25;
end;

procedure TSplitButton.SetDownArrowPopup(AValue: TPopupMenu);
begin
  if FDownArrowPopup = AValue then
    Exit;
  FDownArrowPopup := AValue;
  if AValue <> nil then
    AValue.FreeNotification(Self);
end;

procedure TSplitButton.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then
    Exit;
  FImages := AValue;
  if AValue <> nil then
    AValue.FreeNotification(Self);
  Invalidate;
end;

procedure TSplitButton.SetImageIndex(AValue: Integer);
begin
  if FImageIndex = AValue then
    Exit;
  FImageIndex := AValue;
  Invalidate;
end;

procedure TSplitButton.SetImageWidth(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  if FImageWidth = AValue then
    Exit;
  FImageWidth := AValue;
  Invalidate;
end;

procedure TSplitButton.SetArrowWidth(AValue: Integer);
begin
  if AValue < 8 then
    AValue := 8;
  if FArrowWidth = AValue then
    Exit;
  FArrowWidth := AValue;
  Invalidate;
end;

procedure TSplitButton.SetFlat(AValue: Boolean);
begin
  if FFlat = AValue then
    Exit;
  FFlat := AValue;
  Invalidate;
end;

procedure TSplitButton.SetChecked(AValue: Boolean);
begin
  if FChecked = AValue then
    Exit;
  FChecked := AValue;
  Invalidate;
end;

procedure TSplitButton.SetTransparent(AValue: Boolean);
begin
  if FTransparent = AValue then
    Exit;
  FTransparent := AValue;
  Invalidate;
end;

procedure TSplitButton.SetHot(AValue: TSplitPart);
begin
  if FHot = AValue then
    Exit;
  FHot := AValue;
  Invalidate;
end;

procedure TSplitButton.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FDownArrowPopup then
      FDownArrowPopup := nil;
    if AComponent = FImages then
      FImages := nil;
  end;
end;

procedure TSplitButton.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TSplitButton.CMEnabledChanged(var Msg);
begin
  Invalidate;
end;

{ ===========================================================================
  TSplitButton.MainRect / ArrowRect / PartAt  (geometry)
  Notes:
    The arrow part is the last ArrowWidth pixels on the right, the main part is the rest.
  =========================================================================== }
function TSplitButton.MainRect: TRect;
begin
  Result := Rect(0, 0, Width - FArrowWidth, Height);
end;

function TSplitButton.ArrowRect: TRect;
begin
  Result := Rect(Width - FArrowWidth, 0, Width, Height);
end;

function TSplitButton.PartAt(X: Integer): TSplitPart;
begin
  if (X < 0) or (X >= Width) then
    Result := spNone
  else if X >= Width - FArrowWidth then
    Result := spArrow
  else
    Result := spMain;
end;

{ ===========================================================================
  TSplitButton.DrawPart  (procedure)
  Parameters:
    const R: TRect - where the part goes
    Part: TSplitPart - which part (decides the state it is drawn in)
  Notes:
    Draws one half: the theme's push button for the whole control, clipped to the half, in the state of that half
    (hot or pressed only for the half the mouse is on); the other half stays normal, as in office style split buttons.
  =========================================================================== }
procedure TSplitButton.DrawPart(const R: TRect; Part: TSplitPart);
var
  Det: TThemedElementDetails;
begin
  if not Enabled then
    Det := ThemeServices.GetElementDetails(tbPushButtonDisabled)
  else if (FDown = Part) or ((Part = spMain) and FChecked) then
    Det := ThemeServices.GetElementDetails(tbPushButtonPressed)
  else if (FHot = Part) and (FDown = spNone) then
    Det := ThemeServices.GetElementDetails(tbPushButtonHot)
  else
    Det := ThemeServices.GetElementDetails(tbPushButtonNormal);
  { the whole button is drawn, clipped to the part, so the frame is one frame round both parts and not one each }
  Canvas.ClipRect := R;
  Canvas.Clipping := True;
  ThemeServices.DrawElement(Canvas.Handle, Det, ClientRect, nil);
  Canvas.Clipping := False;
end;

{ ===========================================================================
  TSplitButton.Paint  (procedure)
  Notes:
    Draws both halves, the image and caption centred in the main half, a small filled triangle in the arrow half,
    and the focus rectangle when the button has the focus.
  =========================================================================== }
procedure TSplitButton.Paint;
var
  M, A: TRect;
  TW, TH, IW, X, Y, CX, CY, S: Integer;
  Cap: String;
  Res: TScaledImageListResolution;
begin
  M := MainRect;
  A := ArrowRect;
  { Transparent: what is behind the button is the parent's (nothing is painted); otherwise the control is filled with Color first }
  if not FTransparent then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := Color;
    Canvas.FillRect(ClientRect);
  end;
  { a flat button at rest has no frame: only what is under it }
  if not (FFlat and Enabled and (FHot = spNone) and (FDown = spNone) and not FChecked) then
  begin
    DrawPart(M, spMain);
    DrawPart(A, spArrow);
    { the divider between the parts, a little shorter than the button }
    Canvas.Pen.Color := clBtnShadow;
    Canvas.Line(A.Left, 4, A.Left, Height - 4);
  end;
  Canvas.Font.Assign(Font);
  if Enabled then
    Canvas.Font.Color := clBtnText
  else
    Canvas.Font.Color := clGrayText;
  Canvas.Brush.Style := bsClear;
  Cap := Caption;
  TW := 0;
  if Cap <> '' then
    TW := Canvas.TextWidth(Cap);
  TH := Canvas.TextHeight('Wg');
  IW := 0;
  if (FImages <> nil) and (FImageIndex >= 0) and (FImageIndex < FImages.Count) then
  begin
    { the size asked for (ImageWidth), scaled for the screen's resolution by the list itself }
    Res := FImages.ResolutionForPPI[FImageWidth, Font.PixelsPerInch, 1.0];
    IW := Res.Width;
  end;
  X := M.Left + ((M.Right - M.Left) - (IW + TW + Ord((IW > 0) and (TW > 0)) * 4)) div 2;
  if X < M.Left + 2 then
    X := M.Left + 2;
  if IW > 0 then
  begin
    Res.Draw(Canvas, X, (Height - Res.Height) div 2, FImageIndex, Enabled);
    Inc(X, IW + 4);
  end;
  if TW > 0 then
  begin
    Y := (Height - TH) div 2;
    if FDown = spMain then
    begin
      Inc(X);
      Inc(Y);
    end;
    Canvas.TextOut(X, Y, Cap);
  end;
  { the arrow: a filled triangle, its size follows the height of the button so it stays right at any scaling }
  S := Height div 8;
  if S < 2 then
    S := 2;
  CX := A.Left + (A.Right - A.Left) div 2;
  CY := Height div 2;
  if FDown = spArrow then
    Inc(CY);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Canvas.Font.Color;
  Canvas.Pen.Color := Canvas.Font.Color;
  Canvas.Polygon([Point(CX - S, CY - S div 2), Point(CX + S, CY - S div 2), Point(CX, CY - S div 2 + S)]);
end;

{ ===========================================================================
  TSplitButton.DropDown  (procedure)
  Notes:
    Fires OnDropDown (so the menu can be filled in first) and OnDropDownClick (for an owner that shows its own form), then opens (when DownArrowPopup is assigned) DownArrowPopup at DropDownPoint: level with the left edge of the arrow part, 1 pixel below the button.
    The arrow shows pressed while the menu is open.
  =========================================================================== }
function TSplitButton.DropDownPoint: TPoint;
begin
  Result := Point(Width - FArrowWidth, Height + 1);
end;

procedure TSplitButton.DropDown;
var
  P: TPoint;
begin
  if FShowing then
    Exit;
  if Assigned(FOnDropDown) then
    FOnDropDown(Self);
  if Assigned(FOnDropDownClick) then
    FOnDropDownClick(Self);
  if FDownArrowPopup = nil then
    Exit;
  FShowing := True;
  FDown := spArrow;
  Invalidate;
  Update;
  try
    P := ControlToScreen(DropDownPoint);
    FDownArrowPopup.PopUp(P.X, P.Y);
  finally
    FShowing := False;
    FDown := spNone;
    FHot := spNone;
    Invalidate;
  end;
end;

procedure TSplitButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (Button <> mbLeft) or not Enabled then
    Exit;
  case PartAt(X) of
    spMain:
      begin
        FDown := spMain;
        Invalidate;
      end;
    spArrow:
      { a menu opens at once, as any menu button; a form of the owner's opens when the button is released (opened under the pressed mouse, it would be deactivated by the release) }
      if (FDownArrowPopup <> nil) or not Assigned(FOnDropDownClick) then
        DropDown
      else
        FArrowPending := True;
  end;
end;

procedure TSplitButton.Click;
begin
  if FAllowClick then
    inherited Click;
end;

procedure TSplitButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Was: TSplitPart;
begin
  Was := FDown;
  if FArrowPending then
  begin
    FArrowPending := False;
    if (Button = mbLeft) and (PartAt(X) = spArrow) then
      DropDown;
  end;
  if (Button = mbLeft) and (Was = spMain) then
  begin
    FDown := spNone;
    Invalidate;
    { the main action only when the button is released over the main part, as any button }
    if PartAt(X) = spMain then
    begin
      if FAutoCheck then
        Checked := not FChecked;
      FAllowClick := True;
      try
        Click;
      finally
        FAllowClick := False;
      end;
    end;
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TSplitButton.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(PartAt(X));
end;

procedure TSplitButton.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(spNone);
end;

initialization
  { the palette icon (24 x 24 PNG, made with lazres from tsplitbutton.png): found by the class name }
  {$I CSplitButton.lrs}

end.
