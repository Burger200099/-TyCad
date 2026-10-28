// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Options dialog (TinyCAD's View > Options): three pages, as TinyCAD has them.
    Grid       the spacing of the grid (in the units chosen below, or one of the usual sizes), whether it is shown and whether
               it is snapped to, and whether lengths are shown in millimetres or inches
    Auto-snap  auto drag (moving an object drags the wires attached to it), auto snap (and its range) and auto junctions
    Auto-save  whether a copy of every named design is saved regularly, and how often
  The dialog only holds and checks the values (UOptions.TOptionsData); the main form applies them. OK checks them and
  keeps the dialog open if they cannot be used; Apply does the same and then asks the owner to apply them now.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Foptions;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Buttons, Fbase, UOptions, consts, UDrawTypes, UResources,
  CFontNameCombo;

type

  TColorIds = array of Integer;     // color ids (UC_*)

  { TfrmOptions }

  TfrmOptions = class(TfrmBase)
    btnBackground: TButton;
    btnBuses: TButton;
    btnJunctions: TButton;
    btnNoConnect: TButton;
    btnNoteFill: TButton;
    btnNoteLine: TButton;
    btnNoteText: TButton;
    btnPins: TButton;
    btnPower: TButton;
    btnReset: TButton;
    btnWires: TButton;
    cbAutoDrag: TCheckBox;
    cbAutoJunction: TCheckBox;
    cbReopen: TCheckBox;
    cbAutoSave: TCheckBox;
    cbAutoSnap: TCheckBox;
    cbPreset: TComboBox;
    cbSymbolFont: TFontNameCombo;
    cbSheetDetailsBorder: TCheckBox;
    cbSheetDetailsShowRuler: TCheckBox;
    cbSymbolSize: TComboBox;
    lblSymbolSample: TLabel;
    lblSymbolSize: TLabel;
    cbShowGrid: TCheckBox;
    cbSnapGrid: TCheckBox;
    edGrid: TEdit;
    edMinutes: TEdit;
    edSheetDetailsCols: TEdit;
    edSheetDetailsMargin: TEdit;
    edSheetDetailsRows: TEdit;
    edRange: TEdit;
    Label8: TLabel;
    lbSheetDetailsCols: TLabel;
    lbSheetDetailsMargin: TLabel;
    lbSheetDetailsRows: TLabel;
    Panel1: TPanel;
    tbSheets: TToggleBox;
    tsSheets: TTabSheet;
    gbSymbolFonts: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    lblBackground: TLabel;
    lblBuses: TLabel;
    lblGridUnits: TLabel;
    lblJunctions: TLabel;
    lblNoConnect: TLabel;
    lblNoteFill: TLabel;
    lblNoteLine: TLabel;
    lblNoteText: TLabel;
    lblPins: TLabel;
    lblPower: TLabel;
    lblReopenNote: TLabel;
    lblSaveNote: TLabel;
    lblWires: TLabel;
    pnlBackground: TPanel;
    pnlBuses: TPanel;
    pnlColors: TPanel;
    pnlJunctions: TPanel;
    pnlNavigation: TPanel;
    pcOptions: TPageControl;
    pnlNoConnect: TPanel;
    pnlNoteFill: TPanel;
    pnlNoteLine: TPanel;
    pnlNoteText: TPanel;
    pnlPins: TPanel;
    pnlPower: TPanel;
    pnlWires: TPanel;
    rgUnits: TRadioGroup;
    sbBold: TSpeedButton;
    sbItalic: TSpeedButton;
    TabSheet1: TTabSheet;
    tbFonts: TToggleBox;
    tsColors: TTabSheet;
    tbColors: TToggleBox;
    tbGrid: TToggleBox;
    tbAutosave: TToggleBox;
    tsAutoSave: TTabSheet;
    tsGrid: TTabSheet;
    procedure AutoSaveClick(Sender: TObject);
    procedure AutoSnapClick(Sender: TObject);
    procedure ChangeClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure GridTextChange(Sender: TObject);
    procedure PresetChange(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure SelectTab(Sender: TObject);
    procedure SheetBorderClick(Sender: TObject);
    procedure SheetRulerClick(Sender: TObject);
    procedure SymbolFontChange(Sender: TObject);
    procedure UnitsClick(Sender: TObject);
    procedure OptionsActivate(Sender: TObject);
    procedure ApplyClicked(Sender: TObject);
  private
    FUnits: Integer;            // the units the grid spacing is shown in now
    FBusy: Boolean;             // the dialog is changing its own controls
    FShownMm: Double;           // the spacing, exactly, that the grid box was last filled with by the dialog itself ...
    FShownText: String;         // ... and the text it was shown as (the box is read back exactly while it still says that)
    FColors: array[UC_WIRE..UC_NOTETEXT_TEXT] of Cardinal;
    FSwatch: array[UC_WIRE..UC_NOTETEXT_TEXT] of TPanel;
    FDefaultColorsTab: boolean;
    procedure ShowGridMm(Mm: Double);
    procedure FillPresets;
    procedure ShowPresetFor(Mm: Double);
    procedure ShowSymbolSample;
    function RowLetter(N: Integer): String;
  public
    OnApplyRequest: TNotifyEvent;     // the Apply button: apply the dialog's values now
    procedure LoadFromData(const D: TOptionsData);
    { read the dialog; returns what is wrong with it, or '' }
    function ReadData(out D: TOptionsData): String;
    function ValidationError: String;
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
    property DefaultColorsTab: boolean read FDefaultColorsTab write FDefaultColorsTab;
  end;

var
  frmOptions: TfrmOptions;

implementation

uses UStrings, FSharedCtls;

{$R *.lfm}

{ ===========================================================================
  TfrmOptions.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Shows the OK, Cancel and Apply buttons (when the form is activated) and gives Apply its
    handler. Color Stuff:     The rows of the dialog (a name, a swatch showing the color and a
    Change button for each listed color) are made in the form designer; the Tag of a swatch and
    of its button is the color's id. This only lists the swatches by id so that a color can find
    its swatch.
  =========================================================================== }
procedure TfrmOptions.FormCreate(Sender: TObject);
var
  i: Integer;
  C: TComponent;
begin
  rgUnits.Items[0] := rsMillimetres;      // (the radio group's items are not translated with the form's captions)
  rgUnits.Items[1] := rsInches;
//  OnActivate := @OptionsActivate;
//  btnApply.OnClick := @ApplyClicked;
  if FDefaultColorsTab then
    begin
      pcOptions.ActivePage := tsColors;
      tbColors.Checked := true;
    end
  else
    begin
      pcOptions.ActivePage := tsGrid;
      tbGrid.Checked := true;
    end;
  FUnits := UNITS_MM;
  // color stuff
  for i := 0 to ComponentCount - 1 do
  begin
    C := Components[i];
    if (C is TPanel) and (C <> pnlColors) and (C.Tag >= Low(FSwatch)) and (C.Tag <= High(FSwatch)) then
      FSwatch[C.Tag] := TPanel(C);
  end;

end;

{ ===========================================================================
  TfrmOptions.OptionsActivate  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    Shows the OK, Cancel and Apply buttons when the dialog is activated (the base form shows
    only OK and Cancel).
  =========================================================================== }
procedure TfrmOptions.OptionsActivate(Sender: TObject);
begin
  SetButtons([fcbOK, fcbCancel, fcbApply]);
  pnlNavigation.Caption := '';
  pcOptions.ShowTabs := false;
end;

{ ===========================================================================
  TfrmOptions.ApplyClicked  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    The Apply button: if what is in the dialog can be used, asks the owner to apply it now and
    leaves the dialog open; otherwise says what is wrong.
  =========================================================================== }
procedure TfrmOptions.ApplyClicked(Sender: TObject);
var
  Err: String;
begin
  Err := ValidationError;
  if Err <> '' then
  begin
    MessageDlg(rsOptions, Err, mtWarning, [mbOK], 0);
    Exit;
  end;
  if Assigned(OnApplyRequest) then
    OnApplyRequest(Self);
end;

{ ===========================================================================
  TfrmOptions.FillPresets  (procedure)
  Parameters:  none
  Notes:
    Lists the usual grid sizes in the units now chosen, after "Custom".
  =========================================================================== }
procedure TfrmOptions.FillPresets;
var
  i: Integer;
begin
  cbPreset.Items.Clear;
  cbPreset.Items.Add(rsCustom);
  for i := 0 to High(GridSizeMM) do cbPreset.Items.Add(LengthText(GridSizeMM[i] / 1000, FUnits));
end;

{ ===========================================================================
  TfrmOptions.ShowPresetFor  (procedure)
  Parameters:
    Mm: Double - number
  Notes:
    Selects the usual size that is the same as it, or Custom if there is none.
  =========================================================================== }
procedure TfrmOptions.ShowPresetFor(Mm: Double);
var
  i, Found: Integer;
begin
  Found := 0;
  for i := 0 to High(GridSizeMM) do
    if Abs(GridSizeMM[i] / 1000 - Mm) < 0.0005 then
      Found := i + 1;
  FBusy := True;
  try
    cbPreset.ItemIndex := Found;
  finally
    FBusy := False;
  end;
end;

{ ===========================================================================
  TfrmOptions.LoadFromData  (procedure)
  Parameters:
    const D: TOptionsData
  Notes:
    Puts the values into the controls. The grid spacing is shown in the units of D.
  =========================================================================== }
procedure TfrmOptions.LoadFromData(const D: TOptionsData);
begin
  FBusy := True;
  try
    FUnits := D.Units;
    rgUnits.ItemIndex := D.Units;
    lblGridUnits.Caption := UnitsSuffix(FUnits);
    FillPresets;
    ShowGridMm(D.GridMm);
    cbShowGrid.Checked := D.ShowGrid;
    cbSnapGrid.Checked := D.SnapGrid;
    cbAutoDrag.Checked := D.AutoDrag;
    cbAutoSnap.Checked := D.AutoSnap;
    cbAutoJunction.Checked := D.AutoJunction;
    cbReopen.Checked := D.ReopenDesigns;
    edRange.Text := IntToStr(D.AutoSnapRange);
    edRange.Enabled := D.AutoSnap;
    cbAutoSave.Checked := D.AutoSaveMinutes > 0;
    if D.AutoSaveMinutes > 0 then
      edMinutes.Text := IntToStr(D.AutoSaveMinutes)
    else
      edMinutes.Text := '10';
    edMinutes.Enabled := D.AutoSaveMinutes > 0;
    cbSymbolFont.FontName := D.SymbolFontName;
    cbSymbolSize.Text := IntToStr(D.SymbolFontPoints);
    sbBold.Down := D.SymbolFontBold;
//    cbSymbolBold.Checked := D.SymbolFontBold;
    sbItalic.Down := D.SymbolFontItalic;
//    cbSymbolItalic.Checked := D.SymbolFontItalic;
    cbSheetDetailsBorder.Checked := D.SheetBorder;
    cbSheetDetailsShowRuler.Checked := D.SheetRulers;
    edSheetDetailsCols.Text := IntToStr(D.SheetCols);
    edSheetDetailsRows.Text := RowLetter(D.SheetRows);
    edSheetDetailsMargin.Text := NumberText(D.SheetMarginMm);
    edSheetDetailsMargin.Enabled := D.SheetBorder;
    edSheetDetailsCols.Enabled := D.SheetRulers;
    edSheetDetailsRows.Enabled := D.SheetRulers;
  finally
    FBusy := False;
  end;
  ShowPresetFor(D.GridMm);
  ShowSymbolSample;
end;

{ ===========================================================================
  TfrmOptions.ShowGridMm  (procedure)
  Parameters:
    Mm: Double - number
  Notes:
    Puts the spacing in the box in the units now chosen, and remembers it exactly, so that
    ReadData can give back the very same value if the person does not change the number.
  =========================================================================== }
procedure TfrmOptions.ShowGridMm(Mm: Double);
begin
  FShownMm := Mm;
  FShownText := NumberText(MmToUnits(Mm, FUnits));
  edGrid.Text := FShownText;
end;

{ ===========================================================================
  TfrmOptions.ReadData  (function)
  Parameters:
    out D: TOptionsData - out: set by the call
  Returns:
    String
  Notes:
    The Sheets page (what a new design's sheet starts with) is read too: the last row is a letter A to Z, the margin is in millimetres. The grid spacing is turned back into millimetres. The interval is 0 (no automatic save) when
    the box is not ticked.
  =========================================================================== }
function TfrmOptions.ReadData(out D: TOptionsData): String;
var
  V: Double;
  N: Integer;
  S: String;
begin
  FillChar(D, SizeOf(D), 0);
  D.Units := rgUnits.ItemIndex;
  D.ShowGrid := cbShowGrid.Checked;
  D.SnapGrid := cbSnapGrid.Checked;
  D.AutoDrag := cbAutoDrag.Checked;
  D.AutoSnap := cbAutoSnap.Checked;
  D.AutoJunction := cbAutoJunction.Checked;
  D.ReopenDesigns := cbReopen.Checked;
  if not ParseNumber(edGrid.Text, V) then
  begin
    D.GridMm := 0;
    Exit(rsTheGridSpacingIsNot);
  end;
  { a spacing that the dialog filled in and that has not been typed over is exactly what it was: changing the units turns it into a rounded
    number of the other units, and turning that back would otherwise change a 5 mm grid into 4.99999 mm }
  if (Trim(edGrid.Text) = FShownText) and (D.Units = FUnits) then
    D.GridMm := FShownMm
  else
    D.GridMm := UnitsToMm(V, D.Units);
  N := StrToIntDef(Trim(edRange.Text), -1);
  if N < 0 then
  begin
    D.AutoSnapRange := 0;
    Exit(rsTheAutoSnapRangeIs);
  end;
  D.AutoSnapRange := N;
  D.SymbolFontName := Trim(cbSymbolFont.FontName);
  D.SymbolFontPoints := StrToIntDef(Trim(cbSymbolSize.Text), 0);
  D.SymbolFontBold := sbBold.Down; //cbSymbolBold.Checked;
  D.SymbolFontItalic := sbItalic.Down;  //cbSymbolItalic.Checked;
  D.SheetBorder := cbSheetDetailsBorder.Checked;
  D.SheetRulers := cbSheetDetailsShowRuler.Checked;
  D.SheetCols := StrToIntDef(Trim(edSheetDetailsCols.Text), 0);
  S := Trim(edSheetDetailsRows.Text);
  D.SheetRows := 0;
  if (Length(S) = 1) and (UpCase(S[1]) in ['A'..'Z']) then
    D.SheetRows := Ord(UpCase(S[1])) - Ord('A') + 1;
  if not ParseNumber(edSheetDetailsMargin.Text, D.SheetMarginMm) then
    D.SheetMarginMm := -1;
  if cbAutoSave.Checked then
  begin
    N := StrToIntDef(Trim(edMinutes.Text), -1);
    if N < 0 then
    begin
      D.AutoSaveMinutes := 0;
      Exit(rsTheTimeBetweenAutomaticSaves);
    end;
    D.AutoSaveMinutes := N;
    if N = 0 then
      Exit(Format(rsTheTimeBetweenAutomaticSaves2, [AUTOSAVE_MAX_MINUTES]));
  end
  else
    D.AutoSaveMinutes := 0;
  Result := OptionsError(D);
end;

{ ===========================================================================
  TfrmOptions.ValidationError  (function)
  Parameters:  none
  Returns:
    String - the message
  Notes:
    What is wrong with what the dialog holds, or an empty string if it can be used.
  =========================================================================== }
function TfrmOptions.ValidationError: String;
var
  D: TOptionsData;
begin
  Result := ReadData(D);
end;

{ ===========================================================================
  TfrmOptions.ListedIds  (function)
  Parameters:  none
  Returns:
    TColorIds - the ids
  Notes:
    The ids of the colors the dialog lists, in the order they are shown.
  =========================================================================== }
class function TfrmOptions.ListedIds: TColorIds;
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
  TfrmOptions.ColorName  (function)
  Parameters:
    Id: Integer - the color's id
  Returns:
    String - its name, empty for a color that is not listed
  Notes:
    What a color is called in the dialog (Background, Wires, Buses ...).
  =========================================================================== }
class function TfrmOptions.ColorName(Id: Integer): String;
begin
  case Id of
    UC_BACKGROUND: Result := 'Background';
    UC_WIRE: Result := 'Wires';
    UC_BUS: Result := 'Buses';
    UC_JUNCTION: Result := 'Junctions';
    UC_NOCONNECT: Result := rsNoConnectMarks;
    UC_PIN: Result := rsPins;
    UC_POWER: Result := rsPowerSymbols;
    UC_NOTETEXT_FILL: Result := rsNoteBackground;
    UC_NOTETEXT_LINE: Result := rsNoteBorder;
    UC_NOTETEXT_TEXT: Result := rsNoteText;
  else
    Result := '';
  end;
end;

{ ===========================================================================
  TfrmOptions.LoadColors  (procedure)
  Parameters:
    Source: TUserColors
  Notes:
    Takes all twelve colors of a design (the two that are not listed are only carried) and shows
    the listed ones.
  =========================================================================== }
procedure TfrmOptions.LoadColors(Source: TUserColors);
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
  TfrmOptions.ColorOf  (function)
  Parameters:
    Id: Integer - the color's id
  Returns:
    Cardinal - the color
  Notes:
    The color now held for an id.
  =========================================================================== }
