// SPDX-License-Identifier: LGPL-2.1-or-later
{ The Find panel: what TinyCAD's Find lists, in a frame that takes the place of the symbol library panel in the left
  panel of the main window. An entry and a Find button ask for the text; each object that mentions it is listed in
  lbFindResults ("Label: VCC", "Power: +5V" ...). Choosing an entry takes the main window to that object, which has a red
  circle on it; the red X in the upper corner closes the find. The panel itself only shows and reports: the search and
  the circles are done by the main window, which sets the results and answers the events.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit QFindPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls, StdCtrls, Buttons, Graphics, ImgList;

type
  TFindResultEvent = procedure(Sender: TObject; Index: Integer) of object;

  { TfrFindPanel }

  TfrFindPanel = class(TFrame)
    btnClose: TSpeedButton;
    btnFind: TButton;
    cbFindInAll: TCheckBox;
    edFindText: TEdit;
    lbCaption: TLabel;
    lblCount: TLabel;
    lbFindResults: TListBox;
    pnlButton: TPanel;
    pnlEntry: TPanel;
    pnlHeader: TPanel;
    procedure btnCloseClick(Sender: TObject);
    procedure btnFindClick(Sender: TObject);
    procedure edFindTextKeyPress(Sender: TObject; var Key: Char);
    procedure lbFindResultsClick(Sender: TObject);
    procedure lbFindResultsSelectionChange(Sender: TObject; User: Boolean);
  private
    FOnFindRequest: TNotifyEvent;
    FOnResultSelected: TFindResultEvent;
    FOnCloseRequest: TNotifyEvent;
    function GetFindText: String;
    function GetFindInAll: Boolean;
    procedure SetFindInAll(Value: Boolean);
    procedure SetFindText(const Value: String);
    procedure ResultChosen;
  public
    constructor Create(TheOwner: TComponent); override;
    procedure FocusEntry;
    { show the close button as a picture from an image list instead of the letter X }
    procedure UseCloseIcon(AImages: TCustomImageList; AIndex: Integer);
    procedure SetResults(Items: TStrings; const Summary: String);
    procedure ClearResults(const Summary: String);
    procedure SelectResult(Index: Integer);
    function ResultCount: Integer;
    function ResultText(Index: Integer): String;
    function SelectedResult: Integer;
    property FindText: String read GetFindText write SetFindText;
    { the Search all Sheets box: ticked looks in every sheet of the document, not ticked only in the sheet shown }
    property FindInAll: Boolean read GetFindInAll write SetFindInAll;
    { Enter in the entry or the Find button: look for FindText }
    property OnFindRequest: TNotifyEvent read FOnFindRequest write FOnFindRequest;
    { an entry of the list was chosen by the user (a click, or the arrow keys) }
    property OnResultSelected: TFindResultEvent read FOnResultSelected write FOnResultSelected;
    { the red X (or Esc in the entry): close the find }
    property OnCloseRequest: TNotifyEvent read FOnCloseRequest write FOnCloseRequest;
  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfrFindPanel.GetFindText  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The text in the entry.
  =========================================================================== }

{ ===========================================================================
  TfrFindPanel.Create  (constructor)
  Parameters:
    TheOwner: TComponent - the owner (the main form)
  Notes:
    Creates the frame from its form file and then checks that the form file really made every
    component this unit uses. QFindPanel.pas and QFindPanel.lfm must be the pair that belong
    together; if the form file is another version the field stays nil and its first use would be
    an access violation at a small address, so this raises an error that names the missing
    components instead.
  =========================================================================== }
constructor TfrFindPanel.Create(TheOwner: TComponent);
var
  Missing: String;
  procedure Need(C: TObject; const AName: String);
  begin
    if C = nil then
      Missing := Missing + ' ' + AName;
  end;
