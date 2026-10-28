// SPDX-License-Identifier: LGPL-2.1-or-later
{ The symbol library panel: a frame that shows every open symbol library (.TCLib file) as a tree. The
  top level of the tree is the library file and its children are the symbols (records) in it, so
  several libraries can be open at once, as in TinyCAD. Selecting a symbol shows a preview; double
  clicking it (or clicking the preview) asks the owner to place it.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit QLibPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, Forms, Controls, ExtCtrls, StdCtrls, ComCtrls, Menus, Graphics, Math, Types,
  UDPoint, UDrawTypes, UGeometry, UDrawingObjects, USymbols, UDesign, ULibrary, UPainter, UPartsDb, Dialogs;

type
  TPlaceRequest = procedure(Sender: TObject; Lib: TSymbolLibrary; SetIndex, RecIndex: Integer) of object;
  { what the pop-up menu asks for on the library or symbol under the pointer: the symbol commands of TinyCAD's library window }
  TSymbolCommand = (scNew, scEdit, scDelete, scDuplicate, scProperties, scExportSymbol, scExportLibrary, scImport);
  TSymbolCommandEvent = procedure(Sender: TObject; Cmd: TSymbolCommand) of object;
  TCopyToEvent = procedure(Sender: TObject; TargetIndex: Integer) of object;
  TPartRequest = procedure(Sender: TObject; PartIndex: Integer) of object;
  TCloseLibraryQuery = procedure(Sender: TObject; const FileName: String; var Allow: Boolean) of object;

  { one open library file }
  TLibEntry = class
  public
    FileName: String;
    Lib: TSymbolLibrary;
    destructor Destroy; override;
  end;

  { what a symbol node of the tree stands for }
  TLibNodeRef = class
  public
    Entry: TLibEntry;
    SetIndex, RecIndex: Integer;
  end;

  { TfrLibraryPanel }

  TfrLibraryPanel = class(TFrame)
    btnPartsOpen: TButton;
    dlgPartsOpen: TOpenDialog;
    dlgPartsNew: TSaveDialog;
    edFilter: TEdit;
    ilParts: TImageList;
    lbPartsCaption: TLabel;
    lvParts: TListView;
    lbCaption: TLabel;
    miLibraries: TMenuItem;
    miCloseAllLibs: TMenuItem;
    miCloseLib: TMenuItem;
    miSep: TMenuItem;
    miCopyTo: TMenuItem;
    miImport: TMenuItem;
    miExportLib: TMenuItem;
    miExportSym: TMenuItem;
    miProperties: TMenuItem;
    miDuplicate: TMenuItem;
    miDelete: TMenuItem;
    miEdit: TMenuItem;
    miNew: TMenuItem;
    pcLibrary: TPageControl;
    pbPreview: TPaintBox;
    pmLibView: TPopupMenu;
    Splitter1: TSplitter;
    tsSymbols: TTabSheet;
    tsParts: TTabSheet;
    tvLib: TTreeView;
    procedure Label1Click(Sender: TObject);
    procedure PartsOpenClick(Sender: TObject);
    procedure PartsDblClick(Sender: TObject);
    procedure PartsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure FilterChange(Sender: TObject);
    procedure PreviewPaint(Sender: TObject);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure ListDblClick(Sender: TObject);
    procedure PopupClose(Sender: TObject);
    procedure PopupOpen(Sender: TObject);
    procedure PopupCommand(Sender: TObject);
    procedure PopupCopyTo(Sender: TObject);
    procedure PopupCloseAll(Sender: TObject);
    procedure PopupLibraries(Sender: TObject);
    procedure TreeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  private
    FEntries: TObjectList;       // the open libraries (TLibEntry, owned)
    FRefs: TObjectList;          // what the symbol nodes stand for (TLibNodeRef, owned; rebuilt with the tree)
    FRebuilding: Boolean;
    FPreviewDesign: TDesignFile;
    FPreviewMethod: TDrawMethod;
    FOnPlace: TPlaceRequest;
    FOnChanged: TNotifyEvent;
    FOnPartsFileChanged: TNotifyEvent;
    FOnSymbolCommand: TSymbolCommandEvent;
    FOnCopyTo: TCopyToEvent;
    FOnQueryClose: TCloseLibraryQuery;
    FOnLibraries: TNotifyEvent;
    FCommandItems: array[TSymbolCommand] of TMenuItem;
    FCopyToItem: TMenuItem;
    FPopup: TPopupMenu;
    FPartsLib: TPartsLibrary;      // the open parts library, nil for none
    FPartsError: String;
    FOnPartSelected, FOnPartPlace: TPartRequest;
    procedure FillParts;
    procedure Changed;
    procedure Rebuild;
    procedure BuildPreview;
    procedure ClearPreview;
    procedure UpdateCaption;
    function SelectedRef: TLibNodeRef;
    function SelectedEntry: TLibEntry;
    function FindEntry(const FileName: String): Integer;
    function RecordNode(Index: Integer): TTreeNode;
    function CanCloseEntry(Index: Integer): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenLibrary(const FileName: String);
    procedure CloseLibrary(Index: Integer);
    procedure CloseAll;
    { the index of the open library for a file, or -1 }
    function IndexOfFile(const FileName: String): Integer;
    function LibCount: Integer;
    { CLibraryCollection::GetSymbol + GetDesignSymbol(sheet, 0): the first record of the first set that has a record of this name (ignoring case), in the open libraries; nil when none }
    function FindSymbolByName(const SymName: String; Sheet: TDesignSheet): TDesignFileSymbol;
    { the library of the selected node (a library or one of its symbols), -1 for none; the position of the selected symbol's set in it, -1 when a library is selected }
    function SelectedLibIndex: Integer;
    function SelectedSetIndex: Integer;
    { which record (name) of that symbol is selected, -1 when none }
    function SelectedRecIndex: Integer;
    { show the libraries as they are now (after one was changed under the panel), keeping the selection when the symbol is still there }
    procedure Reload;
    { select a symbol by its id in a library, opening the library }
    function SelectSymbolId(LibIndex: Integer; SymbolId: Int64): Boolean;
    { ask the owner for a symbol command, as the pop-up menu does (nothing when no event is set) }
    procedure Command(Cmd: TSymbolCommand);
    { a pop-up menu item: its text, and whether it is enabled now (as when the menu opens) }
    function CommandEnabled(Cmd: TSymbolCommand): Boolean;
    function LibFileName(Index: Integer): String;
    function LibAt(Index: Integer): TSymbolLibrary;
    procedure SelectRow(Index: Integer);
    procedure PlaceSelected;
    function RowCount: Integer;
    function RowText(Index: Integer): String;
    { the library of the selected node, else the first open library, else nil }
    function Lib: TSymbolLibrary;
    { Parts tab: opens a TCParts file and lists its parts with their icons (24 pixels). False with PartsError set when the file cannot be used. }
    function OpenPartsFile(const FileName: String): Boolean;
    { makes a new, empty parts library at FileName (named after the file) and shows it in the Parts tab; False (PartsError says why) when it could not }
    function NewPartsFile(const FileName: String): Boolean;
    { Parts > New Parts Library...: asks where to save it (an existing file is replaced only after the person agreed in the dialog), then NewPartsFile }
    function NewPartsLibrary: Boolean;
    { the file of the open parts library, '' for none }
    function PartsFileName: String;
    { reads the part list from the file again (after the library editor changed it) and shows it }
    procedure ReloadParts;
    procedure ClosePartsFile;
    function PartsRowCount: Integer;
    function PartsRowText(Index: Integer): String;
    function PartsRowImage(Index: Integer): Integer;
    procedure SelectPartRow(Index: Integer);
    function SelectedPartIndex: Integer;
    property PartsLibrary: TPartsLibrary read FPartsLib;
    property PartsError: String read FPartsError;
    { a part of the Parts tab was chosen (OnPartSelected) or double clicked (OnPartPlace: the owner places it) }
    property OnPartSelected: TPartRequest read FOnPartSelected write FOnPartSelected;
    property OnPartPlace: TPartRequest read FOnPartPlace write FOnPartPlace;
    { a parts file was opened or closed (the owner keeps its name to open it again next time) }
    property OnPartsFileChanged: TNotifyEvent read FOnPartsFileChanged write FOnPartsFileChanged;
    property OnPlace: TPlaceRequest read FOnPlace write FOnPlace;
    { a library was opened, closed or read again: the list of libraries in use changed }
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property OnSymbolCommand: TSymbolCommandEvent read FOnSymbolCommand write FOnSymbolCommand;
    { Copy to: the library chosen in the pop-up menu's submenu }
    property OnCopyTo: TCopyToEvent read FOnCopyTo write FOnCopyTo;
    { a library is about to be closed: the owner can refuse (a symbol of it is being edited) }
    property OnQueryClose: TCloseLibraryQuery read FOnQueryClose write FOnQueryClose;
    { Libraries... in the pop-up menu: the owner shows its library list }
    property OnLibraries: TNotifyEvent read FOnLibraries write FOnLibraries;
  end;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TLibEntry.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the library this entry holds.
  =========================================================================== }
destructor TLibEntry.Destroy;
begin
  Lib.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TfrLibraryPanel.Label1Click  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TfrLibraryPanel
  =========================================================================== }
procedure TfrLibraryPanel.Label1Click(Sender: TObject);
begin
end;

{ ===========================================================================
  TfrLibraryPanel.FilterChange  (procedure)
  Parameters:
    Sender: TObject - the filter box
  Notes:
    Event handler: the filter text changed, so rebuild the tree.
  =========================================================================== }
procedure TfrLibraryPanel.FilterChange(Sender: TObject);
begin
  Rebuild;
end;

{ ===========================================================================
  TfrLibraryPanel.TreeChange  (procedure)
  Parameters:
    Sender: TObject - the tree
    Node: TTreeNode - the node now selected
  Notes:
    Event handler: the selection in the tree changed, so show the preview of the selected symbol
    (nothing is shown for a library node). Ignored while the tree is being rebuilt.
  =========================================================================== }
procedure TfrLibraryPanel.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if FRebuilding then
    Exit;
  BuildPreview;
  pbPreview.Invalidate;
end;

{ ===========================================================================
  TfrLibraryPanel.ListDblClick  (procedure)
  Parameters:
    Sender: TObject - the tree or the preview
  Notes:
    Event handler: a double click on the tree or a click on the preview asks the owner to place
    the selected symbol. On a library node it does nothing, so the tree's own double-click opens
    or closes it.
  =========================================================================== }
procedure TfrLibraryPanel.ListDblClick(Sender: TObject);
begin
  PlaceSelected;      // a library node just opens or closes as the tree does by itself
end;

{ ===========================================================================
  TfrLibraryPanel.PreviewPaint  (procedure)
  Parameters:
    Sender: TObject - the paint box
  Notes:
    Draws the selected symbol, scaled to fit, in the preview area.
  =========================================================================== }
procedure TfrLibraryPanel.PreviewPaint(Sender: TObject);
var
  C: TCanvas;
  T: TTransform;
  P: TSchematicPainter;
  L, Tp, R, B, W, H, Z: Double;
begin
  C := pbPreview.Canvas;
  C.Brush.Color := clWhite;
  C.Pen.Color := clSilver;
  C.Rectangle(0, 0, pbPreview.Width, pbPreview.Height);
  if FPreviewMethod = nil then
    Exit;
  L := Min(FPreviewMethod.PointA.x, FPreviewMethod.PointB.x);
  R := Max(FPreviewMethod.PointA.x, FPreviewMethod.PointB.x);
  Tp := Min(FPreviewMethod.PointA.y, FPreviewMethod.PointB.y);
  B := Max(FPreviewMethod.PointA.y, FPreviewMethod.PointB.y);
  W := Max(20, R - L + 40);
  H := Max(20, B - Tp + 40);
  Z := Min((pbPreview.Width - 10) / W, (pbPreview.Height - 10) / H);
  Z := Min(Z, 2.0);
  T := TTransform.Create;
  try
    T.SetZoomFactor(Z);
    T.SetOrigin(DPoint(L - 20 - ((pbPreview.Width - 10) / Z - W) / 2, Tp - 20 - ((pbPreview.Height - 10) / Z - H) / 2));
    P := TSchematicPainter.Create(C, T);
    try
      P.PaintObject(FPreviewMethod, False);
    finally
      P.Free;
    end;
  finally
    T.Free;
  end;
end;

{ ===========================================================================
  TfrLibraryPanel.SelectedRef  (function)
  Parameters:  none
  Returns:
    TLibNodeRef - the symbol's library, set and record, or nil when a library node or nothing is
    selected
  Notes:
    What the selected symbol node stands for.
  =========================================================================== }
function TfrLibraryPanel.SelectedRef: TLibNodeRef;
var
  N: TTreeNode;
begin
  Result := nil;
  N := tvLib.Selected;
  if (N <> nil) and (N.Level = 1) then
    Result := TLibNodeRef(N.Data);
end;

{ ===========================================================================
  TfrLibraryPanel.SelectedEntry  (function)
  Parameters:  none
  Returns:
    TLibEntry - the library entry, or nil when nothing is selected
  Notes:
    The library the selected node belongs to, whether the node is the library itself or one of
    its symbols.
  =========================================================================== }
function TfrLibraryPanel.SelectedEntry: TLibEntry;
var
  N: TTreeNode;
begin
  Result := nil;
  N := tvLib.Selected;
  if N = nil then
    Exit;
  if N.Level = 0 then
    Result := TLibEntry(N.Data)
  else
    Result := TLibNodeRef(N.Data).Entry;
end;

{ ===========================================================================
  TfrLibraryPanel.FindEntry  (function)
  Parameters:
    const FileName: String - full path of the library file
  Returns:
    Integer - its position in the list of open libraries, or -1
  Notes:
    Finds an open library by its file name (ignoring case on systems where that is how files are
    named).
  =========================================================================== }
function TfrLibraryPanel.FindEntry(const FileName: String): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to FEntries.Count - 1 do
    if SameFileName(TLibEntry(FEntries[i]).FileName, FileName) then
    begin
      Result := i;
      Exit;
    end;
end;

{ ===========================================================================
  TfrLibraryPanel.UpdateCaption  (procedure)
  Parameters:  none
  Notes:
    Sets the caption above the tree: none open, the name of the one open library, or how many
    are open.
  =========================================================================== }
procedure TfrLibraryPanel.UpdateCaption;
begin
  case FEntries.Count of
    0: lbCaption.Caption := rsSymbolLibrariesNoneOpen;
    1: lbCaption.Caption := Format(rsSymbolLibrary, [ChangeFileExt(ExtractFileName(TLibEntry(FEntries[0]).FileName), '')]);
  else
    lbCaption.Caption := Format(rsSymbolLibrariesOpen, [FEntries.Count]);
  end;
end;

{ ===========================================================================
  CompareLibNames  (function)
  Parameters:
    List: TStringList
    Index1: Integer - whole number
    Index2: Integer - whole number
  Returns:
    Integer
  Notes:
    Orders the symbols of a library: by the name's characters (so 0 to 9 come before a to z),
    ignoring case; equal names keep the library's order.
  =========================================================================== }
function CompareLibNames(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := CompareStr(List[Index1], List[Index2]);
  if Result = 0 then
    Result := PtrInt(List.Objects[Index1]) - PtrInt(List.Objects[Index2]);
end;

{ ===========================================================================
  TfrLibraryPanel.Rebuild  (procedure)
  Parameters:  none
  Notes:
    Rebuilds the tree from the open libraries: a node per library (with the number of symbols
    shown) and a child per symbol, keeping only the symbols whose name or description contains
    the filter text. While filtering, libraries without a match disappear and the others are
    opened; otherwise each library stays open or closed as it was. The selected symbol stays
    selected if it is still listed.
  =========================================================================== }
procedure TfrLibraryPanel.Rebuild;
var
  i, j, k, m, Matches: Integer;
  Order: TStringList;
  E: TLibEntry;
  Rec: TLibraryRecord;
  Filt, Txt, SelFile: String;
  SelSet, SelRec: Integer;
  Open: TStringList;
  FileNode, RecNode, Reselect: TTreeNode;
  Ref: TLibNodeRef;
  Sel: TLibNodeRef;
begin
  Open := TStringList.Create;
  FRebuilding := True;
  try
    { remember which libraries were expanded and which symbol was selected }
    for i := 0 to tvLib.Items.Count - 1 do
      if (tvLib.Items[i].Level = 0) and tvLib.Items[i].Expanded then
        Open.Add(TLibEntry(tvLib.Items[i].Data).FileName);
    Sel := SelectedRef;
    SelFile := '';
    SelSet := -1;
    SelRec := -1;
    if Sel <> nil then
    begin
      SelFile := Sel.Entry.FileName;
      SelSet := Sel.SetIndex;
      SelRec := Sel.RecIndex;
    end;
    Reselect := nil;
    Filt := LowerCase(Trim(edFilter.Text));
    tvLib.Items.BeginUpdate;
    try
      tvLib.Items.Clear;     // (before the references go, so nothing points at freed data)
      FRefs.Clear;
      for i := 0 to FEntries.Count - 1 do
      begin
        E := TLibEntry(FEntries[i]);
        FileNode := tvLib.Items.Add(nil, '');
        FileNode.Data := E;
        Matches := 0;
        { the symbols of the library in alphabetical order (digits before letters, capitals and small letters alike) }
        Order := TStringList.Create;
        try
          for j := 0 to E.Lib.SetCount - 1 do
            for k := 0 to E.Lib.Sets[j].RecordCount - 1 do
              Order.AddObject(LowerCase(E.Lib.Sets[j].Records[k].Name), TObject(PtrInt(j * 100000 + k)));
          Order.CustomSort(@CompareLibNames);
          for m := 0 to Order.Count - 1 do
          begin
            j := PtrInt(Order.Objects[m]) div 100000;
            k := PtrInt(Order.Objects[m]) mod 100000;
            Rec := E.Lib.Sets[j].Records[k];
            if Rec.Description <> '' then
              Txt := Rec.Name + '  -  ' + Rec.Description
            else
              Txt := Rec.Name;
            if (Filt <> '') and (Pos(Filt, LowerCase(Txt)) = 0) then
              Continue;
            Ref := TLibNodeRef.Create;
            Ref.Entry := E;
            Ref.SetIndex := j;
            Ref.RecIndex := k;
            FRefs.Add(Ref);
            RecNode := tvLib.Items.AddChild(FileNode, Txt);
            RecNode.Data := Ref;
            Inc(Matches);
            if (SameFileName(E.FileName, SelFile)) and (j = SelSet) and (k = SelRec) then
              Reselect := RecNode;
          end;
        finally
          Order.Free;
        end;
        FileNode.Text := ChangeFileExt(ExtractFileName(E.FileName), '') + '  (' + IntToStr(Matches) + ')';
        if Matches = 0 then
        begin
          if Filt <> '' then
            tvLib.Items.Delete(FileNode);     // nothing in this library matches the filter
        end
        else
          { while filtering every library that has a match is open, otherwise they stay as they were }
          FileNode.Expanded := (Filt <> '') or (Open.IndexOf(E.FileName) >= 0);
      end;
    finally
      tvLib.Items.EndUpdate;
    end;
    if Reselect <> nil then
      tvLib.Selected := Reselect;
  finally
    FRebuilding := False;
    Open.Free;
  end;
  ClearPreview;
  BuildPreview;
  pbPreview.Invalidate;
end;

{ ===========================================================================
  TfrLibraryPanel.BuildPreview  (procedure)
  Parameters:  none
  Notes:
    Builds the one-symbol design that the preview draws from the selected symbol, or clears the
    preview when no symbol is selected.
  =========================================================================== }
procedure TfrLibraryPanel.BuildPreview;
var
  Id: Integer;
  Sheet: TDesignSheet;
  Sym: TDesignFileSymbol;
  Ref: TLibNodeRef;
begin
  ClearPreview;
  Ref := SelectedRef;
  if Ref = nil then
    Exit;
  FPreviewDesign := TDesignFile.Create;
  Sheet := FPreviewDesign.AddSheet;
  Sym := Ref.Entry.Lib.GetDesignSymbol(Sheet, Ref.Entry.Lib.Sets[Ref.SetIndex], Ref.RecIndex);
  if Sym = nil then
    Exit;
  Id := Sheet.Options.AddSymbol(Sym);
  FPreviewMethod := TDrawMethod.CreateFromSymbol(Sheet.Options, Id, 0);
  Sheet.Drawing.Add(FPreviewMethod);
  Sheet.UpdateLayout;
end;

{ ===========================================================================
  TfrLibraryPanel.ClearPreview  (procedure)
  Parameters:  none
  Notes:
    Throws away the preview design.
  =========================================================================== }
procedure TfrLibraryPanel.ClearPreview;
begin
  FPreviewMethod := nil;
  FreeAndNil(FPreviewDesign);
end;

{ ===========================================================================
  TfrLibraryPanel.TreeMouseDown  (procedure)
  Parameters:
    Sender: TObject - the tree
    Button: TMouseButton - which button
    Shift: TShiftState - modifier keys
    X: Integer - x in the tree
    Y: Integer - y in the tree
  Notes:
    A right click selects the node under the pointer, so the pop-up menu acts on it.
  =========================================================================== }
procedure TfrLibraryPanel.TreeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  N: TTreeNode;
begin
  { a right click selects the node under the pointer, so the pop-up menu acts on it }
  if Button = mbRight then
  begin
    N := tvLib.GetNodeAt(X, Y);
    if N <> nil then
      tvLib.Selected := N;
  end;
end;

{ ===========================================================================
  TfrLibraryPanel.PopupClose  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Pop-up menu handler: closes the library the selected node belongs to.
  =========================================================================== }
procedure TfrLibraryPanel.PopupClose(Sender: TObject);
var
  E: TLibEntry;
begin
  E := SelectedEntry;
  if E <> nil then
    CloseLibrary(FEntries.IndexOf(E));
end;

{ ===========================================================================
  TfrLibraryPanel.CanCloseEntry  (function)
  Parameters:
    Index: Integer - position in the list of open libraries
  Returns:
    Boolean - True when the library may be closed
  Notes:
    Asks the owner (OnQueryClose) whether the library can be closed; it cannot while a symbol of
    it is being edited.
  =========================================================================== }
function TfrLibraryPanel.CanCloseEntry(Index: Integer): Boolean;
begin
  Result := True;
  if Assigned(FOnQueryClose) then
    FOnQueryClose(Self, TLibEntry(FEntries[Index]).FileName, Result);
end;

{ ===========================================================================
  TfrLibraryPanel.SelectedLibIndex  (function)
  Parameters:  none
  Returns:
    Integer - the position among the open libraries, -1 when nothing is selected
  Notes:
    The library of the selected node, whether the node is the library or one of its symbols.
  =========================================================================== }
function TfrLibraryPanel.SelectedLibIndex: Integer;
var
  E: TLibEntry;
begin
  E := SelectedEntry;
  if E = nil then
    Result := -1
  else
    Result := FEntries.IndexOf(E);
end;

{ ===========================================================================
  TfrLibraryPanel.SelectedSetIndex  (function)
  Parameters:  none
  Returns:
    Integer - the position of the symbol's set in its library, -1 when a library or nothing is
    selected
  Notes:
    Which symbol is selected.
  =========================================================================== }
function TfrLibraryPanel.SelectedSetIndex: Integer;
var
  R: TLibNodeRef;
begin
  R := SelectedRef;
  if R = nil then
    Result := -1
  else
    Result := R.SetIndex;
end;

{ ===========================================================================
  TfrLibraryPanel.SelectedRecIndex  (function)
  Parameters:  none
  Returns:
    Integer
  Notes:
    Which name of the symbol is selected (a symbol can have several names).
  =========================================================================== }
function TfrLibraryPanel.SelectedRecIndex: Integer;
var
  R: TLibNodeRef;
begin
  R := SelectedRef;
  if R = nil then
    Result := -1
  else
    Result := R.RecIndex;
end;

{ ===========================================================================
  TfrLibraryPanel.Reload  (procedure)
  Parameters:  none
  Notes:
    Shows the libraries as they are now, after one was changed under the panel (a symbol was
    stored, deleted or copied); what was open stays open.
  =========================================================================== }
procedure TfrLibraryPanel.Reload;
begin
  Rebuild;
  UpdateCaption;
end;

{ ===========================================================================
  TfrLibraryPanel.SelectSymbolId  (function)
  Parameters:
    LibIndex: Integer - position among the open libraries
    SymbolId: Int64 - the id of the symbol's set in that library
  Returns:
    Boolean - True when the symbol is listed (the filter may hide it)
  Notes:
    Opens the library and selects the symbol, showing its preview.
  =========================================================================== }
function TfrLibraryPanel.SelectSymbolId(LibIndex: Integer; SymbolId: Int64): Boolean;
var
  i: Integer;
  R: TLibNodeRef;
begin
  Result := False;
  if (LibIndex < 0) or (LibIndex >= FEntries.Count) then
    Exit;
  for i := 0 to tvLib.Items.Count - 1 do
    if tvLib.Items[i].Level = 1 then
    begin
      R := TLibNodeRef(tvLib.Items[i].Data);
      if (R.Entry = TLibEntry(FEntries[LibIndex])) and (R.Entry.Lib.Sets[R.SetIndex].SymbolID = SymbolId) then
      begin
        tvLib.Items[i].Parent.Expanded := True;
        tvLib.Selected := tvLib.Items[i];
        BuildPreview;
        pbPreview.Invalidate;
        Result := True;
        Exit;
      end;
    end;
end;

{ ===========================================================================
  TfrLibraryPanel.CommandEnabled  (function)
  Parameters:
    Cmd: TSymbolCommand - the command
  Returns:
    Boolean - True when it can be asked for now
  Notes:
    New needs a library (or one of its symbols) to be selected; the others need a symbol.
  =========================================================================== }
function TfrLibraryPanel.CommandEnabled(Cmd: TSymbolCommand): Boolean;
begin
  if Cmd in [scNew, scExportLibrary, scImport] then
    Result := SelectedLibIndex >= 0
  else
    Result := SelectedSetIndex >= 0;
end;

{ ===========================================================================
  TfrLibraryPanel.Command  (procedure)
  Parameters:
    Cmd: TSymbolCommand - the command
  Notes:
    Asks the owner (OnSymbolCommand) to do a symbol command on the selection, when it can be
    done.
  =========================================================================== }
procedure TfrLibraryPanel.Command(Cmd: TSymbolCommand);
begin
  if CommandEnabled(Cmd) and Assigned(FOnSymbolCommand) then
    FOnSymbolCommand(Self, Cmd);
end;

{ ===========================================================================
  TfrLibraryPanel.PopupCommand  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Pop-up menu handler for the symbol commands.
  =========================================================================== }
procedure TfrLibraryPanel.PopupCommand(Sender: TObject);
begin
  Command(TSymbolCommand((Sender as TMenuItem).Tag));
end;

{ ===========================================================================
  TfrLibraryPanel.PopupCopyTo  (procedure)
  Parameters:
    Sender: TObject - the menu item (its Tag is the library's position)
  Notes:
    Pop-up menu handler for Copy to.
  =========================================================================== }
procedure TfrLibraryPanel.PopupCopyTo(Sender: TObject);
begin
  if Assigned(FOnCopyTo) and (SelectedSetIndex >= 0) then
    FOnCopyTo(Self, (Sender as TMenuItem).Tag);
end;

{ ===========================================================================
  TfrLibraryPanel.PopupOpen  (procedure)
  Parameters:
    Sender: TObject - the pop-up menu
  Notes:
    As the menu opens the commands are enabled or dimmed for the selection, and Copy to lists
    the open libraries (TinyCAD's FillLibraryNames).
  =========================================================================== }
procedure TfrLibraryPanel.PopupOpen(Sender: TObject);
var
  Cmd: TSymbolCommand;
  i: Integer;
  Item: TMenuItem;
begin
  for Cmd := Low(TSymbolCommand) to High(TSymbolCommand) do FCommandItems[Cmd].Enabled := CommandEnabled(Cmd);
  FCopyToItem.Clear;
  for i := 0 to FEntries.Count - 1 do
  begin
    Item := TMenuItem.Create(FCopyToItem);
    Item.Caption := ChangeFileExt(ExtractFileName(TLibEntry(FEntries[i]).FileName), '');
    Item.Tag := i;
    Item.OnClick := @PopupCopyTo;
    FCopyToItem.Add(Item);
  end;
  FCopyToItem.Enabled := (SelectedSetIndex >= 0) and (FEntries.Count > 0);
end;

{ ===========================================================================
  TfrLibraryPanel.PopupCloseAll  (procedure)
  Parameters:
    Sender: TObject - the menu item
  Notes:
    Pop-up menu handler: closes every library.
  =========================================================================== }
procedure TfrLibraryPanel.PopupCloseAll(Sender: TObject);
begin
  CloseAll;
end;

{ ===========================================================================
  TfrLibraryPanel.PopupLibraries  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Pop-up menu handler: asks the owner (OnLibraries) to show the libraries window.
  =========================================================================== }
procedure TfrLibraryPanel.PopupLibraries(Sender: TObject);
begin
  if Assigned(FOnLibraries) then
    FOnLibraries(Self);
end;

{ ===========================================================================
  TfrLibraryPanel.Create  (constructor)
  Parameters:
    AOwner: TComponent - owner of the frame
  Notes:
    Creates the panel: the lists of open libraries and of symbol references, and the pop-up menu
    (Close library, Close all libraries) of the tree.
  =========================================================================== }
constructor TfrLibraryPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEntries := TObjectList.Create(True);
  FRefs := TObjectList.Create(True);
  { the pop-up menu is in the designer (pmLibView); the code keeps the items its commands and the Copy to list belong to }
  FPopup := pmLibView;
  FCommandItems[scNew] := miNew;
  FCommandItems[scEdit] := miEdit;
  FCommandItems[scDelete] := miDelete;
  FCommandItems[scDuplicate] := miDuplicate;
  FCommandItems[scProperties] := miProperties;
  FCommandItems[scExportSymbol] := miExportSym;
  FCommandItems[scExportLibrary] := miExportLib;
  FCommandItems[scImport] := miImport;
  FCopyToItem := miCopyTo;
  UpdateCaption;
end;

{ ===========================================================================
  TfrLibraryPanel.Destroy  (destructor)
  Parameters:  none
  Notes:
    Drops the preview and the tree, then frees the references and the open libraries.
  =========================================================================== }
destructor TfrLibraryPanel.Destroy;
begin
  FPartsLib.Free;
  ClearPreview;
  if tvLib <> nil then
    tvLib.Items.Clear;     // (not there if the frame could not be created)
  FRefs.Free;
  FEntries.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TfrLibraryPanel.OpenLibrary  (procedure)
  Parameters:
    const FileName: String - path of the .TCLib file
  Notes:
    Opens a symbol library and adds it to the tree, opened and selected. A library that is
    already open is read again instead of being listed twice. If the file cannot be read the
    error is raised and the tree is unchanged. The filter is cleared so the new library is
    visible.
  =========================================================================== }
procedure TfrLibraryPanel.OpenLibrary(const FileName: String);
var
  New: TSymbolLibrary;
  E: TLibEntry;
  Full: String;
  At, i: Integer;
begin
  Full := ExpandFileName(FileName);
  At := FindEntry(Full);
  if At >= 0 then
  begin
    { already open: read it again (it may have changed); the library object stays, because a symbol being edited holds it }
    New := nil;
    TLibEntry(FEntries[At]).Lib.Reread;
  end
  else
  begin
    New := TSymbolLibrary.Create;
    try
      New.Open(Full);
    except
      New.Free;
      raise;
    end;
  end;
  ClearPreview;
  if At >= 0 then
    E := TLibEntry(FEntries[At])
  else
  begin
    E := TLibEntry.Create;
    E.FileName := Full;
    E.Lib := New;
    FEntries.Add(E);
  end;
  edFilter.Text := '';          // (Rebuild runs from the filter's change event when it had text)
  Rebuild;
  UpdateCaption;
  Changed;
  { open the library that was just opened and select it }
  for i := 0 to tvLib.Items.Count - 1 do
    if (tvLib.Items[i].Level = 0) and (TLibEntry(tvLib.Items[i].Data) = E) then
    begin
      tvLib.Items[i].Expanded := True;
      tvLib.Selected := tvLib.Items[i];
      Break;
    end;
end;

{ ===========================================================================
  TfrLibraryPanel.CloseLibrary  (procedure)
  Parameters:
    Index: Integer - position in the list of open libraries (out of range is ignored)
  Notes:
    Closes one library and removes it from the tree.
  =========================================================================== }
procedure TfrLibraryPanel.CloseLibrary(Index: Integer);
begin
  if (Index < 0) or (Index >= FEntries.Count) then
    Exit;
  if not CanCloseEntry(Index) then
    Exit;
  ClearPreview;
  FRebuilding := True;
  try
    tvLib.Items.Clear;
    FRefs.Clear;
  finally
    FRebuilding := False;
  end;
  FEntries.Delete(Index);       // frees the library
  Rebuild;
  UpdateCaption;
  Changed;
end;

{ ===========================================================================
  TfrLibraryPanel.OpenPartsFile  (function)
  Parameters:
    const FileName: String - the TCParts file
  Returns:
    Boolean - True when it was opened
  Notes:
    Opens a TyCAD parts library for the Parts tab and lists its parts. A file that cannot be used (missing, newer than this program, not a TyCAD parts file)
    leaves the tab as it was and PartsError says why.
  =========================================================================== }
function TfrLibraryPanel.OpenPartsFile(const FileName: String): Boolean;
var
  New: TPartsLibrary;
begin
  Result := False;
  FPartsError := '';
  New := TPartsLibrary.Create;
  try
    New.Open(FileName);
  except
    on E: EPartsError do
    begin
      New.Free;
      FPartsError := E.Message;
      Exit;
    end;
  end;
  FPartsLib.Free;
  FPartsLib := New;
  FillParts;
  Result := True;
  if Assigned(FOnPartsFileChanged) then
    FOnPartsFileChanged(Self);
end;

{ ===========================================================================
  TfrLibraryPanel.NewPartsFile  (function)
  Parameters:
    const FileName: String - the file to make
  Returns:
    Boolean - True when it was made and opened
  Notes:
    Makes a new parts library (UPartsDb.CreatePartsFile: the schema, the starting classes and rating quantities, no parts) whose name is the file's name without
    its extension, and opens it in the Parts tab. An existing file at FileName is replaced (the caller has asked the person). When it cannot be made, or the
    file made cannot be opened, the tab stays as it was and PartsError says why.
  =========================================================================== }
function TfrLibraryPanel.NewPartsFile(const FileName: String): Boolean;
begin
  Result := False;
  FPartsError := '';
  try
    if FileExists(FileName) then
    begin
      if (FPartsLib <> nil) and SameFileName(FPartsLib.FileName, FileName) then
        ClosePartsFile;
      if not DeleteFile(FileName) then
        raise EPartsError.Create(Format(rsTheExistingFileCannotBe, [FileName]));
    end;
    CreatePartsFile(FileName, ChangeFileExt(ExtractFileName(FileName), ''), '', '');
  except
    on E: EPartsError do
    begin
      FPartsError := E.Message;
      Exit;
    end;
  end;
  Result := OpenPartsFile(FileName);
end;

{ ===========================================================================
  TfrLibraryPanel.NewPartsLibrary  (procedure)
  Parameters:  none
  Notes:
    Parts > New Parts Library...: the Save dialog asks for the file (its own prompt covers replacing a file); a library that cannot be made is explained in a message.
  =========================================================================== }
function TfrLibraryPanel.NewPartsLibrary: Boolean;
begin
  Result := False;
  if not dlgPartsNew.Execute then
    Exit;
  Result := NewPartsFile(dlgPartsNew.FileName);
  if not Result then
    MessageDlg(rsPartsLibrary, FPartsError, mtError, [mbOK], 0);
end;

{ ===========================================================================
  TfrLibraryPanel.PartsFileName  (function)
  Returns:
    String - the file of the open parts library, empty when none is open
  Notes:
    Which file the Parts tab shows.
  =========================================================================== }
function TfrLibraryPanel.PartsFileName: String;
begin
  if FPartsLib <> nil then
    Result := FPartsLib.FileName
  else
    Result := '';
end;

{ ===========================================================================
  TfrLibraryPanel.ReloadParts  (procedure)
  Notes:
    The parts file was changed by the library editor: the library is read again (class tree and parts) and the list is rebuilt, keeping the choice where it can.
  =========================================================================== }
procedure TfrLibraryPanel.ReloadParts;
begin
  if FPartsLib = nil then
    Exit;
  FPartsLib.Reload;
  FillParts;
end;

{ ===========================================================================
  TfrLibraryPanel.ClosePartsFile  (procedure)
  Parameters:  none
  Notes:
    Closes the parts library and empties the list.
  =========================================================================== }
procedure TfrLibraryPanel.ClosePartsFile;
begin
  FreeAndNil(FPartsLib);
  FillParts;
end;

{ ===========================================================================
  TfrLibraryPanel.FillParts  (procedure)
  Parameters:  none
  Notes:
    Lists the parts of the open parts library: the icon (the stored size nearest to the 24 pixels of the image list, drawn into it at that size), the name and
    the class. A icon that is not a PNG that can be read is left out (the part is listed without one).
  =========================================================================== }
procedure TfrLibraryPanel.FillParts;
var
  i, Sz: Integer;
  Png: String;
  Ms: TMemoryStream;
  G: TPortableNetworkGraphic;
  Bmp: TBitmap;
  It: TListItem;
begin
  lvParts.Items.BeginUpdate;
  try
    lvParts.Items.Clear;
    ilParts.Clear;
    if FPartsLib = nil then
    begin
      lbPartsCaption.Caption := rsPartsLibraryNoneOpen;
      Exit;
    end;
    lbPartsCaption.Caption := Format(rsPartsLibrary2, [FPartsLib.LibraryName]);
    for i := 0 to FPartsLib.PartCount - 1 do
    begin
      It := lvParts.Items.Add;
      It.Caption := FPartsLib.Parts[i].Name;
      It.SubItems.Add(FPartsLib.Parts[i].ClassName);
      It.Data := Pointer(PtrInt(i));
      It.ImageIndex := -1;
      Png := FPartsLib.GlyphPng(FPartsLib.Parts[i].ID, ilParts.Width, Sz);
      if Png <> '' then
      begin
        Ms := TMemoryStream.Create;
        G := TPortableNetworkGraphic.Create;
        Bmp := TBitmap.Create;
        try
          try
            Ms.WriteBuffer(Png[1], Length(Png));
            Ms.Position := 0;
            G.LoadFromStream(Ms);
            Bmp.SetSize(ilParts.Width, ilParts.Height);
            Bmp.Canvas.StretchDraw(Rect(0, 0, ilParts.Width, ilParts.Height), G);      // (the same size draws 1:1; another size is scaled)
            It.ImageIndex := ilParts.Add(Bmp, nil);
          except
            It.ImageIndex := -1;
          end;
        finally
          Bmp.Free;
          G.Free;
          Ms.Free;
        end;
      end;
    end;
  finally
    lvParts.Items.EndUpdate;
  end;
end;

{ ===========================================================================
  TfrLibraryPanel.PartsOpenClick  (procedure)
  Parameters:
    Sender: TObject - the button
  Notes:
    The Open button of the Parts tab: asks for a file and opens it; a file that cannot be used is explained in a message.
  =========================================================================== }
procedure TfrLibraryPanel.PartsOpenClick(Sender: TObject);
begin
  if dlgPartsOpen.Execute and not OpenPartsFile(dlgPartsOpen.FileName) then
    MessageDlg(rsPartsLibrary, FPartsError, mtError, [mbOK], 0);
end;

{ ===========================================================================
  TfrLibraryPanel.PartsSelectItem  (procedure)
  Parameters:
    Sender: TObject - the list
    Item: TListItem - the item
    Selected: Boolean - whether it became selected
  Notes:
    Tells the owner which part is chosen.
  =========================================================================== }
procedure TfrLibraryPanel.PartsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected and Assigned(FOnPartSelected) then
    FOnPartSelected(Self, PtrInt(Item.Data));
end;

{ ===========================================================================
  TfrLibraryPanel.PartsDblClick  (procedure)
  Parameters:
    Sender: TObject - the list
  Notes:
    A double click on a part asks the owner to place it.
  =========================================================================== }
procedure TfrLibraryPanel.PartsDblClick(Sender: TObject);
begin
  if (lvParts.Selected <> nil) and Assigned(FOnPartPlace) then
    FOnPartPlace(Self, PtrInt(lvParts.Selected.Data));
end;

function TfrLibraryPanel.PartsRowCount: Integer;
begin
  Result := lvParts.Items.Count;
end;

function TfrLibraryPanel.PartsRowText(Index: Integer): String;
begin
  Result := lvParts.Items[Index].Caption + '|' + lvParts.Items[Index].SubItems[0];
end;

function TfrLibraryPanel.PartsRowImage(Index: Integer): Integer;
begin
  Result := lvParts.Items[Index].ImageIndex;
end;

procedure TfrLibraryPanel.SelectPartRow(Index: Integer);
begin
  lvParts.Selected := lvParts.Items[Index];
end;

function TfrLibraryPanel.SelectedPartIndex: Integer;
begin
  if lvParts.Selected = nil then
    Result := -1
  else
    Result := PtrInt(lvParts.Selected.Data);
end;

{ ===========================================================================
  TfrLibraryPanel.CloseAll  (procedure)
  Parameters:  none
  Notes:
    Closes every library and empties the tree.
  =========================================================================== }
procedure TfrLibraryPanel.CloseAll;
var
  i: Integer;
begin
  for i := 0 to FEntries.Count - 1 do
    if not CanCloseEntry(i) then
      Exit;           // one is in use: all stay open
  ClearPreview;
  FRebuilding := True;
  try
    tvLib.Items.Clear;
    FRefs.Clear;
  finally
    FRebuilding := False;
  end;
  FEntries.Clear;
  UpdateCaption;
  pbPreview.Invalidate;
  Changed;
end;

{ ===========================================================================
  TfrLibraryPanel.Changed  (procedure)
  Parameters:  none
  Notes:
    Tells the owner (OnChanged) that the libraries in use are not the same any more.
  =========================================================================== }
procedure TfrLibraryPanel.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

{ ===========================================================================
  TfrLibraryPanel.IndexOfFile  (function)
  Parameters:
    const FileName: String - path of the file
  Returns:
    Integer - the position among the open libraries, or -1
  Notes:
    Finds the open library read from a file (the same file under another spelling of its path
    counts as the same).
  =========================================================================== }
function TfrLibraryPanel.IndexOfFile(const FileName: String): Integer;
begin
  Result := FindEntry(ExpandFileName(FileName));
end;

{ ===========================================================================
  TfrLibraryPanel.LibCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many libraries are open.
  =========================================================================== }
function TfrLibraryPanel.LibCount: Integer;
begin
  Result := FEntries.Count;
end;

{ ===========================================================================
  TfrLibraryPanel.FindSymbolByName  (function)
  Parameters:
    const SymName: String - text
    Sheet: TDesignSheet - the sheet
  Returns:
    TDesignFileSymbol
  Notes:
    CLibraryCollection::GetSymbol followed by GetDesignSymbol(sheet, 0): the libraries are
    searched in the order they were opened, then their symbols, and the first symbol with a name
    of that spelling (ignoring case) wins. Its first name's definition is built, as the C++ does
    whichever name matched. Used for the oldest binary design objects, which store the symbol by
    name.
  =========================================================================== }
function TfrLibraryPanel.FindSymbolByName(const SymName: String; Sheet: TDesignSheet): TDesignFileSymbol;
var
  e, i, r: Integer;
  SLib: TSymbolLibrary;
  St: TLibrarySymbolSet;
begin
  Result := nil;
  if SymName = '' then
    Exit;
  for e := 0 to FEntries.Count - 1 do
  begin
    SLib := TLibEntry(FEntries[e]).Lib;
    for i := 0 to SLib.SetCount - 1 do
    begin
      St := SLib.Sets[i];
      for r := 0 to St.RecordCount - 1 do
        if CompareText(St.Records[r].Name, SymName) = 0 then
        begin
          Result := SLib.GetDesignSymbol(Sheet, St, 0);
          Exit;
        end;
    end;
  end;
end;

{ ===========================================================================
  TfrLibraryPanel.LibFileName  (function)
  Parameters:
    Index: Integer - position in the list of open libraries
  Returns:
    String - the full path
  Notes:
    The file an open library was read from.
  =========================================================================== }
function TfrLibraryPanel.LibFileName(Index: Integer): String;
begin
  Result := TLibEntry(FEntries[Index]).FileName;
end;

{ ===========================================================================
  TfrLibraryPanel.LibAt  (function)
  Parameters:
    Index: Integer - position in the list of open libraries
  Returns:
    TSymbolLibrary - the library (owned by the panel)
  Notes:
    An open library.
  =========================================================================== }
function TfrLibraryPanel.LibAt(Index: Integer): TSymbolLibrary;
begin
  Result := TLibEntry(FEntries[Index]).Lib;
end;

{ ===========================================================================
  TfrLibraryPanel.Lib  (function)
  Parameters:  none
  Returns:
    TSymbolLibrary - the library, or nil when none is open
  Notes:
    The library of the selected node, otherwise the first open library.
  =========================================================================== }
function TfrLibraryPanel.Lib: TSymbolLibrary;
var
  E: TLibEntry;
begin
  E := SelectedEntry;
  if E <> nil then
    Result := E.Lib
  else if FEntries.Count > 0 then
    Result := TLibEntry(FEntries[0]).Lib
  else
    Result := nil;
end;

{ ===========================================================================
  TfrLibraryPanel.RecordNode  (function)
  Parameters:
    Index: Integer - symbol position, 0-based
  Returns:
    TTreeNode - the node, or nil
  Notes:
    The node of the n-th symbol in tree order (across all libraries, whether or not its library
    is open).
  =========================================================================== }
function TfrLibraryPanel.RecordNode(Index: Integer): TTreeNode;
var
  i, n: Integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to tvLib.Items.Count - 1 do
    if tvLib.Items[i].Level = 1 then
    begin
      if n = Index then
      begin
        Result := tvLib.Items[i];
        Exit;
      end;
      Inc(n);
    end;
end;

{ ===========================================================================
  TfrLibraryPanel.SelectRow  (procedure)
  Parameters:
    Index: Integer - symbol position, 0-based
  Notes:
    Selects the n-th symbol in tree order, opening its library, and shows its preview. An index
    out of range is ignored.
  =========================================================================== }
procedure TfrLibraryPanel.SelectRow(Index: Integer);
var
  N: TTreeNode;
begin
  N := RecordNode(Index);
  if N = nil then
    Exit;
  N.Parent.Expanded := True;
  tvLib.Selected := N;
  BuildPreview;
  pbPreview.Invalidate;
end;

{ ===========================================================================
  TfrLibraryPanel.PlaceSelected  (procedure)
  Parameters:  none
  Notes:
    Asks the owner to place the selected symbol (OnPlace); a library node or no selection does
    nothing.
  =========================================================================== }
procedure TfrLibraryPanel.PlaceSelected;
var
  Ref: TLibNodeRef;
begin
  Ref := SelectedRef;
  if Ref = nil then
    Exit;
  if Assigned(FOnPlace) then
    FOnPlace(Self, Ref.Entry.Lib, Ref.SetIndex, Ref.RecIndex);
end;

{ ===========================================================================
  TfrLibraryPanel.RowCount  (function)
  Parameters:  none
  Returns:
    Integer - the count
  Notes:
    How many symbols the tree lists (those matching the filter), across all libraries.
  =========================================================================== }
function TfrLibraryPanel.RowCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to tvLib.Items.Count - 1 do
    if tvLib.Items[i].Level = 1 then
      Inc(Result);
end;

{ ===========================================================================
  TfrLibraryPanel.RowText  (function)
  Parameters:
    Index: Integer - symbol position, 0-based
  Returns:
    String - the text, or empty when out of range
  Notes:
    The text of the n-th symbol in tree order: its name and description.
  =========================================================================== }
function TfrLibraryPanel.RowText(Index: Integer): String;
var
  N: TTreeNode;
begin
  N := RecordNode(Index);
  if N = nil then
    Result := ''
  else
    Result := N.Text;
end;

end.