function TfrmOptions.ColorOf(Id: Integer): Cardinal;
begin
  Result := FColors[Id];
end;

{ ===========================================================================
  TfrmOptions.SetColor  (procedure)
  Parameters:
    Id: Integer - the color's id
    AColor: Cardinal - Cardinal
  Notes:
    Gives a color a value, as choosing it does, and shows it on its swatch. An id that is not a
    color of a design is ignored.
  =========================================================================== }
procedure TfrmOptions.SetColor(Id: Integer; AColor: Cardinal);
begin
  if (Id < UC_WIRE) or (Id > UC_NOTETEXT_TEXT) then
    Exit;
  FColors[Id] := AColor and $FFFFFF;
  if FSwatch[Id] <> nil then
    FSwatch[Id].Color := TColor(FColors[Id]);
end;

{ ===========================================================================
  TfrmOptions.ChooseColor  (procedure)
  Parameters:
    Id: Integer - the color's id
  Notes:
    Asks for a color for one id with the form's color dialog (ColorDlg, a TColorDialog placed on
    the form at design time), starting from the one it has; if one is chosen it is set. An id
    that is not a color of a design is ignored.
  =========================================================================== }
procedure TfrmOptions.ChooseColor(Id: Integer);
begin
  if (Id < UC_WIRE) or (Id > UC_NOTETEXT_TEXT) then
    Exit;
  frmSharedControls.DlgColor.Color := TColor(FColors[Id] and $FFFFFF);
  if frmSharedControls.DlgColor.Execute then
    SetColor(Id, Cardinal(frmSharedControls.DlgColor.Color));
