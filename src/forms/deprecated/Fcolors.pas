{ The Colors dialog (TinyCAD's Options > Colors): the colors a schematic is drawn in - the background, wires, buses, junctions,
  no-connect marks, pins, power symbols and the three colors of a note - each shown as a swatch with a button to change it, and a
  button to go back to the standard colors. The dialog only holds the colors; the main form applies them to the design and
  keeps the ones that differ from the standard colors as the user's own for new designs. (Two colors that the design also has,
  those of net labels and of the pins of power symbols, are not in the dialog, as in TinyCAD; they are carried through unchanged.)

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fcolors;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UDrawTypes, UResources;

type
  TColorIds = array of Integer;     // color ids (UC_*)

  { TfrmColors }

  TfrmColors = class(TfrmBase)
    btnReset: TButton;
    ColorDlg: TColorDialog;
    pnlColors: TPanel;
    lblBackground: TLabel;
    pnlBackground: TPanel;
    btnBackground: TButton;
    lblWires: TLabel;
    pnlWires: TPanel;
    btnWires: TButton;
    lblBuses: TLabel;
    pnlBuses: TPanel;
    btnBuses: TButton;
    lblJunctions: TLabel;
    pnlJunctions: TPanel;
    btnJunctions: TButton;
    lblNoConnect: TLabel;
    pnlNoConnect: TPanel;
    btnNoConnect: TButton;
    lblPins: TLabel;
    pnlPins: TPanel;
    btnPins: TButton;
    lblPower: TLabel;
    pnlPower: TPanel;
    btnPower: TButton;
    lblNoteFill: TLabel;
    pnlNoteFill: TPanel;
    btnNoteFill: TButton;
    lblNoteLine: TLabel;
    pnlNoteLine: TPanel;
    btnNoteLine: TButton;
    lblNoteText: TLabel;
    pnlNoteText: TPanel;
    btnNoteText: TButton;
    procedure FormCreate(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure ChangeClick(Sender: TObject);
  private
    FColors: array[UC_WIRE..UC_NOTETEXT_TEXT] of Cardinal;
    FSwatch: array[UC_WIRE..UC_NOTETEXT_TEXT] of TPanel;
  public
    { the colors that can be changed here, in the order they are listed }
    class function ListedIds: TColorIds;
    class function ColorName(Id: Integer): String;
    procedure LoadColors(Source: TUserColors);
    function ColorOf(Id: Integer): Cardinal;
    { give a color a value, as choosing it does }
    procedure SetColor(Id: Integer; AColor: Cardinal);
    { ask the user for a color for one (the system color chooser) }
    procedure ChooseColor(Id: Integer);
    { all the colors back to the standard ones }
    procedure ResetToStandard;
  end;

var
  frmColors: TfrmColors;

implementation

{$R *.lfm}

{ ===========================================================================
  TfrmColors.ListedIds  (function)
  Parameters:  none
  Returns:
    TColorIds - the ids
  Notes:
    The ids of the colors the dialog lists, in the order they are shown.
  =========================================================================== }
class function TfrmColors.ListedIds: TColorIds;
begin
  SetLength(Result, 10);
  Result[0] := UC_BACKGROUND;
  Result[1] := UC_WIRE;
  Result[2] := UC_BUS;
  Result[3] := UC_JUNCTION;
  Result[4] := UC_NOCONNECT;
  Result[5] := UC_PIN;
  Result[6] := UC_POWER;
  Result[7] := UC_NOTETEXT_FILL;
  Result[8] := UC_NOTETEXT_LINE;
  Result[9] := UC_NOTETEXT_TEXT;
end;

{ ===========================================================================
  TfrmColors.ColorName  (function)
  Parameters:
    Id: Integer - the color's id
  Returns:
    String - its name, empty for a color that is not listed
  Notes:
    What a color is called in the dialog (Background, Wires, Buses ...).
  =========================================================================== }
class function TfrmColors.ColorName(Id: Integer): String;
begin
  case Id of
    UC_BACKGROUND: Result := 'Background';
    UC_WIRE: Result := 'Wires';
    UC_BUS: Result := 'Buses';
    UC_JUNCTION: Result := 'Junctions';
    UC_NOCONNECT: Result := 'No-connect marks';
    UC_PIN: Result := 'Pins';
    UC_POWER: Result := 'Power symbols';
    UC_NOTETEXT_FILL: Result := 'Note background';
    UC_NOTETEXT_LINE: Result := 'Note border';
    UC_NOTETEXT_TEXT: Result := 'Note text';
  else
    Result := '';
  end;
end;

{ ===========================================================================
  TfrmColors.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The rows of the dialog (a name, a swatch showing the color and a Change button for each
    listed color) are made in the form designer; the Tag of a swatch and of its button is the
    color's id. This only lists the swatches by id so that a color can find its swatch.
  =========================================================================== }
procedure TfrmColors.FormCreate(Sender: TObject);
var
  i: Integer;
  C: TComponent;
begin
  for i := 0 to ComponentCount - 1 do
  begin
    C := Components[i];
    if (C is TPanel) and (C <> pnlColors) and (C.Tag >= Low(FSwatch)) and (C.Tag <= High(FSwatch)) then
      FSwatch[C.Tag] := TPanel(C);
  end;
end;

{ ===========================================================================
  TfrmColors.LoadColors  (procedure)
  Parameters:
    Source: TUserColors
  Notes:
    Takes all twelve colors of a design (the two that are not listed are only carried) and shows
    the listed ones.
  =========================================================================== }
procedure TfrmColors.LoadColors(Source: TUserColors);
var
  Id: Integer;
begin
  for Id := UC_WIRE to UC_NOTETEXT_TEXT do
  begin
    FColors[Id] := Source.Get(Id);
    if FSwatch[Id] <> nil then
      FSwatch[Id].Color := TColor(FColors[Id] and $FFFFFF);
  end;
end;

{ ===========================================================================
  TfrmColors.ColorOf  (function)
  Parameters:
    Id: Integer - the color's id
  Returns:
    Cardinal - the color
  Notes:
    The color now held for an id.
  =========================================================================== }
function TfrmColors.ColorOf(Id: Integer): Cardinal;
begin
  Result := FColors[Id];
end;

{ ===========================================================================
  TfrmColors.SetColor  (procedure)
  Parameters:
    Id: Integer - the color's id
    AColor: Cardinal
  Notes:
    Gives a color a value, as choosing it does, and shows it on its swatch. An id that is not a
    color of a design is ignored.
  =========================================================================== }
procedure TfrmColors.SetColor(Id: Integer; AColor: Cardinal);
begin
  if (Id < UC_WIRE) or (Id > UC_NOTETEXT_TEXT) then
    Exit;
  FColors[Id] := AColor and $FFFFFF;
  if FSwatch[Id] <> nil then
    FSwatch[Id].Color := TColor(FColors[Id]);
end;

{ ===========================================================================
  TfrmColors.ChooseColor  (procedure)
  Parameters:
    Id: Integer - the color's id
  Notes:
    Asks for a color for one id with the form's color dialog (ColorDlg, a TColorDialog placed on
    the form at design time), starting from the one it has; if one is chosen it is set. An id
    that is not a color of a design is ignored.
  =========================================================================== }
procedure TfrmColors.ChooseColor(Id: Integer);
begin
  if (Id < UC_WIRE) or (Id > UC_NOTETEXT_TEXT) then
    Exit;
  ColorDlg.Color := TColor(FColors[Id] and $FFFFFF);
  if ColorDlg.Execute then
    SetColor(Id, Cardinal(ColorDlg.Color));
end;

{ ===========================================================================
  TfrmColors.ChangeClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    A Change button was pressed: choose the color of its row.
  =========================================================================== }
procedure TfrmColors.ChangeClick(Sender: TObject);
begin
  ChooseColor((Sender as TComponent).Tag);
end;

{ ===========================================================================
  TfrmColors.ResetToStandard  (procedure)
  Parameters:  none
  Notes:
    Puts every color, listed or not, back to the standard colors TinyCAD starts with (the user's
    own colors for new designs are not used here: this is the factory's).
  =========================================================================== }
procedure TfrmColors.ResetToStandard;
var
  T: TUserColors;
  Id: Integer;
begin
  T := TUserColors.Create;
  try
    T.Init;
    for Id := UC_WIRE to UC_NOTETEXT_TEXT do SetColor(Id, T.Get(Id));
  finally
    T.Free;
  end;
end;

{ ===========================================================================
  TfrmColors.ResetClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    The Reset button was pressed: all the colors go back to the standard ones.
  =========================================================================== }
procedure TfrmColors.ResetClick(Sender: TObject);
begin
  ResetToStandard;
end;

end.
