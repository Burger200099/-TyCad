{ Property frames: a frame designed in the Lazarus form designer that is shown on the ribbon in place of the editors BuildEditors makes by itself.
  One frame can serve a tool (the Properties panel of the Draw ribbon) and, for the same kind of object, the selection (the Properties ribbon).

  Making one:
    - add a Frame (File > New > Frame) and lay its controls out as they should look on the ribbon: captions, positions, widths, ranges of the number boxes,
      hints. Its height is the ribbon's (about 73 pixels, above the label that says what the panel is); its width is the width the panel gets.
    - give each editor a Name that ends with the property it edits, the key of UProps with the dot taken out; case and underscores do not matter and
      anything may come before it:  spLineWidth (line.width), cbtnLineColor (line.color), cbLineStyle (line.style), edText (text), ckFontBold (font.bold),
      spFontHeight (font.height), cbPinDir (pin.dir) ... The whole list is UProps.PropKeys.
    - the editor class has to fit the property: whole number (pkInt) TSpinEdit (or a TComboBox holding the number as text, like a font size), fractional
      (pkFloat) TFloatSpinEdit, color TColorButton, choice TComboBox, yes/no TCheckBox or a TSpeedButton that stays down, text TEdit (or a TComboBox, like a
      font name). Two more uses of a choice: a TCheckBox that is ticked when the choice is not the first one (a Fill box for Fill None/Solid/...; it may
      share the property with the combo box), and a TSpeedButton that steps through the choices when it is clicked (the direction button of a power symbol,
      Up > Right > Down > Left; its picture is chosen by the program). Radio buttons for a choice (arc.type, 'in|out') are named for the property too (rbArcType) or listed in the registration; each is captioned with its choice and is ticked when it is the property's value. A TSpeedButton bound to fill.type ('bbFill=fill.type') is the whole fill editor: the program
      draws the fill style and color on it and drops the menu down (FFillDropDown) to choose the style or the color; it needs no Fill box, type list or color button. (A frame with a wrong class is still shown; the editor is disabled and the problem
      is listed by BindPropFrame.)
    - a drop-down needs no items: the program fills it with the choices of the property (and draws the line styles as pictures). Events need no handlers either:
      they are attached when the frame is shown.
    - a caption and its editor that should disappear together (a selection of several objects shows only the properties they all have) go in a small
      panel (or group box) of their own; the panel is hidden with the editor. A caption outside any panel stays.
    - names that do not end with a property key are linked by a list in the registration:  'cbWireColor=line.color'; a caption that goes with the editor can
      be added after a colon ('cbTextDirection1=label.style:lbType', the label is hidden when the property is missing); 'cbFill=' alone says the control is not
      an editor. Controls named the first way need no list.
    - register it in QPropFrameList.pas:  RegisterPropFrame('wire', TfrWireProps, ['cbWireColor=line.color']);  The keys are the tools and object kinds: wire, bus, line, polygon, arc,
      rect, circle, note, cloud, measure, text, label, power, and for other objects the class name without TDraw, in lower case (ruler, reftext, ladder, method, pin ...).

  The program does the rest: it makes the frame, finds the editors by their names, shows the values of the tool or of the selection in them, and applies what
  is chosen. A kind of object without a frame gets the editors BuildEditors makes.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit QPropFrame;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Spin, Dialogs, Buttons, UProps, UDrawTypes, UDrawingObjects;

type
  TPropFrameClass = class of TFrame;

  { how a control edits its property: the way its class fits the kind of the property }
  TBindMode = (
    bmNormal,     // a box, a color button, a check box or a toggle button holding the value itself
    bmSwitch,     // a check box for a choice: ticked when the choice is not the first one
    bmCycle,      // a button for a choice: each click goes to the next choice (Up, Right, Down, Left for a direction)
    bmFill,       // a TSpeedButton for the fill type (fill.type): it shows the fill (pattern and color) and drops down the menu of the fill styles and the color
    bmRadio,     // a TRadioButton for one choice of a property: ticked when the property is that choice (its caption is the choice's name, 'in' or 'out'); a group of them shares the property
    bmDrop);     // a TSpeedButton for the bus phases (bus.phases): it shows the phases and drops down the panel of the phases and the wire spacing (FBusDropDown)

  { one editor of a frame, linked to the property it edits }
  TFrameBinding = record
    Def: TPropDef;          // the property (from the tool or the selection)
    Control: TControl;      // the editor
    Mode: TBindMode;
  end;
  TFrameBindings = array of TFrameBinding;

{ the frame for a kind of tool or object (see the unit's comment for the keys); a second registration of a key replaces the first.
  AAliases links controls whose names do not end with a property key:  'control=prop.key[:caption,caption]'  ('control=' says it is not an editor) }
procedure RegisterPropFrame(const AKey: String; AFrame: TPropFrameClass; const AAliases: array of String);
procedure RegisterPropFrame(const AKey: String; AFrame: TPropFrameClass);
{ forget every registration (for tests) }
procedure UnregisterPropFrames;
function PropFrameFor(const AKey: String): TPropFrameClass;
{ the control-to-property list of a registration (nil when there is none) }
function PropFrameAliases(const AKey: String): TStrings;
{ the key a kind of object is registered under: wire, bus, line, polygon, arc, rect, circle, note, or the lower case class name without TDraw }
function PropFrameKeyOfObject(Obj: TDrawingObject): String;
{ the property a control name ends with (see the unit's comment), or '' }
function PropKeyOfControlName(const AName: String): String;
{ what is wrong with a control as the editor of a property, or '' }
function ControlProblem(const ADef: TPropDef; AControl: TControl): String;
{ how a control edits a property of that kind }
function ControlMode(const ADef: TPropDef; AControl: TControl): TBindMode;
{ Links the editors of a frame to the properties in Defs (the tool's or the selection's): returns the editors in Bindings, hides the editors of properties that
  are not in Defs (with their captions, and a panel left with nothing visible), disables the ones of the wrong class, and adds a line to Problems for each of
  those and for a property bound twice. Aliases (may be nil) is the control=property list of the registration. Returns how many were linked. }
function BindPropFrame(AFrame: TFrame; const Defs: TPropDefArray; Aliases: TStrings; out Bindings: TFrameBindings; Problems: TStrings): Integer;

implementation

type
  TRegistered = record
    Key: String;
    Cls: TPropFrameClass;
    Aliases: TStringList;
  end;

var
  Registered: array of TRegistered;

{ ===========================================================================
  RegisterPropFrame  (procedure)
  Parameters:
    const AKey: String - text
    AFrame: TPropFrameClass
    const AAliases: array of String
  Notes:
    Makes the frame the one shown for that key; a second call for the same key replaces the
    first.
  =========================================================================== }
procedure RegisterPropFrame(const AKey: String; AFrame: TPropFrameClass; const AAliases: array of String);
var
  i, N: Integer;
begin
  N := -1;
  for i := 0 to High(Registered) do
    if SameText(Registered[i].Key, AKey) then
      N := i;
  if N < 0 then
  begin
    SetLength(Registered, Length(Registered) + 1);
    N := High(Registered);
    Registered[N].Key := LowerCase(AKey);
    Registered[N].Aliases := TStringList.Create;
  end;
  Registered[N].Cls := AFrame;
  Registered[N].Aliases.Clear;
  for i := 0 to High(AAliases) do Registered[N].Aliases.Add(AAliases[i]);
end;

{ ===========================================================================
  RegisterPropFrame  (procedure)
  Parameters:
    const AKey: String - text
    AFrame: TPropFrameClass
  Notes:
    TODO: describe.
  =========================================================================== }
procedure RegisterPropFrame(const AKey: String; AFrame: TPropFrameClass);
begin
  RegisterPropFrame(AKey, AFrame, []);
end;

{ ===========================================================================
  UnregisterPropFrames  (procedure)
  Parameters:  none
  Notes:
    Forgets every registration (the self-test script starts from none).
  =========================================================================== }
procedure UnregisterPropFrames;
var
  i: Integer;
begin
  for i := 0 to High(Registered) do Registered[i].Aliases.Free;
  SetLength(Registered, 0);
end;

{ ===========================================================================
  PropFrameFor  (function)
  Parameters:
    const AKey: String - text
  Returns:
    TPropFrameClass
  Notes:
    Finds the registered frame.
  =========================================================================== }
function PropFrameFor(const AKey: String): TPropFrameClass;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to High(Registered) do
    if SameText(Registered[i].Key, AKey) then
      Exit(Registered[i].Cls);
end;

{ ===========================================================================
  PropFrameAliases  (function)
  Parameters:
    const AKey: String - text
  Returns:
    TStrings
  Notes:
    The list belongs to the registry.
  =========================================================================== }
function PropFrameAliases(const AKey: String): TStrings;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to High(Registered) do
    if SameText(Registered[i].Key, AKey) then
      Exit(Registered[i].Aliases);
end;

{ ===========================================================================
  PropFrameKeyOfObject  (function)
  Parameters:
    Obj: TDrawingObject - the drawing object
  Returns:
    String
  Notes:
    wire, bus, line, polygon, arc, rect and circle tell apart the kinds that share a class; any
    other object is its class name without TDraw, in lower case.
  =========================================================================== }
function PropFrameKeyOfObject(Obj: TDrawingObject): String;
begin
  if Obj is TDrawLine then
  begin
    case Obj.GetType of
      xWire: Result := 'wire';
      xBus: Result := 'bus';
    else
      Result := 'line';
    end;
  end
  else if Obj is TDrawPolygon then
  begin
    if IsArcPolygon(Obj) then
      Result := 'arc'
    else
      Result := 'polygon';
  end
  else if Obj is TDrawSquare then
  begin
    if Obj.GetType = xCircleEx3 then
      Result := 'circle'
    else
      Result := 'rect';
  end
  else if Obj is TDrawNoteText then
    Result := 'note'
  else
  begin
    Result := LowerCase(Obj.ClassName);
    if Copy(Result, 1, 5) = 'tdraw' then
      Delete(Result, 1, 5);
  end;
end;

{ ===========================================================================
  NormalName  (function)
  Parameters:
    const S: String - text
  Returns:
    String
  Notes:
    What names are compared as.
  =========================================================================== }
function NormalName(const S: String): String;
begin
  Result := LowerCase(StringReplace(StringReplace(S, '_', '', [rfReplaceAll]), '.', '', [rfReplaceAll]));
end;

{ ===========================================================================
  PropKeyOfControlName  (function)
  Parameters:
    const AName: String - the name
  Returns:
    String
  Notes:
    The longest property key (UProps.PropKeys, dot removed) the name ends with, so cbPinDir is
    pin.dir and not dir.
  =========================================================================== }
function PropKeyOfControlName(const AName: String): String;
var
  i: Integer;
  N, K: String;
begin
  Result := '';
  N := NormalName(AName);
  for i := 0 to High(PropKeys) do
  begin
    K := NormalName(PropKeys[i]);
    if (Length(N) >= Length(K)) and (Copy(N, Length(N) - Length(K) + 1, Length(K)) = K) then
      if (Result = '') or (Length(K) > Length(NormalName(Result))) then
        Result := PropKeys[i];
  end;
end;

{ ===========================================================================
  IsEditorClass  (function)
  Parameters:
    AControl: TControl
  Returns:
    Boolean
  Notes:
    Labels and panels that merely look like a property name are not editors. A button is one
    only as a toggle or a cycling button.
  =========================================================================== }
function IsEditorClass(AControl: TControl): Boolean;
begin
  Result := (AControl is TCustomFloatSpinEdit) or (AControl is TColorButton) or (AControl is TCustomComboBox) or (AControl is TCustomCheckBox)
    or (AControl is TCustomEdit) or (AControl is TCustomMemo) or (AControl is TSpeedButton);
end;

{ ===========================================================================
  ControlMode  (function)
  Parameters:
    const ADef: TPropDef
    AControl: TControl
  Returns:
    TBindMode
  Notes:
    See the unit's comment for the ways a choice can be edited.
  =========================================================================== }
function ControlMode(const ADef: TPropDef; AControl: TControl): TBindMode;
begin
  Result := bmNormal;
  if ADef.Kind <> pkChoice then
    Exit;
  if AControl is TRadioButton then
    Result := bmRadio
  else if AControl is TCustomCheckBox then
    Result := bmSwitch
  else if AControl is TSpeedButton then
  begin
    if ADef.Name = 'fill.type' then
      Result := bmFill
    else if ADef.Name = 'bus.phases' then
      Result := bmDrop
    else
      Result := bmCycle;
  end;
end;

{ ===========================================================================
  ControlProblem  (function)
  Parameters:
    const ADef: TPropDef
    AControl: TControl
  Returns:
    String
  Notes:
    Text is a TEdit (or a TComboBox), a whole number a TSpinEdit (or a TComboBox), a fractional
    number a TFloatSpinEdit, a color a TColorButton, a choice a TComboBox (a TCheckBox or a
    TSpeedButton also work: ControlMode) and a yes/no a TCheckBox or a TSpeedButton.
  =========================================================================== }
function ControlProblem(const ADef: TPropDef; AControl: TControl): String;
var
  Want: String;
  Fits: Boolean;
begin
  case ADef.Kind of
    pkText, pkMemo: begin
      Want := 'TEdit or TComboBox';
      Fits := (AControl.ClassType = TEdit) or (AControl is TCustomComboBox) or (AControl is TCustomMemo);
    end;
    pkInt: begin
      Want := 'TSpinEdit or TComboBox';
      Fits := (AControl is TSpinEdit) or (AControl is TCustomComboBox);
    end;
    pkFloat: begin
      Want := 'TFloatSpinEdit';
      Fits := AControl is TFloatSpinEdit;
    end;
    pkColor: begin
      Want := 'TColorButton';
      Fits := AControl is TColorButton;
    end;
    pkChoice: begin
      Want := 'TComboBox, TCheckBox or TSpeedButton';
      Fits := (AControl is TComboBox) or (AControl is TCustomCheckBox) or (AControl is TSpeedButton);
    end;
    pkBool: begin
      Want := 'TCheckBox or TSpeedButton';
      Fits := (AControl is TCustomCheckBox) or (AControl is TSpeedButton);
    end;
  else
    begin
      Want := '?';
      Fits := False;
    end;
  end;
  if Fits then
    Result := ''
  else
    Result := AControl.Name + ' is a ' + AControl.ClassName + ' but ' + ADef.Name + ' needs a ' + Want;
end;

{ ===========================================================================
  HideWith  (procedure)
  Parameters:
    AFrame: TFrame
    AControl: TControl
    const ACaptions: String - text
  Notes:
    Hides the control and its captions.
  =========================================================================== }
procedure HideWith(AFrame: TFrame; AControl: TControl; const ACaptions: String);
var
  L: TStringList;
  i: Integer;
  C: TComponent;
begin
  AControl.Visible := False;
  if ACaptions = '' then
    Exit;
  L := TStringList.Create;
  try
    L.CommaText := ACaptions;
    for i := 0 to L.Count - 1 do
    begin
      C := AFrame.FindComponent(Trim(L[i]));
      if C is TControl then
        TControl(C).Visible := False;
    end;
  finally
    L.Free;
  end;
end;

{ ===========================================================================
  HideEmptyPanels  (procedure)
  Parameters:
    AFrame: TFrame
  Notes:
    A panel or group box that holds editors and all of them are hidden is hidden with them (a
    caption and its editor in a panel of their own disappear together); one with a visible
    editor stays.
  =========================================================================== }
procedure HideEmptyPanels(AFrame: TFrame);
var
  i, k: Integer;
  P: TWinControl;
  Editors, Shown: Integer;
begin
  for i := 0 to AFrame.ComponentCount - 1 do
  begin
    if not ((AFrame.Components[i] is TPanel) or (AFrame.Components[i] is TGroupBox)) then
      Continue;
    P := TWinControl(AFrame.Components[i]);
    Editors := 0; Shown := 0;
    for k := 0 to P.ControlCount - 1 do
      if IsEditorClass(P.Controls[k]) then
      begin
        Inc(Editors);
        if P.Controls[k].Visible then
          Inc(Shown);
      end;
    if (Editors > 0) and (Shown = 0) then
      P.Visible := False;
  end;
end;

{ ===========================================================================
  BindPropFrame  (function)
  Parameters:
    AFrame: TFrame
    const Defs: TPropDefArray
    Aliases: TStrings
    out Bindings: TFrameBindings - out: set by the call
    Problems: TStrings
  Returns:
    Integer
  Notes:
    Goes through the controls of the frame in the order they were made. A control is an editor
    of the property its alias names, else of the property its name ends with (a control with
    neither is left alone). It is linked when the tool or selection has the property, and hidden
    (with its captions) when it has not. An editor of the wrong class is disabled; an editor for
    a property that another one has already taken is disabled too (a check box for a choice may
    share it); both are reported in Problems. Afterwards a panel with no visible editor left is
    hidden.
  =========================================================================== }
function BindPropFrame(AFrame: TFrame; const Defs: TPropDefArray; Aliases: TStrings; out Bindings: TFrameBindings; Problems: TStrings): Integer;
var
  i, k, N, P: Integer;
  C: TControl;
  Key, Msg, Caps, Line: String;
  Taken: TStringList;
  M: TBindMode;
begin
  SetLength(Bindings, 0);
  Taken := TStringList.Create;
  try
    for i := 0 to AFrame.ComponentCount - 1 do
    begin
      if not (AFrame.Components[i] is TControl) then
        Continue;
      C := TControl(AFrame.Components[i]);
      if not IsEditorClass(C) then
        Continue;
      Key := ''; Caps := '';
      if Aliases <> nil then
      begin
        Line := Aliases.Values[C.Name];
        if (Line = '') and (Aliases.IndexOfName(C.Name) >= 0) then
          Continue;       // 'control=': not an editor
        if Line <> '' then
        begin
          P := Pos(':', Line);
          if P > 0 then begin
            Caps := Copy(Line, P + 1, MaxInt);
            Key := Copy(Line, 1, P - 1);
          end
          else
            Key := Line;
        end;
      end;
      if Key = '' then
        Key := PropKeyOfControlName(C.Name);
      if Key = '' then
        Continue;
      k := -1;
      for N := 0 to High(Defs) do
        if Defs[N].Name = Key then
          k := N;
      if k < 0 then
      begin
        HideWith(AFrame, C, Caps);      // the tool or selection has no such property
        Continue;
      end;
      M := ControlMode(Defs[k], C);
      if (Taken.IndexOf(Key) >= 0) and (M <> bmSwitch) and (M <> bmRadio) then
      begin
        if Problems <> nil then
          Problems.Add(C.Name + ': ' + Key + ' is already edited by another control');
        C.Enabled := False;
        Continue;
      end;
      Msg := ControlProblem(Defs[k], C);
      if Msg <> '' then
      begin
        if Problems <> nil then
          Problems.Add(Msg);
        C.Enabled := False;
        Continue;
      end;
      if (M <> bmSwitch) and (M <> bmRadio) then
        Taken.Add(Key);
      C.Visible := True;
      SetLength(Bindings, Length(Bindings) + 1);
      with Bindings[High(Bindings)] do
      begin
        Def := Defs[k];
        Control := C;
        Mode := M;
      end;
    end;
  finally
    Taken.Free;
  end;
  HideEmptyPanels(AFrame);
  Result := Length(Bindings);
end;

finalization
  UnregisterPropFrames;
end.