end;

{ ===========================================================================
  TfrmOptions.ResetToStandard  (procedure)
  Parameters:  none
  Notes:
    Puts every color, listed or not, back to the standard colors TinyCAD starts with (the user's
    own colors for new designs are not used here: this is the factory's).
  =========================================================================== }
procedure TfrmOptions.ResetToStandard;
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
  TfrmOptions.FormCloseQuery  (procedure)
  Parameters:
    Sender: TObject - the form
    var CanClose: Boolean - set False to keep the dialog open
  Notes:
    Pressing OK checks the values first: if they cannot be used a message says why and the
    dialog stays open.
  =========================================================================== }
procedure TfrmOptions.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Err: String;
begin
  if ModalResult <> mrOK then
    Exit;
  Err := ValidationError;
  if Err <> '' then
  begin
    MessageDlg(rsOptions, Err, mtWarning, [mbOK], 0);
    CanClose := False;
    ModalResult := mrNone;
  end;
end;

{ ===========================================================================
  TfrmOptions.UnitsClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Changing the units converts the grid spacing in the box to the new units (the spacing itself
    is not changed) and relists the usual sizes, as TinyCAD's Grid page does.
  =========================================================================== }
procedure TfrmOptions.UnitsClick(Sender: TObject);
var
  V, Mm: Double;