begin
  inherited Create(TheOwner);
  Missing := '';
  Need(pnlHeader, 'pnlHeader');
  Need(lbCaption, 'lbCaption');
  Need(btnClose, 'btnClose');
  Need(pnlEntry, 'pnlEntry');
  Need(edFindText, 'edFindText');
  Need(pnlButton, 'pnlButton');
  Need(btnFind, 'btnFind');
  Need(cbFindInAll, 'cbFindInAll');
  Need(lblCount, 'lblCount');
  Need(lbFindResults, 'lbFindResults');
  if Missing <> '' then
    raise EInvalidOperation.Create('QFindPanel.lfm does not match QFindPanel.pas: the form file has no component named' + Missing +
      '. Use the QFindPanel.pas and QFindPanel.lfm that belong together, and rebuild.');
end;

{ ===========================================================================
  TfrFindPanel.GetFindText  (function)
  Parameters:  none
  Returns:
    String - the text
  Notes:
    The text in the entry.
  =========================================================================== }
function TfrFindPanel.GetFindText: String;
begin
  Result := edFindText.Text;
end;

{ ===========================================================================
  TfrFindPanel.GetFindInAll  (function)
  Parameters:  none
  Returns:
    Boolean - True when every sheet is searched
  Notes:
    The state of the Search all Sheets box.
  =========================================================================== }
function TfrFindPanel.GetFindInAll: Boolean;
begin
  Result := cbFindInAll.Checked;
end;

{ ===========================================================================
  TfrFindPanel.SetFindInAll  (procedure)
  Parameters:
    Value: Boolean - True to search every sheet
  Notes:
    Ticks or clears the Search all Sheets box.
  =========================================================================== }
procedure TfrFindPanel.SetFindInAll(Value: Boolean);
begin
  cbFindInAll.Checked := Value;
end;

{ ===========================================================================
  TfrFindPanel.SetFindText  (procedure)
  Parameters:
    const Value: String - the text
  Notes:
    Puts a text in the entry.
  =========================================================================== }
procedure TfrFindPanel.SetFindText(const Value: String);
begin
  edFindText.Text := Value;
end;

{ ===========================================================================
  TfrFindPanel.FocusEntry  (procedure)
  Parameters:  none
  Notes:
    Puts the cursor in the entry with its text selected, ready to type over.
  =========================================================================== }
procedure TfrFindPanel.FocusEntry;
begin
  if edFindText.CanFocus then
  begin
    edFindText.SetFocus;
    edFindText.SelectAll;
  end;
end;

