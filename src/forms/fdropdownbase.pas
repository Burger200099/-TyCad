// SPDX-License-Identifier: LGPL-2.1-or-later
unit FDropDownBase;

{$mode ObjFPC}{$H+}

{ The parent of the forms that drop down from a button of a property panel (the Fill menu, the Bus phases and spacing panel ...). What every one of them does is here:
    - it is a borderless form that opens just below the button (Popup), moved up or left when it would run off the screen;
    - it closes when something else is clicked (Deactivate), unless it asked to stay (KeepOpen: while its own dialog is open, say), and on Esc;
    - the click on the button that closed it must not open it again (JustClosed, ForgetClose);
    - a key it does not use itself goes to HandleKey, which a descendant overrides.
  A descendant is made as a form that inherits this one (File > New > Form in the designer, then change the ancestor, or write the .lfm as 'inherited'), and
  puts its own controls on it. The button that opens it keeps one instance and calls Popup; the choice comes back through an event of the descendant's own.

  Licence: LGPL 2.1 or later, as the rest of this port. }

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, LCLType, Types;

type

  { TfrmDropDownBase }

  TfrmDropDownBase = class(TForm)
  private
    FClosedAt: QWord;               // when it was last hidden (GetTickCount64)
    FKeepOpen: Integer;             // above 0: do not close when the form is deactivated
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure DoCreate; override;
    procedure Deactivate; override;
    procedure DoHide; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    { a descendant handles its own keys here; True when it used the key (Esc is not passed: it closes the form) }
    function HandleKey(var Key: Word; Shift: TShiftState): Boolean; virtual;
    { the descendant stays open while it does something that takes the focus (a dialog): BeginKeepOpen before, EndKeepOpen after }
    procedure BeginKeepOpen;
    procedure EndKeepOpen;
  public
    procedure Popup(AAnchor: TControl); virtual;
    function JustClosed: Boolean;
    procedure ForgetClose;
    { a key as the person presses it (for the self-test script, which has no keyboard) }
    procedure PressKey(var Key: Word; Shift: TShiftState);
  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfrmDropDownBase.CreateParams  (procedure)
  Parameters:
    var Params: TCreateParams - in/out: changed by the call
  Notes:
    Nothing is changed: the form is borderless by its BorderStyle. (For an actual window style,
    WS_POPUP, WS_BORDER and WS_EX_TOOLWINDOW could be set here.)
  =========================================================================== }
procedure TfrmDropDownBase.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
end;

{ ===========================================================================
  TfrmDropDownBase.DoCreate  (procedure)
  Parameters:  none
  Notes:
    The form sees the keys before the control that has the focus does (KeyPreview), so Esc and
    the arrow keys work wherever the focus is.
  =========================================================================== }
procedure TfrmDropDownBase.DoCreate;
begin
  KeyPreview := True;
  inherited DoCreate;
end;

{ ===========================================================================
  TfrmDropDownBase.Deactivate  (procedure)
  Parameters:  none
  Notes:
    Something else was clicked: the form closes, except while a descendant asked to stay
    (BeginKeepOpen).
  =========================================================================== }
procedure TfrmDropDownBase.Deactivate;
begin
  inherited Deactivate;
  if Visible and (FKeepOpen = 0) then
    Close;
end;

{ ===========================================================================
  TfrmDropDownBase.DoHide  (procedure)
  Parameters:  none
  Notes:
    Remembers when the form closed (JustClosed).
  =========================================================================== }
procedure TfrmDropDownBase.DoHide;
begin
  FClosedAt := GetTickCount64;
  inherited DoHide;
end;

{ ===========================================================================
  TfrmDropDownBase.KeyDown  (procedure)
  Parameters:
    var Key: Word - key code (in/out: changed by the call)
    Shift: TShiftState - modifier keys held down
  Notes:
    Esc closes the form without a choice; any other key goes to HandleKey, and what that does
    not use goes on to the control with the focus.
  =========================================================================== }
procedure TfrmDropDownBase.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Close;
    Exit;
  end;
  if HandleKey(Key, Shift) then
    Key := 0
  else
    inherited KeyDown(Key, Shift);
end;

{ ===========================================================================
  TfrmDropDownBase.HandleKey  (function)
  Parameters:
    var Key: Word - key code (in/out: changed by the call)
    Shift: TShiftState - modifier keys held down
  Returns:
    Boolean
  Notes:
    TODO: describe.
  =========================================================================== }
function TfrmDropDownBase.HandleKey(var Key: Word; Shift: TShiftState): Boolean;
begin
  Result := False;
end;

{ ===========================================================================
  TfrmDropDownBase.BeginKeepOpen  (procedure)
  Parameters:  none
  Notes:
    The form stays open when it is deactivated, until the matching EndKeepOpen (they may be
    nested).
  =========================================================================== }
procedure TfrmDropDownBase.BeginKeepOpen;
begin
  Inc(FKeepOpen);
end;

{ ===========================================================================
  TfrmDropDownBase.EndKeepOpen  (procedure)
  Parameters:  none
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfrmDropDownBase.EndKeepOpen;
begin
  if FKeepOpen > 0 then
    Dec(FKeepOpen);
end;

{ ===========================================================================
  TfrmDropDownBase.Popup  (procedure)
  Parameters:
    AAnchor: TControl
  Notes:
    Shows the form just below the button, moved left when it would run off the right of the
    screen and above the button when it would run off the bottom.
  =========================================================================== }
procedure TfrmDropDownBase.Popup(AAnchor: TControl);
var
  P: TPoint;
  W: TRect;
begin
  P := AAnchor.ClientToScreen(Point(0, AAnchor.Height));
  W := Screen.MonitorFromPoint(P).WorkareaRect;
  if P.X + Width > W.Right then
    P.X := W.Right - Width;
  if P.Y + Height > W.Bottom then
    P.Y := AAnchor.ClientToScreen(Point(0, 0)).Y - Height;
  Left := P.X;
  Top := P.Y;
  Show;
end;

{ ===========================================================================
  TfrmDropDownBase.JustClosed  (function)
  Parameters:  none
  Returns:
    Boolean
  Notes:
    Clicking the button of an open form first takes the focus from the form (which hides it) and
    then clicks the button: the button should not open the form again then.
  =========================================================================== }
function TfrmDropDownBase.JustClosed: Boolean;
begin
  Result := (FClosedAt <> 0) and (GetTickCount64 - FClosedAt < 300);
end;

{ ===========================================================================
  TfrmDropDownBase.ForgetClose  (procedure)
  Parameters:  none
  Notes:
    JustClosed is False from now on (for the self-test script, which does not wait between its
    clicks as a person does).
  =========================================================================== }
procedure TfrmDropDownBase.ForgetClose;
begin
  FClosedAt := 0;
end;

{ ===========================================================================
  TfrmDropDownBase.PressKey  (procedure)
  Parameters:
    var Key: Word - key code (in/out: changed by the call)
    Shift: TShiftState - modifier keys held down
  Notes:
    Runs the key through the form as a key the person pressed (the self-test script).
  =========================================================================== }
procedure TfrmDropDownBase.PressKey(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

end.