begin
  if FBusy or (rgUnits.ItemIndex = FUnits) then
    Exit;
  if ParseNumber(edGrid.Text, V) then
  begin
    if Trim(edGrid.Text) = FShownText then
      Mm := FShownMm
    else
      Mm := UnitsToMm(V, FUnits);     // (exactly, if the box has not been typed over)
    FUnits := rgUnits.ItemIndex;
    FBusy := True;
    try
      lblGridUnits.Caption := UnitsSuffix(FUnits);
      FillPresets;
      ShowGridMm(Mm);
    finally
      FBusy := False;
    end;
    ShowPresetFor(Mm);
  end
  else
  begin
    FUnits := rgUnits.ItemIndex;
    lblGridUnits.Caption := UnitsSuffix(FUnits);
    FBusy := True;
    try
      FillPresets;
    finally
      FBusy := False;
    end;
  end;
end;

{ ===========================================================================
  TfrmOptions.PresetChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Choosing one of the usual sizes puts it in the spacing box.
  =========================================================================== }
procedure TfrmOptions.PresetChange(Sender: TObject);
begin
  if FBusy or (cbPreset.ItemIndex < 1) then
    Exit;
  FBusy := True;
  try
    ShowGridMm(GridSizeMM[cbPreset.ItemIndex - 1] / 1000);
  finally
    FBusy := False;
  end;