{ ===========================================================================
  TfrFindPanel.UseCloseIcon  (procedure)
  Parameters:
    AImages: TCustomImageList - the image list
    AIndex: Integer - which picture (0 is the red X)
  Notes:
    Shows the close button as a picture from an image list (the main form's ilTinyIcons) instead
    of the letter X. The frame is given the list by the owner, so it does not depend on the main
    form. If there is no such picture the letter X stays.
  =========================================================================== }
procedure TfrFindPanel.UseCloseIcon(AImages: TCustomImageList; AIndex: Integer);
begin
  if (AImages = nil) or (AIndex < 0) or (AIndex >= AImages.Count) then
    Exit;      // (no such picture: the letter X stays)
  btnClose.Images := AImages;
  btnClose.ImageIndex := AIndex;
  btnClose.Caption := '';
end;

{ ===========================================================================
  TfrFindPanel.SetResults  (procedure)
  Parameters:
    Items: TStrings - the lines to list
    const Summary: String - the short text beside the button
  Notes:
    Fills the list with what was found and shows the summary ("4 found", "Not found") beside the
    Find button. No entry is chosen.
  =========================================================================== }
procedure TfrFindPanel.SetResults(Items: TStrings; const Summary: String);
begin
  lbFindResults.Items.Assign(Items);
  lbFindResults.ItemIndex := -1;
  lblCount.Caption := Summary;
end;

{ ===========================================================================
  TfrFindPanel.ClearResults  (procedure)
  Parameters:
    const Summary: String - the short text beside the button
  Notes:
    Empties the list and shows a summary text.
  =========================================================================== }
procedure TfrFindPanel.ClearResults(const Summary: String);
begin
  lbFindResults.Items.Clear;
  lblCount.Caption := Summary;
end;

{ ===========================================================================
  TfrFindPanel.SelectResult  (procedure)
  Parameters:
    Index: Integer - the entry, 0 for the first
  Notes:
    Chooses an entry of the list from the program (a red circle was clicked on the sheet). This
    does not report a choice: the sheet is already where it should be.
  =========================================================================== }
procedure TfrFindPanel.SelectResult(Index: Integer);
begin
  { choosing an entry in the program (a marker was clicked on the sheet) does not take the sheet anywhere: it is already there }
  if (Index >= 0) and (Index < lbFindResults.Count) then
  begin
    lbFindResults.ItemIndex := Index;
    lbFindResults.MakeCurrentVisible;
  end;
end;

{ ===========================================================================
  TfrFindPanel.ResultCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many entries the list has.
  =========================================================================== }
function TfrFindPanel.ResultCount: Integer;
begin
  Result := lbFindResults.Count;
end;

{ ===========================================================================
  TfrFindPanel.ResultText  (function)
  Parameters:
    Index: Integer - the entry, 0 for the first
  Returns:
    String - the text, empty if there is no such entry
  Notes:
    The text of one entry of the list.
  =========================================================================== }
function TfrFindPanel.ResultText(Index: Integer): String;
begin
  if (Index >= 0) and (Index < lbFindResults.Count) then
    Result := lbFindResults.Items[Index]
  else
    Result := '';
end;

{ ===========================================================================
  TfrFindPanel.SelectedResult  (function)
  Parameters:  none
  Returns:
    Integer - its number, -1 for none
  Notes:
    Which entry of the list is chosen.
  =========================================================================== }
function TfrFindPanel.SelectedResult: Integer;
begin
  Result := lbFindResults.ItemIndex;
end;

{ ===========================================================================
  TfrFindPanel.ResultChosen  (procedure)
  Parameters:  none
  Notes:
    Reports the chosen entry to the owner (OnResultSelected).
  =========================================================================== }
procedure TfrFindPanel.ResultChosen;
begin
  if (lbFindResults.ItemIndex >= 0) and Assigned(FOnResultSelected) then
    FOnResultSelected(Self, lbFindResults.ItemIndex);
end;

{ ===========================================================================
  TfrFindPanel.btnCloseClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    The red X in the upper corner: asks the owner to close the find (OnCloseRequest).
  =========================================================================== }
procedure TfrFindPanel.btnCloseClick(Sender: TObject);
begin
  if Assigned(FOnCloseRequest) then
    FOnCloseRequest(Self);
end;

{ ===========================================================================
  TfrFindPanel.btnFindClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    The Find button: asks the owner to look for the text in the entry (OnFindRequest).
  =========================================================================== }
procedure TfrFindPanel.btnFindClick(Sender: TObject);
begin
  if Assigned(FOnFindRequest) then
    FOnFindRequest(Self);
end;

{ ===========================================================================
  TfrFindPanel.edFindTextKeyPress  (procedure)
  Parameters:
    Sender: TObject - the entry
    var Key: Char - the key (set to 0 when it was used)
  Notes:
    Keys in the entry: Enter looks for the text, Esc closes the find.
  =========================================================================== }
procedure TfrFindPanel.edFindTextKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    if Assigned(FOnFindRequest) then
      FOnFindRequest(Self);
  end
  else if Key = #27 then
  begin
    Key := #0;
    if Assigned(FOnCloseRequest) then
      FOnCloseRequest(Self);
  end;
end;

{ ===========================================================================
  TfrFindPanel.lbFindResultsClick  (procedure)
  Parameters:
    Sender: TObject - the list
  Notes:
    A click on the list: the entry is reported every time, even if it was chosen already,
    because the sheet may have been moved away from it since.
  =========================================================================== }
procedure TfrFindPanel.lbFindResultsClick(Sender: TObject);
begin
  ResultChosen;           // (every click, even on the entry that is already chosen: the sheet may have been left since)
end;

{ ===========================================================================
  TfrFindPanel.lbFindResultsSelectionChange  (procedure)
  Parameters:
    Sender: TObject - the list
    User: Boolean - True when the user changed it
  Notes:
    The chosen entry changed: reported when it was the user who did it (the arrow keys).
  =========================================================================== }
procedure TfrFindPanel.lbFindResultsSelectionChange(Sender: TObject; User: Boolean);
begin
  if User then
    ResultChosen;       // the arrow keys
end;

end.
