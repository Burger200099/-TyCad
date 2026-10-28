{ The property frame of a placed symbol, and of the symbol being placed: TinyCAD's symbol tool options (CEditDlgMethodEdit, IDD_METHOD) as ribbon controls.
    sbRotateSymbol   a click turns the symbol Up > Right > Down > Left; its arrow drops down the menu of the four directions and Mirror
    edRef            the reference (U?)                                  sym.ref
    edSymbolText     the text of a symbol text (its Name field)          symtext.text
    sbShowRef        whether the reference is shown                       sym.showref
    sbShowPowerPins  whether the power pins are shown                     sym.showpower
    sbAllowResize    whether the symbol may be resized                    sym.canscale
    sbParameterList  split button: its left part switches "show the list of the symbol's parameters whenever a symbol is selected" on and off (Checked, AutoShow);
                     its arrow drops the list down once (TfrmSymbolPropList)
  The buttons that stay down and the edit are bound to the properties by QPropFrame; the direction, the mirror and the list are told to the main window through the events below.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit qsymbols;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Menus, Buttons, StdCtrls, QPropbase, CSplitButton,
  Fsharedctls, UDrawingObjects, FSymDDD;

type
  TSymbolGetEvent = function(Sender: TObject): TMethodArray of object;
  TSymbolChangeEvent = procedure(Sender: TObject; ABefore: Boolean) of object;
  TSymbolDirEvent = procedure(Sender: TObject; ADir: Integer) of object;      // 0 up, 1 right, 2 down, 3 left (the order of the menu)

  { TfmSymbols }

  TfmSymbols = class(TfmPropertyBase)
    edRef: TEdit;
    edSymbolText: TEdit;
    miMirror: TMenuItem;
    miSep1: TMenuItem;
    miRight: TMenuItem;
    miLeft: TMenuItem;
    miDown: TMenuItem;
    miUp: TMenuItem;
    pmRotate: TPopupMenu;
    sbRotateSymbol: TSplitButton;
    sbAllowResize: TSpeedButton;
    sbShowRef: TSpeedButton;
    sbShowPowerPins: TSpeedButton;
    sbParameterList: TSplitButton;
    procedure FrameClick(Sender: TObject);
    procedure sbRotateSymbolClick(Sender: TObject);
    procedure ListBefore(Sender: TObject);
    procedure ListAfter(Sender: TObject);
    procedure MenuDirectionClick(Sender: TObject);
    procedure MenuMirrorClick(Sender: TObject);
    procedure ParametersClick(Sender: TObject);
    procedure DropParameters(AAnchor: TControl);
    procedure AutoShowClick(Sender: TObject);
  private
    FOnRotate: TNotifyEvent;
    FOnPickDirection: TSymbolDirEvent;
    FOnMirror: TNotifyEvent;
    FOnGetSymbol: TSymbolGetEvent;
    FOnParameterChange: TSymbolChangeEvent;
    FOnAutoShowChange: TNotifyEvent;
    FList: TfrmSymbolPropList;      // the parameter list dropped down by sbParameterList (made when first needed)
  public
    procedure AfterCreate; override;
    { drops the list of the parameters down (when it is not open, and there is a symbol to list) }
    procedure ShowParameters(AAnchor: TControl = nil);
    { whether the list is shown by itself when a symbol is selected: the checked state of the parameter button }
    function GetAutoShow: Boolean;
    procedure SetAutoShow(AValue: Boolean);
    property AutoShow: Boolean read GetAutoShow write SetAutoShow;
    { the parameter button was switched on or off by a click (the owner keeps the state for the next frame) }
    property OnAutoShowChange: TNotifyEvent read FOnAutoShowChange write FOnAutoShowChange;
    { shows the symbol's direction in the menu and the hint of the rotate button (ADir: 0 up, 1 down, 2 left, 3 right as TinyCAD numbers them; AMirror) }
    procedure ShowDirection(const ADirName: String; AMirror: Boolean);
    { a click on the rotate button: the owner turns the symbol to the next direction }
    property OnRotate: TNotifyEvent read FOnRotate write FOnRotate;
    { a direction chosen in the menu (0 up, 1 right, 2 down, 3 left) }
    property OnPickDirection: TSymbolDirEvent read FOnPickDirection write FOnPickDirection;
    property OnMirror: TNotifyEvent read FOnMirror write FOnMirror;
    { the symbol whose parameters the list shows (the one being placed or the one selected); nil when there is none (the owner says why) }
    property OnGetSymbol: TSymbolGetEvent read FOnGetSymbol write FOnGetSymbol;
    { a parameter is about to change (ABefore) or has changed: the owner makes it an undo step }
    property OnParameterChange: TSymbolChangeEvent read FOnParameterChange write FOnParameterChange;
    { the drop-down list of the symbol's parameters (nil until it was first opened) }
    property ParameterList: TfrmSymbolPropList read FList;
  end;

implementation


uses UStrings;

{$R *.lfm}

{ TfmSymbols }

function MirrorWords(AMirror: Boolean): String;
begin
  if AMirror then
    Result := rsMirrored
  else
    Result := '';
end;

{ ===========================================================================
  TfmSymbols.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    Gives the buttons the shared pictures (and shows their hints), attaches the menu items and the parameter list button to the frame's events (they have no handlers in the designer, so the form file stays as it was drawn).
  =========================================================================== }
procedure TfmSymbols.AfterCreate;
var
  i: Integer;
begin
  { the pictures: the form file names frmSharedControls.ilSpeedBtn, which only the designer can resolve (the shared form is not there when this frame is read), so the
    buttons get it here; a control with a hint shows it }
  for i := 0 to ComponentCount - 1 do
  begin
    if (Components[i] is TSpeedButton) and (TSpeedButton(Components[i]).Images = nil) then
      TSpeedButton(Components[i]).Images := frmSharedControls.ilSpeedBtn;
    if (Components[i] is TSplitButton) and (TSplitButton(Components[i]).Images = nil) then
      TSplitButton(Components[i]).Images := frmSharedControls.ilSpeedBtn;
    if (Components[i] is TControl) and (TControl(Components[i]).Hint <> '') then
      TControl(Components[i]).ShowHint := True;
  end;
  miUp.Tag := 0;
  miRight.Tag := 1;
  miDown.Tag := 2;
  miLeft.Tag := 3;
  miUp.OnClick := @MenuDirectionClick;
  miRight.OnClick := @MenuDirectionClick;
  miDown.OnClick := @MenuDirectionClick;
  miLeft.OnClick := @MenuDirectionClick;
  miMirror.OnClick := @MenuMirrorClick;
//  sbParameterList.OnClick := @ParametersClick;
//  sbParameterList.OnDropDownClick := @ParametersClick;
end;

{ ===========================================================================
  TfmSymbols.FrameClick  (procedure)
  Parameters:
    Sender: TObject
  Notes:
    Nothing to do (kept: the designer's form file names it).
  =========================================================================== }
procedure TfmSymbols.FrameClick(Sender: TObject);
begin
end;

{ ===========================================================================
  TfmSymbols.sbRotateSymbolClick  (procedure)
  Parameters:
    Sender: TObject
  Notes:
    A click on the rotate button turns the symbol on to the next direction: Up, Right, Down, Left (the owner does it, as it knows what the frame is editing).
  =========================================================================== }
procedure TfmSymbols.sbRotateSymbolClick(Sender: TObject);
begin
  if Assigned(FOnRotate) then
    FOnRotate(Self);
end;

{ ===========================================================================
  TfmSymbols.MenuDirectionClick  (procedure)
  Parameters:
    Sender: TObject - the menu item (its Tag is the direction)
  =========================================================================== }
procedure TfmSymbols.MenuDirectionClick(Sender: TObject);
begin
  if Assigned(FOnPickDirection) then
    FOnPickDirection(Self, (Sender as TMenuItem).Tag);
end;

{ ===========================================================================
  TfmSymbols.MenuMirrorClick  (procedure)
  Parameters:
    Sender: TObject
  Notes:
    The Mirror item turns the mirroring over (the owner knows the state).
  =========================================================================== }
procedure TfmSymbols.MenuMirrorClick(Sender: TObject);
begin
  if Assigned(FOnMirror) then
    FOnMirror(Self);
end;

{ ===========================================================================
  TfmSymbols.ParametersClick  (procedure)
  Parameters:
    Sender: TObject
  Notes:
    Drops the parameter list (TfrmSymbolPropList) down below the button, for the symbols the owner names (OnGetSymbol: the selected ones, or the one being placed); a click while it is open closes it. The list is made here the
    first time, and its changes are passed on through OnParameterChange.
  =========================================================================== }
procedure TfmSymbols.ParametersClick(Sender: TObject);
begin
  DropParameters(sbParameterList);
end;

{ the list drops from AAnchor (a button that is on the screen) }
procedure TfmSymbols.DropParameters(AAnchor: TControl);
var
  M: TMethodArray;
begin
  if FList = nil then
  begin
    FList := TfrmSymbolPropList.Create(Self);
    FList.OnBeforeChange := @ListBefore;
    FList.OnAfterChange := @ListAfter;
  end;
  if FList.Visible then
  begin
    FList.Close;
    Exit;
  end;
  if FList.JustClosed then
    Exit;
  SetLength(M, 0);
  if Assigned(FOnGetSymbol) then
    M := FOnGetSymbol(Self);
  if Length(M) = 0 then
    Exit;
  FList.AttachMany(M);
  FList.Popup(AAnchor);
end;

{ ===========================================================================
  TfmSymbols.ShowParameters  (procedure)
  Notes:
    Drops the parameter list down below the button unless it is open already or was closed a moment ago; nothing when there is no symbol to list.
  =========================================================================== }
procedure TfmSymbols.ShowParameters(AAnchor: TControl);
begin
  if (FList <> nil) and FList.Visible then
    Exit;
  if AAnchor = nil then
    AAnchor := sbParameterList;
  DropParameters(AAnchor);
end;

function TfmSymbols.GetAutoShow: Boolean;
begin
  Result := sbParameterList.Checked;
end;

procedure TfmSymbols.SetAutoShow(AValue: Boolean);
begin
  sbParameterList.Checked := AValue;
end;

{ ===========================================================================
  TfmSymbols.AutoShowClick  (procedure)
  Parameters:
    Sender: TObject - the parameter button (it has turned Checked over already: AutoCheck)
  Notes:
    The left part of the parameter button: on, the list opens now and with every symbol selected from now on; off, the list closes and stays closed until the arrow is used.
  =========================================================================== }
procedure TfmSymbols.AutoShowClick(Sender: TObject);
begin
  if Assigned(FOnAutoShowChange) then
    FOnAutoShowChange(Self);
  if sbParameterList.Checked then
    ShowParameters
  else if (FList <> nil) and FList.Visible then
    FList.Close;
end;

procedure TfmSymbols.ListBefore(Sender: TObject);
begin
  if Assigned(FOnParameterChange) then
    FOnParameterChange(Self, True);
end;

procedure TfmSymbols.ListAfter(Sender: TObject);
begin
  if Assigned(FOnParameterChange) then
    FOnParameterChange(Self, False);
end;

{ ===========================================================================
  TfmSymbols.ShowDirection  (procedure)
  Parameters:
    const ADirName: String - Up, Down, Left or Right ('' when a mixed selection has no one direction)
    AMirror: Boolean - the symbol is mirrored
  Notes:
    Ticks the direction in the menu (as radio items), the Mirror item, and tells the direction in the hint of the rotate button.
  =========================================================================== }
procedure TfmSymbols.ShowDirection(const ADirName: String; AMirror: Boolean);
begin
  miUp.RadioItem := True; miRight.RadioItem := True; miDown.RadioItem := True; miLeft.RadioItem := True;
  miUp.Checked := ADirName = 'Up';
  miRight.Checked := ADirName = 'Right';
  miDown.Checked := ADirName = 'Down';
  miLeft.Checked := ADirName = 'Left';
  miMirror.Checked := AMirror;
  miMirror.Caption := rsMirror2;
  sbRotateSymbol.Hint := rsRotateSymbolUpRightDown;
  if ADirName <> '' then
    sbRotateSymbol.Hint := Format(rsNow, [sbRotateSymbol.Hint, ADirName, MirrorWords(AMirror)]);
  sbRotateSymbol.ShowHint := True;
end;

end.