end;

{ ===========================================================================
  TfrmOptions.ResetClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    The Reset button was pressed: all the colors go back to the standard ones.
  =========================================================================== }
procedure TfrmOptions.ResetClick(Sender: TObject);
begin
  ResetToStandard;
end;

{ ===========================================================================
  TfrmOptions.SelectTab  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Pick the tab based on togglebutton.
  =========================================================================== }
procedure TfrmOptions.SelectTab(Sender: TObject);
begin
  // dump event
  tbGrid.OnChange := nil;
  tbAutoSave.OnChange := nil;
  tbColors.OnChange := nil;
  tbFonts.OnChange := nil;
  tbSheets.OnChange := nil;
  //process changes
  tbGrid.Checked := Sender = tbGrid;
  tbAutoSave.Checked := Sender = tbAutosave;
  tbColors.Checked := Sender = tbColors;
  tbFonts.Checked := Sender = tbFonts;
  tbSheets.Checked := Sender = tbSheets;
  if tbGrid.Checked then
    pcOptions.ActivePageIndex := 0
  else if tbAutosave.Checked then
    pcOptions.ActivePageIndex := 1
  else if tbColors.Checked then
    pcOptions.ActivePageIndex := 2
  else if tbFonts.Checked then
    pcOptions.ActivePageIndex := 3
  else if tbSheets.Checked then
    pcOptions.ActivePageIndex := 4;
  //reassign event
  tbGrid.OnChange := @SelectTab;
  tbAutosave.OnChange := @SelectTab;
  tbColors.OnChange := @SelectTab;
  tbFonts.OnChange := @SelectTab;
  tbSheets.OnChange := @SelectTab;
