{ The Design Markers window (TinyCAD's CDlgERCListBox): a window that stays open beside the sheet and lists what the design rules check found, one line
  for each marker on the sheets. Choosing a line shows the marker (the main form finds it and shows its sheet); the buttons are Close, Re-check, and the
  convenience buttons Generate Symbol References, Generate PCB Netlist and Generate SPICE Netlist. Closing the window (the Close button or the window's own
  close button) takes the markers off the sheets. The window only holds the list and raises events; the main form runs the check and finds the markers.

  Differences from TinyCAD: the text of a line has no line end at its end (the C++ list shows the line end some messages carry as a box).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fercwin;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls;

type
  TErcItemEvent = procedure(Sender: TObject; Index: Integer) of object;

  { TfrmErcList }

  TfrmErcList = class(TForm)
    btnAnnotate: TButton;
    btnClose: TButton;
    btnPcb: TButton;
    btnRecheck: TButton;
    btnSpice: TButton;
    gbConvenience: TGroupBox;
    lbErrors: TListBox;
    pnlButtons: TPanel;
    procedure AnnotateClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure ErrorsSelectionChange(Sender: TObject; User: Boolean);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure PcbClick(Sender: TObject);
    procedure RecheckClick(Sender: TObject);
    procedure SpiceClick(Sender: TObject);
  private
    FStop: Boolean;              // a selection made by the program does not count as a choice (CDlgERCListBox::stop)
    FOnItem: TErcItemEvent;
    FOnRecheck, FOnClose, FOnAnnotate, FOnPcb, FOnSpice: TNotifyEvent;
  public
    { empty the list and put the lines in (CDlgERCListBox::Open + AddString) }
    procedure Fill(Lines: TStrings);
    { select a line without raising the choice event (CDlgERCListBox::SetSelect) }
    procedure SetSelect(Index: Integer);
    { what clicking line Index does }
    procedure ChooseItem(Index: Integer);
    function ItemCount: Integer;
    function ItemText(Index: Integer): String;
    function Selected: Integer;
    property OnItemChosen: TErcItemEvent read FOnItem write FOnItem;
    property OnRecheck: TNotifyEvent read FOnRecheck write FOnRecheck;
    property OnCloseRequest: TNotifyEvent read FOnClose write FOnClose;
    property OnAnnotate: TNotifyEvent read FOnAnnotate write FOnAnnotate;
    property OnPcbNetlist: TNotifyEvent read FOnPcb write FOnPcb;
    property OnSpiceNetlist: TNotifyEvent read FOnSpice write FOnSpice;
  end;

var
  frmErcList: TfrmErcList;

implementation

{$R *.lfm}

{ ===========================================================================
  TfrmErcList.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The window is not modal, so it is a plain form and not a TfrmBase; its button panel
    (pnlButtons, with Close and Re-check) is made to look like the base dialog's bar.
  =========================================================================== }
procedure TfrmErcList.FormCreate(Sender: TObject);
begin
  FStop := False;
end;

{ ===========================================================================
  TfrmErcList.Fill  (procedure)
  Parameters:
    Lines: TStrings - the lines of the check's result
  Notes:
    Empties the list and adds the lines, each without the line end some of them carry.
  =========================================================================== }
procedure TfrmErcList.Fill(Lines: TStrings);
var
  i: Integer;
  S: String;
begin
  FStop := True;
  try
    lbErrors.Items.BeginUpdate;
    try
      lbErrors.Items.Clear;
      if Lines <> nil then
      for i := 0 to Lines.Count - 1 do
      begin
        S := Lines[i];
        while (S <> '') and (S[Length(S)] in [#10, #13]) do Delete(S, Length(S), 1);
        lbErrors.Items.Add(S);
      end;
    finally
      lbErrors.Items.EndUpdate;
    end;
    lbErrors.ItemIndex := -1;
  finally
    FStop := False;
  end;
end;

{ ===========================================================================
  TfrmErcList.SetSelect  (procedure)
  Parameters:
    Index: Integer - the line, -1 for none
  Notes:
    Selects a line without it counting as the user's choice (so the sheet is not scrolled to
    it).
  =========================================================================== }
procedure TfrmErcList.SetSelect(Index: Integer);
begin
  FStop := True;
  try
    if (Index >= 0) and (Index < lbErrors.Items.Count) then
      lbErrors.ItemIndex := Index
    else
      lbErrors.ItemIndex := -1;
  finally
    FStop := False;
  end;
end;

{ ===========================================================================
  TfrmErcList.ChooseItem  (procedure)
  Parameters:
    Index: Integer - the line
  Notes:
    What clicking a line does: selects it and raises the choice event (CDlgERCListBox::OnClick).
    Used by the list's own event and by tests.
  =========================================================================== }
procedure TfrmErcList.ChooseItem(Index: Integer);
begin
  if (Index < 0) or (Index >= lbErrors.Items.Count) then
    Exit;
  FStop := True;
  try
    lbErrors.ItemIndex := Index;
  finally
    FStop := False;
  end;
  if Assigned(FOnItem) then
    FOnItem(Self, Index);
end;

{ ===========================================================================
  TfrmErcList.ItemCount  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    The number of lines.
  =========================================================================== }
function TfrmErcList.ItemCount: Integer;
begin
  Result := lbErrors.Items.Count;
end;

{ ===========================================================================
  TfrmErcList.ItemText  (function)
  Parameters:
    Index: Integer - the line
  Returns:
    String - the text
  Notes:
    The text of a line.
  =========================================================================== }
function TfrmErcList.ItemText(Index: Integer): String;
begin
  Result := lbErrors.Items[Index];
end;

{ ===========================================================================
  TfrmErcList.Selected  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    The line that is selected, -1 for none.
  =========================================================================== }
function TfrmErcList.Selected: Integer;
begin
  Result := lbErrors.ItemIndex;
end;

{ ===========================================================================
  TfrmErcList.ErrorsSelectionChange  (procedure)
  Parameters:
    Sender: TObject - the list
    User: Boolean - True when the user made the change
  Notes:
    LBN_SELCHANGE: the user chose a line.
  =========================================================================== }
procedure TfrmErcList.ErrorsSelectionChange(Sender: TObject; User: Boolean);
begin
  if FStop or (not User) then
    Exit;
  if lbErrors.ItemIndex < 0 then
    Exit;
  if Assigned(FOnItem) then
    FOnItem(Self, lbErrors.ItemIndex);
end;

{ ===========================================================================
  TfrmErcList.CloseClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The Close button.
  =========================================================================== }
procedure TfrmErcList.CloseClick(Sender: TObject);
begin
  if Assigned(FOnClose) then
    FOnClose(Self)
  else
    Hide;
end;

{ ===========================================================================
  TfrmErcList.FormClose  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
    var CloseAction: TCloseAction - what to do with the window
  Notes:
    The window's own close button does what Close does (the window is hidden by the main form).
  =========================================================================== }
procedure TfrmErcList.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
  if Assigned(FOnClose) then
    FOnClose(Self);
end;

{ ===========================================================================
  TfrmErcList.RecheckClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The Re-check button.
  =========================================================================== }
procedure TfrmErcList.RecheckClick(Sender: TObject);
begin
  if Assigned(FOnRecheck) then
    FOnRecheck(Self);
end;

{ ===========================================================================
  TfrmErcList.AnnotateClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The Generate Symbol References button.
  =========================================================================== }
procedure TfrmErcList.AnnotateClick(Sender: TObject);
begin
  if Assigned(FOnAnnotate) then
    FOnAnnotate(Self);
end;

{ ===========================================================================
  TfrmErcList.PcbClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The Generate PCB Netlist button.
  =========================================================================== }
procedure TfrmErcList.PcbClick(Sender: TObject);
begin
  if Assigned(FOnPcb) then
    FOnPcb(Self);
end;

{ ===========================================================================
  TfrmErcList.SpiceClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    The Generate SPICE Netlist button.
  =========================================================================== }
procedure TfrmErcList.SpiceClick(Sender: TObject);
begin
  if Assigned(FOnSpice) then
    FOnSpice(Self);
end;

end.