end;

{ ===========================================================================
  TfrmOptions.RowLetter  (function)
  Parameters:
    N: Integer - the number of rows, 1 to 26
  Returns:
    String - the letter of the last row (A to Z), '' for a number out of range
  Notes:
    The rulers number their columns and letter their rows, so the Sheets page asks for "the last row" as a letter, as the Details drop-down of the ribbon does.
  =========================================================================== }
function TfrmOptions.RowLetter(N: Integer): String;
begin
  if (N >= 1) and (N <= 26) then
    Result := Chr(Ord('A') + N - 1)
  else
    Result := '';
end;

{ ===========================================================================
  TfrmOptions.SheetBorderClick  (procedure)
  Parameters:
    Sender: TObject - the Show Border box
  Notes:
    The margin of the border is only entered while a new sheet gets a border.
  =========================================================================== }
procedure TfrmOptions.SheetBorderClick(Sender: TObject);
begin
  edSheetDetailsMargin.Enabled := cbSheetDetailsBorder.Checked;
end;

{ ===========================================================================
  TfrmOptions.SheetRulerClick  (procedure)
  Parameters:
    Sender: TObject - the Show rulers box
  Notes:
    The numbers of columns and rows are only entered while a new sheet gets rulers.
  =========================================================================== }
procedure TfrmOptions.SheetRulerClick(Sender: TObject);
begin
  edSheetDetailsCols.Enabled := cbSheetDetailsShowRuler.Checked;
  edSheetDetailsRows.Enabled := cbSheetDetailsShowRuler.Checked;
end;

{ ===========================================================================
  TfrmOptions.ShowSymbolSample  (procedure)
  Notes:
    Shows a reference in the font now chosen (face, size in points, bold, italic) under the font boxes, so the choice can be seen before it is applied. A size that is not a number
    is left out (the sample keeps the last size; ReadData says what is wrong).
  =========================================================================== }
procedure TfrmOptions.ShowSymbolSample;
var
  P: Integer;
  St: TFontStyles;
begin
  if cbSymbolFont.FontName <> '' then
    lblSymbolSample.Font.Name := cbSymbolFont.FontName;
  P := StrToIntDef(Trim(cbSymbolSize.Text), 0);
  if (P >= SYMBOL_FONT_MIN_POINTS) and (P <= SYMBOL_FONT_MAX_POINTS) then
    lblSymbolSample.Font.Size := P;
  St := [];
  if sbBold.Down then
    Include(St, fsBold);
  if sbItalic.Down then
    Include(St, fsItalic);
  lblSymbolSample.Font.Style := St;
end;

{ ===========================================================================
  TfrmOptions.SymbolFontChange  (procedure)
  Parameters:
    Sender: TObject - the font, size, bold or italic control
  Notes:
    Any of the font controls changed: the sample follows.
  =========================================================================== }
procedure TfrmOptions.SymbolFontChange(Sender: TObject);
begin
{  if Sender is TSpeedButton then
    (Sender as TSpeedButton).Down := not (Sender as TSpeedButton).Down;}
  if not FBusy then
    ShowSymbolSample;
end;

{ ===========================================================================
  TfrmOptions.GridTextChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Typing a spacing selects the usual size it equals, or Custom.
  =========================================================================== }
procedure TfrmOptions.GridTextChange(Sender: TObject);
var
  V: Double;
begin
  if FBusy then
    Exit;
  if ParseNumber(edGrid.Text, V) then
    ShowPresetFor(UnitsToMm(V, FUnits))
  else
    ShowPresetFor(-1);
end;

{ ===========================================================================
  TfrmOptions.AutoSnapClick  (procedure)
  Parameters:
    Sender: TObject - the check box
  Notes:
    The range of auto snap is only entered while auto snap is ticked.
  =========================================================================== }
procedure TfrmOptions.AutoSnapClick(Sender: TObject);
begin
  edRange.Enabled := cbAutoSnap.Checked;
end;

{ ===========================================================================
  TfrmOptions.ChangeClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    A Change button was pressed: choose the color of its row.
  =========================================================================== }
procedure TfrmOptions.ChangeClick(Sender: TObject);
begin
  ChooseColor((Sender as TComponent).Tag);
end;

{ ===========================================================================
  TfrmOptions.AutoSaveClick  (procedure)
  Parameters:
    Sender: TObject - the check box
  Notes:
    The minutes between automatic saves are only entered while automatic saving is ticked.
  =========================================================================== }
procedure TfrmOptions.AutoSaveClick(Sender: TObject);
begin
  edMinutes.Enabled := cbAutoSave.Checked;
end;

end.
