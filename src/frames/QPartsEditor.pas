// SPDX-License-Identifier: LGPL-2.1-or-later
{ The parts library editor (Phase B of the parts database): one open parts file shown as a tab of the document strip next to the designs and symbols. This
  version edits the library's own details (name, description, author) and the list of generic parts: Add, Properties (name, reference letters, description,
  status), Duplicate and Delete. Every change is written to the file at once (one transaction each, Revision and Modified stamped), so there is nothing to save.
  The frame owns its own connection to the file; OnChanged tells the owner when the list in the library panel must be read again.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit QPartsEditor;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Menus, UPartsDb, Fpartedit, Fclassedit, Ffieldedit, Fratingedit, Fobjectedit, Fproductedit, Fvalueedit, Fsymbolinfo, UGlyph;

type
  TPartSymbolEvent = procedure(Sender: TObject; PartID, SymbolID: Int64) of object;

  { TfrPartsEditor }

  TfrPartsEditor = class(TFrame)
    btnAdd: TButton;
    btnDelete: TButton;
    btnDuplicate: TButton;
    btnEdit: TButton;
    btnClassAdd: TButton;
    btnValClear: TButton;
    btnValEdit: TButton;
    cbValPart: TComboBox;
    lblValPart: TLabel;
    lvValues: TListView;
    miValClear: TMenuItem;
    miValEdit: TMenuItem;
    pmValues: TPopupMenu;
    pnlValTools: TPanel;
    tsValues: TTabSheet;
    btnSymDefault: TButton;
    btnSymDelete: TButton;
    btnSymEdit: TButton;
    btnSymImport: TButton;
    btnSymNew: TButton;
    btnSymProps: TButton;
    cbSymPart: TComboBox;
    lblSymPart: TLabel;
    lvSymbols: TListView;
    pnlSymTools: TPanel;
    tsSymbols: TTabSheet;
    btnProdAdd: TButton;
    btnProdDelete: TButton;
    btnProdEdit: TButton;
    btnProdPreferred: TButton;
    btnProdRatAdd: TButton;
    btnProdRatDelete: TButton;
    btnProdRatEdit: TButton;
    btnProdSuggest: TButton;
    cbProdPart: TComboBox;
    lblProdPart: TLabel;
    lvProdRatings: TListView;
    lvProducts: TListView;
    miProdAdd: TMenuItem;
    miProdDelete: TMenuItem;
    miProdEdit: TMenuItem;
    miProdRatAdd: TMenuItem;
    miProdRatDelete: TMenuItem;
    miProdRatEdit: TMenuItem;
    pmProdRatings: TPopupMenu;
    pmProducts: TPopupMenu;
    pnlProdRat: TPanel;
    pnlProdRatTools: TPanel;
    pnlProdTools: TPanel;
    splProducts: TSplitter;
    tsProducts: TTabSheet;
    btnObjAdd: TButton;
    btnObjDelete: TButton;
    btnObjEdit: TButton;
    cbObjPart: TComboBox;
    lblObjPart: TLabel;
    miObjAdd: TMenuItem;
    miObjDelete: TMenuItem;
    miObjEdit: TMenuItem;
    pmObjects: TPopupMenu;
    pnlObjTools: TPanel;
    tsObjects: TTabSheet;
    tvObjects: TTreeView;
    btnRatAdd: TButton;
    btnRatDelete: TButton;
    btnRatEdit: TButton;
    cbRatPart: TComboBox;
    lblRatPart: TLabel;
    lvRatings: TListView;
    miRatAdd: TMenuItem;
    miRatDelete: TMenuItem;
    miRatEdit: TMenuItem;
    pmRatings: TPopupMenu;
    pnlRatTools: TPanel;
    tsRatings: TTabSheet;
    btnClassDelete: TButton;
    btnClassProps: TButton;
    btnFieldAdd: TButton;
    btnFieldDelete: TButton;
    btnFieldEdit: TButton;
    btnLibApply: TButton;
    edLibAuthor: TEdit;
    edLibDesc: TEdit;
    edLibName: TEdit;
    lblLibAuthor: TLabel;
    lblLibDesc: TLabel;
    lblLibFile: TLabel;
    lblLibName: TLabel;
    lblClassInfo: TLabel;
    lvFields: TListView;
    lvParts: TListView;
    miClassAdd: TMenuItem;
    miClassDelete: TMenuItem;
    miClassProps: TMenuItem;
    miFieldAdd: TMenuItem;
    miFieldDelete: TMenuItem;
    miFieldEdit: TMenuItem;
    pcEditor: TPageControl;
    pmClasses: TPopupMenu;
    pmFields: TPopupMenu;
    pnlClassInfo: TPanel;
    pnlClassRight: TPanel;
    pnlClassTools: TPanel;
    splClasses: TSplitter;
    tsClasses: TTabSheet;
    tsParts: TTabSheet;
    tvClasses: TTreeView;
    miPartAdd: TMenuItem;
    miPartDelete: TMenuItem;
    miPartDuplicate: TMenuItem;
    miPartEdit: TMenuItem;
    pmParts: TPopupMenu;
    pnlInfo: TPanel;
    pnlTools: TPanel;
    procedure AddClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure DuplicateClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure LibApplyClick(Sender: TObject);
    procedure PartsDblClick(Sender: TObject);
    procedure PartsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure PageChange(Sender: TObject);
    procedure ValEditClick(Sender: TObject);
    procedure ValClearClick(Sender: TObject);
    procedure ValSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ValPartChange(Sender: TObject);
    procedure SymPartChange(Sender: TObject);
    procedure SymSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure SymNewClick(Sender: TObject);
    procedure SymEditClick(Sender: TObject);
    procedure SymImportClick(Sender: TObject);
    procedure SymPropsClick(Sender: TObject);
    procedure SymDefaultClick(Sender: TObject);
    procedure SymDeleteClick(Sender: TObject);
    procedure ProdAddClick(Sender: TObject);
    procedure ProdEditClick(Sender: TObject);
    procedure ProdDeleteClick(Sender: TObject);
    procedure ProdSuggestClick(Sender: TObject);
    procedure ProdPreferredClick(Sender: TObject);
    procedure ProdSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ProdPartChange(Sender: TObject);
    procedure ProdRatAddClick(Sender: TObject);
    procedure ProdRatEditClick(Sender: TObject);
    procedure ProdRatDeleteClick(Sender: TObject);
    procedure ProdRatSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ObjAddClick(Sender: TObject);
    procedure ObjEditClick(Sender: TObject);
    procedure ObjDeleteClick(Sender: TObject);
    procedure ObjDblClick(Sender: TObject);
    procedure ObjChange(Sender: TObject; Node: TTreeNode);
    procedure ObjPartChange(Sender: TObject);
    procedure RatAddClick(Sender: TObject);
    procedure RatEditClick(Sender: TObject);
    procedure RatDeleteClick(Sender: TObject);
    procedure RatDblClick(Sender: TObject);
    procedure RatSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure RatPartChange(Sender: TObject);
    procedure ClassAddClick(Sender: TObject);
    procedure ClassPropsClick(Sender: TObject);
    procedure ClassDeleteClick(Sender: TObject);
    procedure FieldAddClick(Sender: TObject);
    procedure FieldEditClick(Sender: TObject);
    procedure FieldDeleteClick(Sender: TObject);
    procedure ClassTreeChange(Sender: TObject; Node: TTreeNode);
    procedure ClassTreeDblClick(Sender: TObject);
    procedure FieldDblClick(Sender: TObject);
    procedure FieldCustomDraw(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure FieldSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
  private
    FFields: TFieldInfoArray;      // the fields shown in lvFields (row Data = index)
    FValues: TValueRowArray;       // the field rows shown in lvValues (row Data = index)
    FProducts: TProductRowArray;    // the products shown in lvProducts (row Data = index)
    FProdFit: TProductInfoArray;    // their verdicts for the part chosen in cbProdPart
    FProdRatings: TPartRatingArray; // the ratings of the chosen product (row Data = index)
    FObjects: TObjectRefArray;     // the child objects shown in tvObjects (node Data = index)
    FRatings: TPartRatingArray;    // the requirements shown in lvRatings (row Data = index)
    FLib: TPartsLibrary;           // this editor's own connection to the file (owned)
    FOnChanged: TNotifyEvent;
    FSymbols: TSymbolRowArray;     // the symbols shown in lvSymbols (row Data = index)
    FOnEditSymbol: TPartSymbolEvent;
    FOnImportSymbol: TPartSymbolEvent;
    FLastError: String;
    procedure Changed;
    procedure ShowError(const Msg: String);
    procedure UpdateButtons;
    procedure UpdateClassButtons;
    procedure UpdateValButtons;
    procedure FillValParts(WantID: Int64);
    procedure FillSymParts(WantID: Int64);
    procedure FillSymbols(WantID: Int64);
    procedure UpdateSymButtons;
    procedure FillValues(SelectIndex: Integer);
    procedure UpdateProdButtons;
    procedure FillProdParts(WantID: Int64);
    procedure FillProducts(SelectID: Int64);
    procedure FillProdRatings(SelectID: Int64);
    function ProductIndexOfID(ProductID: Int64): Integer;
    function ProdRatingIndexOfID(RatingID: Int64): Integer;
    function FitText(const P: TProductRow): String;
    procedure UpdateObjButtons;
    procedure FillObjParts(WantID: Int64);
    procedure FillObjects(SelectID: Int64);
    function ObjectIndexOfID(ObjectID: Int64): Integer;
    procedure UpdateRatButtons;
    procedure FillRatParts(WantID: Int64);
    procedure FillRatings(SelectID: Int64);
    function RatingIndexOfID(RatingID: Int64): Integer;
    procedure FillFields;
    function ClassPath(ClassID: Int64): String;
  public
    destructor Destroy; override;
    { opens the file for editing (EPartsError when it cannot be used) and shows its details and parts }
    procedure LoadFile(const AFileName: String);
    { shows the library's details and parts again; the part with that PartID (0 for none) is chosen }
    procedure Refresh(SelectPartID: Int64);
    { the commands (the Parts menu and the buttons). Add / Properties ask in the dialog, Duplicate asks for the name, Delete asks to confirm }
    procedure CmdAdd;
    procedure CmdProperties;
    procedure CmdDuplicate;
    procedure CmdDelete;
    { the same without any question, as the dialogs and the scripts use them: False (LastError says why) when the library refused }
    function AddPart(const AName: String; AClassID: Int64; const ARef, ADesc: String): Boolean;
    function ChangePart(PartID: Int64; const AName, ARef, ADesc, AStatus: String): Boolean;
    function CopyPart(PartID: Int64; const NewName: String): Boolean;
    function RemovePart(PartID: Int64): Boolean;
    function ApplyLibraryInfo(const AName, ADesc, AAuthor: String): Boolean;
    { the PartID of the chosen row, 0 for none }
    function SelectedPartID: Int64;
    function CanChangeSelected: Boolean;
    { the classes page: the tree of part classes and the fields of the chosen class. Add / Properties ask in the dialogs, Delete asks to confirm }
    procedure RefreshClasses(SelectClassID: Int64);
    procedure CmdAddClass;
    procedure CmdClassProperties;
    procedure CmdDeleteClass;
    procedure CmdAddField;
    procedure CmdFieldProperties;
    procedure CmdDeleteField;
    { the same without any question (False and LastError when the library refused) }
    function AddClass(const AName: String; AParentID: Int64; AAbstract: Boolean; const ADesc: String): Boolean;
    function ChangeClass(ClassID: Int64; const AName: String; AParentID: Int64; AAbstract: Boolean; const ADesc: String): Boolean;
    function RemoveClass(ClassID: Int64): Boolean;
    function AddField(ClassID: Int64; const AName, AType, AUnit, AEnum: String; ARequired: Boolean; const ADesc: String): Boolean;
    function ChangeField(FieldID: Int64; const AName, AType, AUnit, AEnum: String; ARequired: Boolean; const ADesc: String): Boolean;
    function RemoveField(FieldID: Int64): Boolean;
    { the ClassID of the chosen tree node (0 for none); the FieldID of the chosen field row (0 for none) and whether the chosen class declares it itself }
    function SelectedClassID: Int64;
    function SelectedFieldID: Int64;
    function SelectedFieldIsOwn: Boolean;
    { 'parts' or 'classes': the page shown }
    function PageName: String;
    procedure ShowPage(const AName: String);
    { the Requirements page: the ratings the chosen part must have. Add / Properties ask in the dialog, Delete asks to confirm }
    procedure CmdEditValue;
    procedure CmdClearValue;
    { the value edit without any question (False and LastError when the library refused); see TPartsLibrary.SetFieldValue }
    function SetValue(ObjectID, FieldID: Int64; const AValue: String): Boolean;
    function CurrentValPartID: Int64;
    function SelectedValueRow: Integer;
    function ValueRowObject(Row: Integer): Int64;
    function ValueRowField(Row: Integer): Int64;
    function ValueRowAt(Row: Integer): TValueRow;
    procedure CmdAddProduct;
    { Parts > Import Products from CSV... / Export Products to CSV... (Products page); the file versions are what the script and the commands use }
    function ImportProductsFile(const AFile: String; out Msg: String): Boolean;
    function ExportProductsFile(const AFile: String; out Msg: String): Boolean;
    procedure CmdImportProducts;
    procedure CmdExportProducts;
    procedure CmdProductProperties;
    procedure CmdDeleteProduct;
    procedure CmdSuggestProduct;
    procedure CmdPreferProduct;
    procedure CmdAddProdRating;
    procedure CmdProdRatingProperties;
    procedure CmdDeleteProdRating;
    { the product edits without any question (False and LastError when the library refused); see TPartsLibrary.AddProduct and AddProductRating }
    function AddProductRow(ClassID: Int64; const AManufacturer, AMPN, ASeries, ADescription, AStatus: String): Boolean;
    function ChangeProductRow(ProductID, ClassID: Int64; const AManufacturer, AMPN, ASeries, ADescription, AStatus: String): Boolean;
    function RemoveProductRow(ProductID: Int64): Boolean;
    function SuggestProductFor(ProductID: Int64; State: Integer): Boolean;
    function AddProdRatingRow(ProductID: Int64; const AAppliesTo, AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Boolean;
    function ChangeProdRatingRow(RatingID: Int64; const AAppliesTo, AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Boolean;
    function RemoveProdRatingRow(RatingID: Int64): Boolean;
    { the part the fit is shown for (0 for none), the chosen product and the chosen product rating (0 for none) }
    function CurrentProdPartID: Int64;
    function SelectedProductID: Int64;
    function SelectedProdRatingID: Int64;
    function ProductIDOfRow(Row: Integer): Int64;
    function ProdRatingIDOfRow(Row: Integer): Int64;
    procedure CmdAddObject;
    procedure CmdObjectProperties;
    procedure CmdDeleteObject;
    { the child object edits without any question (False and LastError when the library refused); see TPartsLibrary.AddObject }
    function AddChildObject(PartID, ParentID, KindID: Int64; const AName, ADesignator, ADescription: String; ASort: Integer): Boolean;
    function ChangeChildObject(ObjectID, ParentID, KindID: Int64; const AName, ADesignator, ADescription: String; ASort: Integer): Boolean;
    function RemoveChildObject(ObjectID: Int64): Boolean;
    { the part whose objects are shown (0 for none) and the chosen object (0 for none) }
    function CurrentObjPartID: Int64;
    function SelectedObjectID: Int64;
    function ObjectIDOfNode(Node: TTreeNode): Int64;
    procedure CmdAddRating;
    procedure CmdRatingProperties;
    procedure CmdDeleteRating;
    { the same without any question (False and LastError when the library refused); see TPartsLibrary.AddRating }
    function AddRequirement(PartID, ObjectID: Int64; const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Boolean;
    function ChangeRequirement(RatingID, ObjectID: Int64; const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Boolean;
    function RemoveRequirement(RatingID: Int64): Boolean;
    { the part whose requirements are shown (0 for none) and the chosen requirement's RatingID (0 for none) }
    function CurrentRatPartID: Int64;
    function SelectedRatingID: Int64;
    function RatingIDOfRow(Row: Integer): Int64;
    property Lib: TPartsLibrary read FLib;
    property LastError: String read FLastError;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    { Symbols page. The editor of the drawing is the main form's (the symbol editor document), so New / Edit / Import ask it through these events; the form hands the
      result back with StoreSymbolDrawing / AddSymbolDrawing. }
    property OnEditSymbol: TPartSymbolEvent read FOnEditSymbol write FOnEditSymbol;
    property OnImportSymbol: TPartSymbolEvent read FOnImportSymbol write FOnImportSymbol;
    function CurrentSymPartID: Int64;
    function SelectedSymbolRow: Integer;
    function SelectedSymbolID: Int64;
    function SymbolIDOfRow(Row: Integer): Int64;
    function SymbolRowAt(Row: Integer): TSymbolRow;
    function AddSymbolDrawing(PartID: Int64; const AStandard, APurpose, AName, ABlob: String; out NewID: Int64): Boolean;
    function StoreSymbolDrawing(SymbolID: Int64; const ABlob: String): Boolean;
    function ChangeSymbolInfo(SymbolID: Int64; const AStandard, APurpose, AName: String): Boolean;
    { SymbolID draws ObjectID of its part (0 = the whole device); False with LastError when refused }
    function ChangeSymbolShows(SymbolID, ObjectID: Int64): Boolean;
    function MakeDefaultSymbol(SymbolID: Int64): Boolean;
    function RemoveSymbol(SymbolID: Int64): Boolean;
    procedure CmdSymNew;
    procedure CmdSymEdit;
    procedure CmdSymImport;
    procedure CmdSymProps;
    procedure CmdSymDefault;
    procedure CmdSymDelete;
    { the library changed behind the frame's back (a symbol stored by the symbol editor): read the lists again }
    procedure ReloadAfterSymbolStore(PartID: Int64);
  end;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrPartsEditor.Destroy  (destructor)
  Notes:
    Closes the file.
  =========================================================================== }
destructor TfrPartsEditor.Destroy;
begin
  FLib.Free;
  inherited Destroy;
end;

{ ===========================================================================
  TfrPartsEditor.LoadFile  (procedure)
  Parameters:
    const AFileName: String - the parts file
  Notes:
    Opens the file (upgrading an older one as the library panel does) and shows it. Raises EPartsError when the file cannot be used.
  =========================================================================== }
procedure TfrPartsEditor.LoadFile(const AFileName: String);
var
  New: TPartsLibrary;
begin
  New := TPartsLibrary.Create;
  try
    New.Open(AFileName);
  except
    New.Free;
    raise;
  end;
  FLib.Free;
  FLib := New;
  Refresh(0);
end;

{ ===========================================================================
  TfrPartsEditor.Refresh  (procedure)
  Parameters:
    SelectPartID: Int64 - the part to choose afterwards, 0 for none
  Notes:
    Fills the library details and the list of parts from the library (columns: name, class, reference letters, status, revision, modified, description).
  =========================================================================== }
procedure TfrPartsEditor.Refresh(SelectPartID: Int64);
var
  i: Integer;
  It: TListItem;
begin
  lvParts.Items.BeginUpdate;
  try
    lvParts.Items.Clear;
    if FLib <> nil then
    begin
      edLibName.Text := FLib.LibraryName;
      edLibDesc.Text := FLib.LibraryDescription;
      edLibAuthor.Text := FLib.LibraryAuthor;
      lblLibFile.Caption := Format(rsGUID, [FLib.FileName, FLib.LibraryUID]);
      for i := 0 to FLib.PartCount - 1 do
      begin
        It := lvParts.Items.Add;
        It.Caption := FLib.Parts[i].Name;
        It.SubItems.Add(FLib.Parts[i].ClassName);
        It.SubItems.Add(FLib.Parts[i].RefPrefix);
        It.SubItems.Add(FLib.Parts[i].Status);
        It.SubItems.Add(FLib.Parts[i].Revision);
        It.SubItems.Add(FLib.Parts[i].Modified);
        It.SubItems.Add(FLib.Parts[i].Description);
        It.Data := Pointer(PtrInt(FLib.Parts[i].ID));
        if FLib.Parts[i].ID = SelectPartID then
          It.Selected := True;
      end;
    end;
  finally
    lvParts.Items.EndUpdate;
  end;
  UpdateButtons;
  RefreshClasses(SelectedClassID);
  FillObjParts(0);
  FillRatParts(0);
  FillProdParts(0);
  FillValParts(0);
  FillSymParts(0);
end;

{ ===========================================================================
  TfrPartsEditor.UpdateButtons  (procedure)
  Notes:
    Enables Properties, Duplicate and Delete (and the pop-up menu's) only while a part is chosen.
  =========================================================================== }
procedure TfrPartsEditor.UpdateButtons;
var
  Have: Boolean;
begin
  Have := SelectedPartID <> 0;
  btnEdit.Enabled := Have;
  btnDuplicate.Enabled := Have;
  btnDelete.Enabled := Have;
  miPartEdit.Enabled := Have;
  miPartDuplicate.Enabled := Have;
  miPartDelete.Enabled := Have;
end;

function TfrPartsEditor.SelectedPartID: Int64;
begin
  Result := 0;
  if lvParts.Selected <> nil then
    Result := PtrInt(lvParts.Selected.Data);
end;

function TfrPartsEditor.CanChangeSelected: Boolean;
begin
  Result := (FLib <> nil) and (SelectedPartID <> 0);
end;

procedure TfrPartsEditor.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TfrPartsEditor.ShowError(const Msg: String);
begin
  MessageDlg(rsPartsLibrary, Msg, mtError, [mbOK], 0);
end;

{ ===========================================================================
  TfrPartsEditor.AddPart  (function)
  Parameters:
    const AName: String - the name
    AClassID: Int64 - the class
    const ARef, ADesc: String - reference letters and description
  Returns:
    Boolean - True when the part was added (and is now the chosen row)
  Notes:
    Adds the part to the library without asking anything; on a refusal LastError holds the reason.
  =========================================================================== }
function TfrPartsEditor.AddPart(const AName: String; AClassID: Int64; const ARef, ADesc: String): Boolean;
var
  Id: Int64;
begin
  Result := False;
  FLastError := '';
  try
    Id := FLib.AddPart(AName, AClassID, ARef, ADesc);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(Id);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.ChangePart  (function)
  Parameters:
    PartID: Int64 - the part
    const AName, ARef, ADesc, AStatus: String - the new details
  Returns:
    Boolean - True when it was changed
  Notes:
    Changes the details of a part (Revision up by one, Modified stamped); LastError holds the reason when the library refused.
  =========================================================================== }
function TfrPartsEditor.ChangePart(PartID: Int64; const AName, ARef, ADesc, AStatus: String): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.UpdatePart(PartID, AName, ARef, ADesc, AStatus);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(PartID);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.CopyPart  (function)
  Parameters:
    PartID: Int64 - the part to copy
    const NewName: String - the copy's name
  Returns:
    Boolean - True when the copy was made (it becomes the chosen row)
  Notes:
    Duplicates the part and everything of it; LastError holds the reason when the library refused.
  =========================================================================== }
function TfrPartsEditor.CopyPart(PartID: Int64; const NewName: String): Boolean;
var
  Id: Int64;
begin
  Result := False;
  FLastError := '';
  try
    Id := FLib.DuplicatePart(PartID, NewName);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(Id);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.RemovePart  (function)
  Parameters:
    PartID: Int64 - the part
  Returns:
    Boolean - True when it was deleted
  Notes:
    Deletes the part without asking; LastError holds the reason when the library refused.
  =========================================================================== }
function TfrPartsEditor.RemovePart(PartID: Int64): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.DeletePart(PartID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(0);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.ApplyLibraryInfo  (function)
  Parameters:
    const AName, ADesc, AAuthor: String - the library's details
  Returns:
    Boolean - True when they were written
  Notes:
    Writes the library name, description and author; LastError holds the reason when the library refused (an empty name).
  =========================================================================== }
function TfrPartsEditor.ApplyLibraryInfo(const AName, ADesc, AAuthor: String): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.SetLibraryInfo(AName, ADesc, AAuthor);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.CmdAdd  (procedure)
  Notes:
    Parts > Add Part...: the Part dialog for a new part; OK adds it, a refusal is explained and the dialog opens again with the entries.
  =========================================================================== }
procedure TfrPartsEditor.CmdAdd;
var
  Dlg: TfrmPartEdit;
begin
  if FLib = nil then
    Exit;
  Dlg := TfrmPartEdit.Create(Self);
  try
    Dlg.Setup(FLib, -1);
    while Dlg.ShowModal = mrOK do
    begin
      if AddPart(Dlg.PartName, Dlg.ClassID, Dlg.RefPrefix, Dlg.Description) then
      begin
        { (the status of a new part is 'active'; another status is set right away) }
        if (Dlg.Status <> 'active') and (SelectedPartID <> 0) then
          ChangePart(SelectedPartID, Dlg.PartName, Dlg.RefPrefix, Dlg.Description, Dlg.Status);
        Break;
      end;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdProperties  (procedure)
  Notes:
    Parts > Part Properties...: the Part dialog for the chosen part (class fixed); OK writes the changes.
  =========================================================================== }
procedure TfrPartsEditor.CmdProperties;
var
  Dlg: TfrmPartEdit;
  Id: Int64;
begin
  Id := SelectedPartID;
  if (FLib = nil) or (Id = 0) then
    Exit;
  Dlg := TfrmPartEdit.Create(Self);
  try
    Dlg.Setup(FLib, FLib.PartIndexOfID(Id));
    while Dlg.ShowModal = mrOK do
    begin
      if ChangePart(Id, Dlg.PartName, Dlg.RefPrefix, Dlg.Description, Dlg.Status) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdDuplicate  (procedure)
  Notes:
    Parts > Duplicate Part: asks for the copy's name (the old name and " copy" to start with) and copies the chosen part.
  =========================================================================== }
procedure TfrPartsEditor.CmdDuplicate;
var
  Id: Int64;
  NewName: String;
begin
  Id := SelectedPartID;
  if (FLib = nil) or (Id = 0) then
    Exit;
  NewName := Format(rsCopy, [FLib.Parts[FLib.PartIndexOfID(Id)].Name]);
  while InputQuery(rsDuplicatePart, rsNameOfTheCopy, NewName) do
  begin
    if CopyPart(Id, NewName) then
      Break;
    ShowError(FLastError);
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdDelete  (procedure)
  Notes:
    Parts > Delete Part: asks to confirm (saying how many products are listed as suitable for it, which lose that suggestion; the products stay) and deletes the
    chosen part. Designs that have placed the part keep their own copy.
  =========================================================================== }
procedure TfrPartsEditor.CmdDelete;
var
  Id: Int64;
  Msg: String;
  N: Integer;
begin
  Id := SelectedPartID;
  if (FLib = nil) or (Id = 0) then
    Exit;
  N := FLib.SuggestionCount(Id);
  Msg := Format(rsDeleteThePartWithIts, [FLib.Parts[FLib.PartIndexOfID(Id)].Name]);
  if N > 0 then
    Msg := Format(rsProductSAreListedAs, [Msg, N]);
  Msg := Format(rsDesignsThatHavePlacedThe, [Msg]);
  if MessageDlg(rsDeletePart, Msg, mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    if not RemovePart(Id) then
      ShowError(FLastError);
end;

{ ===========================================================================
  TfrPartsEditor.ClassPath  (function)
  Parameters:
    ClassID: Int64 - a class
  Returns:
    String - its name with those of its parents, root first, joined with " > "
  =========================================================================== }
function TfrPartsEditor.ClassPath(ClassID: Int64): String;
var
  i, G: Integer;
begin
  Result := '';
  G := 0;
  while (ClassID <> 0) and (G < 100) do
  begin
    i := FLib.ClassIndexOfID(ClassID);
    if i < 0 then
      Break;
    if Result = '' then
      Result := FLib.Classes[i].Name
    else
      Result := FLib.Classes[i].Name + ' > ' + Result;
    ClassID := FLib.Classes[i].ParentID;
    Inc(G);
  end;
end;

{ ===========================================================================
  TfrPartsEditor.RefreshClasses  (procedure)
  Parameters:
    SelectClassID: Int64 - the class to choose afterwards (0 = the first root)
  Notes:
    Builds the tree of the part classes (children sorted by name, everything expanded; an abstract class is shown in brackets) and the field list of the
    chosen class.
  =========================================================================== }
procedure TfrPartsEditor.RefreshClasses(SelectClassID: Int64);
  procedure AddChildren(Parent: TTreeNode; ParentID: Int64);
  var
    i: Integer;
    L: TStringList;
    N: TTreeNode;
    Cap: String;
  begin
    L := TStringList.Create;
    try
      for i := 0 to FLib.ClassCount - 1 do
        if FLib.Classes[i].ParentID = ParentID then
          L.AddObject(FLib.Classes[i].Name, TObject(PtrInt(FLib.Classes[i].ID)));
      L.Sort;
      for i := 0 to L.Count - 1 do
      begin
        Cap := L[i];
        if FLib.Classes[FLib.ClassIndexOfID(PtrInt(L.Objects[i]))].Abstract then
          Cap := '(' + Cap + ')';
        N := tvClasses.Items.AddChildObject(Parent, Cap, L.Objects[i]);
        AddChildren(N, PtrInt(L.Objects[i]));
      end;
    finally
      L.Free;
    end;
  end;
var
  i: Integer;
begin
  tvClasses.Items.BeginUpdate;
  try
    tvClasses.Items.Clear;
    if FLib <> nil then
    begin
      AddChildren(nil, 0);
      tvClasses.FullExpand;
      for i := 0 to tvClasses.Items.Count - 1 do
        if PtrInt(tvClasses.Items[i].Data) = SelectClassID then
          tvClasses.Selected := tvClasses.Items[i];
      if (tvClasses.Selected = nil) and (tvClasses.Items.Count > 0) then
        tvClasses.Selected := tvClasses.Items[0];
    end;
  finally
    tvClasses.Items.EndUpdate;
  end;
  FillFields;
end;

{ ===========================================================================
  TfrPartsEditor.FillFields  (procedure)
  Notes:
    Shows the fields of the chosen class (inherited ones first, in grey; "Declared by" names the class that owns each) and, above, what the class is: its
    path, whether abstract and how many parts and products it has.
  =========================================================================== }
procedure TfrPartsEditor.FillFields;
var
  i, Idx: Integer;
  It: TListItem;
  Id: Int64;
  Info: String;
begin
  lvFields.Items.BeginUpdate;
  try
    lvFields.Items.Clear;
    SetLength(FFields, 0);
    Id := SelectedClassID;
    if (FLib <> nil) and (Id <> 0) then
    begin
      FFields := FLib.ClassFieldList(Id);
      for i := 0 to High(FFields) do
      begin
        It := lvFields.Items.Add;
        It.Caption := FFields[i].Name;
        It.SubItems.Add(FFields[i].FieldType);
        It.SubItems.Add(FFields[i].Unit_);
        if FFields[i].Required then
          It.SubItems.Add(rsYes2)
        else
          It.SubItems.Add('');
        It.SubItems.Add(FFields[i].DeclaredBy);
        if FFields[i].EnumValues <> '' then
          It.SubItems.Add('{' + FFields[i].EnumValues + '} ' + FFields[i].Description)
        else
          It.SubItems.Add(FFields[i].Description);
        It.Data := Pointer(PtrInt(i));
      end;
      Idx := FLib.ClassIndexOfID(Id);
      Info := ClassPath(Id);
      if FLib.Classes[Idx].Abstract then
        Info := Format(rsAbstract, [Info]);
      Info := Format(rsPartSProductS, [Info, FLib.ClassPartCount(Id), FLib.ClassProductCount(Id)]);
      lblClassInfo.Caption := Info;
    end
    else
      lblClassInfo.Caption := ' ';
  finally
    lvFields.Items.EndUpdate;
  end;
  UpdateClassButtons;
end;

{ ===========================================================================
  TfrPartsEditor.UpdateClassButtons  (procedure)
  Notes:
    Class Properties and Delete Class need a chosen class; Add Field too; Field Properties and Delete Field only while a field the class declares itself is
    chosen (the inherited ones are changed on the class that owns them).
  =========================================================================== }
procedure TfrPartsEditor.UpdateClassButtons;
var
  HaveC, HaveF: Boolean;
begin
  HaveC := SelectedClassID <> 0;
  HaveF := SelectedFieldIsOwn;
  btnClassProps.Enabled := HaveC;
  btnClassDelete.Enabled := HaveC;
  btnFieldAdd.Enabled := HaveC;
  btnFieldEdit.Enabled := HaveF;
  btnFieldDelete.Enabled := HaveF;
  miClassProps.Enabled := HaveC;
  miClassDelete.Enabled := HaveC;
  miFieldAdd.Enabled := HaveC;
  miFieldEdit.Enabled := HaveF;
  miFieldDelete.Enabled := HaveF;
end;

function TfrPartsEditor.SelectedClassID: Int64;
begin
  Result := 0;
  if tvClasses.Selected <> nil then
    Result := PtrInt(tvClasses.Selected.Data);
end;

function TfrPartsEditor.SelectedFieldID: Int64;
begin
  Result := 0;
  if (lvFields.Selected <> nil) and (PtrInt(lvFields.Selected.Data) <= High(FFields)) then
    Result := FFields[PtrInt(lvFields.Selected.Data)].ID;
end;

function TfrPartsEditor.SelectedFieldIsOwn: Boolean;
begin
  Result := (lvFields.Selected <> nil) and (PtrInt(lvFields.Selected.Data) <= High(FFields)) and (not FFields[PtrInt(lvFields.Selected.Data)].FromParent);
end;

function TfrPartsEditor.PageName: String;
begin
  if pcEditor.ActivePage = tsClasses then
    Result := 'classes'
  else if pcEditor.ActivePage = tsObjects then
    Result := 'objects'
  else if pcEditor.ActivePage = tsSymbols then
    Result := 'symbols'
  else if pcEditor.ActivePage = tsValues then
    Result := 'values'
  else if pcEditor.ActivePage = tsProducts then
    Result := 'products'
  else if pcEditor.ActivePage = tsRatings then
    Result := 'requirements'
  else
    Result := 'parts';
end;

procedure TfrPartsEditor.ShowPage(const AName: String);
begin
  if AName = 'classes' then
    pcEditor.ActivePage := tsClasses
  else if AName = 'objects' then
    pcEditor.ActivePage := tsObjects
  else if AName = 'symbols' then
    pcEditor.ActivePage := tsSymbols
  else if AName = 'values' then
    pcEditor.ActivePage := tsValues
  else if AName = 'products' then
    pcEditor.ActivePage := tsProducts
  else if AName = 'requirements' then
    pcEditor.ActivePage := tsRatings
  else
    pcEditor.ActivePage := tsParts;
  PageChange(nil);
end;

procedure TfrPartsEditor.PageChange(Sender: TObject);
begin
  Changed;      // (the Parts menu items depend on the page)
end;

{ ===========================================================================
  TfrPartsEditor.AddClass / ChangeClass / RemoveClass / AddField / ChangeField / RemoveField  (functions)
  Returns:
    Boolean - True when the library accepted the change
  Notes:
    The class and field edits without any question. The tree and fields are shown again and OnChanged fires; on a refusal LastError holds the reason and the
    file is unchanged.
  =========================================================================== }
function TfrPartsEditor.AddClass(const AName: String; AParentID: Int64; AAbstract: Boolean; const ADesc: String): Boolean;
var
  Id: Int64;
begin
  Result := False;
  FLastError := '';
  try
    Id := FLib.AddClass(AName, AParentID, AAbstract, ADesc);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  RefreshClasses(Id);
  Changed;
  Result := True;
end;

function TfrPartsEditor.ChangeClass(ClassID: Int64; const AName: String; AParentID: Int64; AAbstract: Boolean; const ADesc: String): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.UpdateClass(ClassID, AName, AParentID, AAbstract, ADesc);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  RefreshClasses(ClassID);
  Changed;
  Result := True;
end;

function TfrPartsEditor.RemoveClass(ClassID: Int64): Boolean;
var
  Par: Int64;
  i: Integer;
begin
  Result := False;
  FLastError := '';
  Par := 0;
  i := FLib.ClassIndexOfID(ClassID);
  if i >= 0 then
    Par := FLib.Classes[i].ParentID;
  try
    FLib.DeleteClass(ClassID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  RefreshClasses(Par);
  Changed;
  Result := True;
end;

function TfrPartsEditor.AddField(ClassID: Int64; const AName, AType, AUnit, AEnum: String; ARequired: Boolean; const ADesc: String): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.AddField(ClassID, AName, AType, AUnit, AEnum, ARequired, ADesc);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  RefreshClasses(ClassID);
  Changed;
  Result := True;
end;

function TfrPartsEditor.ChangeField(FieldID: Int64; const AName, AType, AUnit, AEnum: String; ARequired: Boolean; const ADesc: String): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.UpdateField(FieldID, AName, AType, AUnit, AEnum, ARequired, ADesc);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  RefreshClasses(SelectedClassID);
  Changed;
  Result := True;
end;

function TfrPartsEditor.RemoveField(FieldID: Int64): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.DeleteField(FieldID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  RefreshClasses(SelectedClassID);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.CmdAddClass  (procedure)
  Notes:
    Parts > Add Class...: the Class dialog for a new class, starting under the chosen one; a refusal is explained and the dialog opens again.
  =========================================================================== }
procedure TfrPartsEditor.CmdAddClass;
var
  Dlg: TfrmClassEdit;
begin
  if FLib = nil then
    Exit;
  Dlg := TfrmClassEdit.Create(Self);
  try
    Dlg.Setup(FLib, 0, SelectedClassID);
    while Dlg.ShowModal = mrOK do
    begin
      if AddClass(Dlg.edName.Text, Dlg.ParentID, Dlg.chAbstract.Checked, Dlg.edDescription.Text) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdClassProperties  (procedure)
  Notes:
    Parts > Class Properties...: the Class dialog for the chosen class (name, parent, abstract, description).
  =========================================================================== }
procedure TfrPartsEditor.CmdClassProperties;
var
  Dlg: TfrmClassEdit;
  Id: Int64;
begin
  Id := SelectedClassID;
  if (FLib = nil) or (Id = 0) then
    Exit;
  Dlg := TfrmClassEdit.Create(Self);
  try
    Dlg.Setup(FLib, Id, 0);
    while Dlg.ShowModal = mrOK do
    begin
      if ChangeClass(Id, Dlg.edName.Text, Dlg.ParentID, Dlg.chAbstract.Checked, Dlg.edDescription.Text) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdDeleteClass  (procedure)
  Notes:
    Parts > Delete Class: asks to confirm (naming the fields that go with it) and deletes the chosen class; the library refuses while it has subclasses,
    parts or products.
  =========================================================================== }
procedure TfrPartsEditor.CmdDeleteClass;
var
  Id: Int64;
  Msg: String;
  N, i: Integer;
  F: TFieldInfoArray;
begin
  Id := SelectedClassID;
  if (FLib = nil) or (Id = 0) then
    Exit;
  F := FLib.ClassFieldList(Id);
  N := 0;
  for i := 0 to High(F) do
    if not F[i].FromParent then
      Inc(N);
  Msg := Format(rsDeleteTheClass, [FLib.Classes[FLib.ClassIndexOfID(Id)].Name]);
  if N > 0 then
    Msg := Format(rsAndItsFieldS, [Msg, N]);
  Msg := Format(rsThisCannotBeUndone, [Msg]);
  if MessageDlg(rsDeleteClass, Msg, mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    if not RemoveClass(Id) then
      ShowError(FLastError);
end;

{ ===========================================================================
  TfrPartsEditor.CmdAddField  (procedure)
  Notes:
    Parts > Add Field...: the Field dialog for a new field of the chosen class.
  =========================================================================== }
procedure TfrPartsEditor.CmdAddField;
var
  Dlg: TfrmFieldEdit;
  Blank: TFieldInfo;
  Id: Int64;
begin
  Id := SelectedClassID;
  if (FLib = nil) or (Id = 0) then
    Exit;
  Dlg := TfrmFieldEdit.Create(Self);
  try
    Blank := Default(TFieldInfo);
    Dlg.Setup(Blank, True);
    while Dlg.ShowModal = mrOK do
    begin
      if AddField(Id, Dlg.FieldName, Dlg.FieldType, Dlg.FieldUnit, Dlg.FieldEnum, Dlg.FieldRequired, Dlg.FieldDescription) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdFieldProperties  (procedure)
  Notes:
    Parts > Field Properties...: the Field dialog for the chosen field (only a field the chosen class declares itself).
  =========================================================================== }
procedure TfrPartsEditor.CmdFieldProperties;
var
  Dlg: TfrmFieldEdit;
  F: TFieldInfo;
begin
  if (FLib = nil) or (not SelectedFieldIsOwn) then
    Exit;
  F := FFields[PtrInt(lvFields.Selected.Data)];
  Dlg := TfrmFieldEdit.Create(Self);
  try
    Dlg.Setup(F, False);
    while Dlg.ShowModal = mrOK do
    begin
      if ChangeField(F.ID, Dlg.FieldName, Dlg.FieldType, Dlg.FieldUnit, Dlg.FieldEnum, Dlg.FieldRequired, Dlg.FieldDescription) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdDeleteField  (procedure)
  Notes:
    Parts > Delete Field: asks to confirm and deletes the chosen own field; the library refuses while a part has a value for it.
  =========================================================================== }
procedure TfrPartsEditor.CmdDeleteField;
var
  F: TFieldInfo;
begin
  if (FLib = nil) or (not SelectedFieldIsOwn) then
    Exit;
  F := FFields[PtrInt(lvFields.Selected.Data)];
  if MessageDlg(rsDeleteField, Format(rsDeleteTheFieldFromThe, [F.Name, F.DeclaredBy]),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    if not RemoveField(F.ID) then
      ShowError(FLastError);
end;

procedure TfrPartsEditor.ClassAddClick(Sender: TObject);
begin
  CmdAddClass;
end;

procedure TfrPartsEditor.ClassPropsClick(Sender: TObject);
begin
  CmdClassProperties;
end;

procedure TfrPartsEditor.ClassDeleteClick(Sender: TObject);
begin
  CmdDeleteClass;
end;

procedure TfrPartsEditor.FieldAddClick(Sender: TObject);
begin
  CmdAddField;
end;

procedure TfrPartsEditor.FieldEditClick(Sender: TObject);
begin
  CmdFieldProperties;
end;

procedure TfrPartsEditor.FieldDeleteClick(Sender: TObject);
begin
  CmdDeleteField;
end;

procedure TfrPartsEditor.ClassTreeChange(Sender: TObject; Node: TTreeNode);
begin
  if FLib <> nil then
    FillFields;
end;

procedure TfrPartsEditor.ClassTreeDblClick(Sender: TObject);
begin
  CmdClassProperties;
end;

procedure TfrPartsEditor.FieldDblClick(Sender: TObject);
begin
  CmdFieldProperties;
end;

{ the fields inherited from a parent class are drawn grey (they are changed on the class that declares them) }
procedure TfrPartsEditor.FieldCustomDraw(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  if (Item <> nil) and (PtrInt(Item.Data) <= High(FFields)) and FFields[PtrInt(Item.Data)].FromParent then
    Sender.Canvas.Font.Color := clGrayText
  else
    Sender.Canvas.Font.Color := clWindowText;
  DefaultDraw := True;
end;

procedure TfrPartsEditor.FieldSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateClassButtons;
end;

{ ===========================================================================
  TfrPartsEditor.FillRatParts  (procedure)
  Parameters:
    WantID: Int64 - the part to show (0 = keep the one shown, else the part chosen on the Parts page, else the first)
  Notes:
    Fills the part box of the Requirements page with every part ("name (class)") and shows its requirements.
  =========================================================================== }
procedure TfrPartsEditor.FillRatParts(WantID: Int64);
var
  i, At: Integer;
begin
  if WantID = 0 then
    WantID := CurrentRatPartID;
  if WantID = 0 then
    WantID := SelectedPartID;
  cbRatPart.Items.BeginUpdate;
  try
    cbRatPart.Items.Clear;
    if FLib <> nil then
      for i := 0 to FLib.PartCount - 1 do
        cbRatPart.Items.AddObject(FLib.Parts[i].Name + '  (' + FLib.Parts[i].ClassName + ')', TObject(PtrInt(FLib.Parts[i].ID)));
  finally
    cbRatPart.Items.EndUpdate;
  end;
  At := -1;
  for i := 0 to cbRatPart.Items.Count - 1 do
    if PtrInt(cbRatPart.Items.Objects[i]) = WantID then
      At := i;
  if (At < 0) and (cbRatPart.Items.Count > 0) then
    At := 0;
  cbRatPart.ItemIndex := At;
  FillRatings(0);
end;

function TfrPartsEditor.CurrentRatPartID: Int64;
begin
  Result := 0;
  if cbRatPart.ItemIndex >= 0 then
    Result := PtrInt(cbRatPart.Items.Objects[cbRatPart.ItemIndex]);
end;

{ ===========================================================================
  TfrPartsEditor.FillRatings  (procedure)
  Parameters:
    SelectID: Int64 - the requirement to choose afterwards (0 = none)
  Notes:
    Shows the requirements of the part chosen in the box: what they apply to, quantity, minimum, typical, maximum, unit and condition.
  =========================================================================== }
procedure TfrPartsEditor.FillRatings(SelectID: Int64);
var
  i: Integer;
  It: TListItem;
begin
  lvRatings.Items.BeginUpdate;
  try
    lvRatings.Items.Clear;
    SetLength(FRatings, 0);
    if (FLib <> nil) and (CurrentRatPartID <> 0) then
    begin
      FRatings := FLib.Ratings(CurrentRatPartID);
      for i := 0 to High(FRatings) do
      begin
        It := lvRatings.Items.Add;
        if FRatings[i].ObjectName = '' then
          It.Caption := rsTheWholePart
        else
          It.Caption := FRatings[i].ObjectName;
        It.SubItems.Add(FRatings[i].Quantity);
        if FRatings[i].HasMin then
          It.SubItems.Add(FormatRatingNumber(FRatings[i].Min))
        else
          It.SubItems.Add('');
        if FRatings[i].HasTyp then
          It.SubItems.Add(FormatRatingNumber(FRatings[i].Typ))
        else
          It.SubItems.Add('');
        if FRatings[i].HasMax then
          It.SubItems.Add(FormatRatingNumber(FRatings[i].Max))
        else
          It.SubItems.Add('');
        It.SubItems.Add(FRatings[i].Unit_);
        It.SubItems.Add(FRatings[i].Condition);
        It.Data := Pointer(PtrInt(i));
        if FRatings[i].ID = SelectID then
          It.Selected := True;
      end;
    end;
  finally
    lvRatings.Items.EndUpdate;
  end;
  UpdateRatButtons;
end;

procedure TfrPartsEditor.UpdateRatButtons;
var
  Part, Row: Boolean;
begin
  Part := CurrentRatPartID <> 0;
  Row := SelectedRatingID <> 0;
  btnRatAdd.Enabled := Part;
  btnRatEdit.Enabled := Row;
  btnRatDelete.Enabled := Row;
  miRatAdd.Enabled := Part;
  miRatEdit.Enabled := Row;
  miRatDelete.Enabled := Row;
end;

function TfrPartsEditor.SelectedRatingID: Int64;
begin
  Result := 0;
  if (lvRatings.Selected <> nil) and (PtrInt(lvRatings.Selected.Data) <= High(FRatings)) then
    Result := FRatings[PtrInt(lvRatings.Selected.Data)].ID;
end;

function TfrPartsEditor.RatingIDOfRow(Row: Integer): Int64;
begin
  Result := 0;
  if (Row >= 0) and (Row < lvRatings.Items.Count) and (PtrInt(lvRatings.Items[Row].Data) <= High(FRatings)) then
    Result := FRatings[PtrInt(lvRatings.Items[Row].Data)].ID;
end;

function TfrPartsEditor.RatingIndexOfID(RatingID: Int64): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FRatings) do
    if FRatings[i].ID = RatingID then
      Result := i;
end;

{ ===========================================================================
  TfrPartsEditor.AddRequirement / ChangeRequirement / RemoveRequirement  (functions)
  Returns:
    Boolean - True when the library accepted the change
  Notes:
    The requirement edits without any question (see TPartsLibrary.AddRating for the rules and the parameters). The list is shown again and OnChanged fires; on a
    refusal LastError holds the reason and the file is unchanged. The part list is read again too: the part's revision and modified stamp changed.
  =========================================================================== }
function TfrPartsEditor.AddRequirement(PartID, ObjectID: Int64; const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Boolean;
var
  Id: Int64;
begin
  Result := False;
  FLastError := '';
  try
    Id := FLib.AddRating(PartID, ObjectID, AQuantity, AUnit, ACondition, HasMin, HasTyp, HasMax, AMin, ATyp, AMax);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  FillRatParts(PartID);
  FillRatings(Id);
  Changed;
  Result := True;
end;

function TfrPartsEditor.ChangeRequirement(RatingID, ObjectID: Int64; const AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Boolean;
var
  PartID: Int64;
begin
  Result := False;
  FLastError := '';
  PartID := CurrentRatPartID;
  try
    FLib.UpdateRating(RatingID, ObjectID, AQuantity, AUnit, ACondition, HasMin, HasTyp, HasMax, AMin, ATyp, AMax);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  FillRatParts(PartID);
  FillRatings(RatingID);
  Changed;
  Result := True;
end;

function TfrPartsEditor.RemoveRequirement(RatingID: Int64): Boolean;
var
  PartID: Int64;
begin
  Result := False;
  FLastError := '';
  PartID := CurrentRatPartID;
  try
    FLib.DeleteRating(RatingID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  FillRatParts(PartID);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.CmdAddRating  (procedure)
  Notes:
    Parts > Add Requirement...: the Requirement dialog for a new requirement of the part shown; a refusal is explained and the dialog opens again with the entries.
  =========================================================================== }
procedure TfrPartsEditor.CmdAddRating;
var
  Dlg: TfrmRatingEdit;
  Blank: TPartRating;
  HMin, HTyp, HMax: Boolean;
  VMin, VTyp, VMax: Double;
  PartID: Int64;
begin
  PartID := CurrentRatPartID;
  if (FLib = nil) or (PartID = 0) then
    Exit;
  Dlg := TfrmRatingEdit.Create(Self);
  try
    Blank := Default(TPartRating);
    Dlg.Setup(FLib, PartID, Blank, 0);
    while Dlg.ShowModal = mrOK do
    begin
      Dlg.Values(HMin, HTyp, HMax, VMin, VTyp, VMax);
      if AddRequirement(PartID, Dlg.ObjectID, Dlg.Quantity, '', Dlg.edCondition.Text, HMin, HTyp, HMax, VMin, VTyp, VMax) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdRatingProperties  (procedure)
  Notes:
    Parts > Requirement Properties...: the Requirement dialog for the chosen requirement.
  =========================================================================== }
procedure TfrPartsEditor.CmdRatingProperties;
var
  Dlg: TfrmRatingEdit;
  R: TPartRating;
  HMin, HTyp, HMax: Boolean;
  VMin, VTyp, VMax: Double;
  Idx: Integer;
begin
  Idx := RatingIndexOfID(SelectedRatingID);
  if (FLib = nil) or (Idx < 0) then
    Exit;
  R := FRatings[Idx];
  Dlg := TfrmRatingEdit.Create(Self);
  try
    Dlg.Setup(FLib, CurrentRatPartID, R, 0);
    while Dlg.ShowModal = mrOK do
    begin
      Dlg.Values(HMin, HTyp, HMax, VMin, VTyp, VMax);
      if ChangeRequirement(R.ID, Dlg.ObjectID, Dlg.Quantity, '', Dlg.edCondition.Text, HMin, HTyp, HMax, VMin, VTyp, VMax) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdDeleteRating  (procedure)
  Notes:
    Parts > Delete Requirement: asks to confirm and deletes the chosen requirement.
  =========================================================================== }
procedure TfrPartsEditor.CmdDeleteRating;
var
  Idx: Integer;
begin
  Idx := RatingIndexOfID(SelectedRatingID);
  if (FLib = nil) or (Idx < 0) then
    Exit;
  if MessageDlg(rsDeleteRequirement, Format(rsDeleteTheRequirementForThis, [FRatings[Idx].Quantity, FRatings[Idx].Condition]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    if not RemoveRequirement(FRatings[Idx].ID) then
      ShowError(FLastError);
end;

{ ===========================================================================
  TfrPartsEditor.FillObjParts  (procedure)
  Parameters:
    WantID: Int64 - the part to show; 0 keeps the one shown now
  Notes:
    Lists the parts in the Objects page's part box (name and class) and shows the objects of the wanted one (else the first).
  =========================================================================== }
procedure TfrPartsEditor.FillObjParts(WantID: Int64);
var
  i, At: Integer;
begin
  if WantID = 0 then
    WantID := CurrentObjPartID;
  cbObjPart.Items.BeginUpdate;
  try
    cbObjPart.Items.Clear;
    if FLib <> nil then
      for i := 0 to FLib.PartCount - 1 do
        cbObjPart.Items.AddObject(FLib.Parts[i].Name + '  (' + FLib.Parts[i].ClassName + ')', TObject(PtrInt(FLib.Parts[i].ID)));
  finally
    cbObjPart.Items.EndUpdate;
  end;
  At := -1;
  for i := 0 to cbObjPart.Items.Count - 1 do
    if PtrInt(cbObjPart.Items.Objects[i]) = WantID then
      At := i;
  if (At < 0) and (cbObjPart.Items.Count > 0) then
    At := 0;
  cbObjPart.ItemIndex := At;
  FillObjects(0);
end;

function TfrPartsEditor.CurrentObjPartID: Int64;
begin
  Result := 0;
  if cbObjPart.ItemIndex >= 0 then
    Result := PtrInt(cbObjPart.Items.Objects[cbObjPart.ItemIndex]);
end;

{ ===========================================================================
  TfrPartsEditor.FillObjects  (procedure)
  Parameters:
    SelectID: Int64 - the object to choose afterwards (0 = none)
  Notes:
    Shows the part's child objects as a tree (an object inside another hangs below it), each as "name [designator] - kind", in the part's order; all open.
  =========================================================================== }
procedure TfrPartsEditor.FillObjects(SelectID: Int64);
var
  i: Integer;
  Nodes: array of TTreeNode;
  Chosen: TTreeNode;
  procedure AddBelow(ParentObj: Int64; ParentNode: TTreeNode);
  var
    k: Integer;
    Txt: String;
  begin
    for k := 0 to High(FObjects) do
      if (Nodes[k] = nil) and (FObjects[k].ParentID = ParentObj) then
      begin
        Txt := FObjects[k].Name;
        if FObjects[k].Designator <> '' then
          Txt := Txt + ' [' + FObjects[k].Designator + ']';
        Txt := Txt + ' - ' + FObjects[k].Kind;
        Nodes[k] := tvObjects.Items.AddChild(ParentNode, Txt);
        Nodes[k].Data := Pointer(PtrInt(k));
        if FObjects[k].ID = SelectID then
          Chosen := Nodes[k];
        AddBelow(FObjects[k].ID, Nodes[k]);
      end;
  end;
begin
  Chosen := nil;
  tvObjects.Items.BeginUpdate;
  try
    tvObjects.Items.Clear;
    SetLength(FObjects, 0);
    if (FLib <> nil) and (CurrentObjPartID <> 0) then
    begin
      FObjects := FLib.PartObjects(CurrentObjPartID);
      SetLength(Nodes, Length(FObjects));
      // (the tree is built from the top: each object's children in the part's order, wherever they stand in the list)
      for i := 0 to High(FObjects) do
        Nodes[i] := nil;
      AddBelow(0, nil);
      for i := 0 to High(FObjects) do
        if (Nodes[i] = nil) and (ObjectIndexOfID(FObjects[i].ParentID) < 0) then
          AddBelow(FObjects[i].ParentID, nil);      // (an object whose parent is missing hangs at the top)
      tvObjects.FullExpand;
    end;
  finally
    tvObjects.Items.EndUpdate;
  end;
  if Chosen <> nil then
    tvObjects.Selected := Chosen;
  UpdateObjButtons;
end;

function TfrPartsEditor.ObjectIndexOfID(ObjectID: Int64): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FObjects) do
    if FObjects[i].ID = ObjectID then
      Exit(i);
end;

function TfrPartsEditor.ObjectIDOfNode(Node: TTreeNode): Int64;
begin
  Result := 0;
  if (Node <> nil) and (PtrInt(Node.Data) <= High(FObjects)) then
    Result := FObjects[PtrInt(Node.Data)].ID;
end;

function TfrPartsEditor.SelectedObjectID: Int64;
begin
  Result := 0;
  if (tvObjects.Selected <> nil) and (PtrInt(tvObjects.Selected.Data) <= High(FObjects)) then
    Result := FObjects[PtrInt(tvObjects.Selected.Data)].ID;
end;

procedure TfrPartsEditor.UpdateObjButtons;
var
  CanAdd, Row: Boolean;
begin
  CanAdd := (FLib <> nil) and (CurrentObjPartID <> 0) and (Length(FLib.ObjectKinds(CurrentObjPartID)) > 0);
  Row := SelectedObjectID <> 0;
  btnObjAdd.Enabled := CanAdd;
  btnObjEdit.Enabled := Row;
  btnObjDelete.Enabled := Row;
  miObjAdd.Enabled := CanAdd;
  miObjEdit.Enabled := Row;
  miObjDelete.Enabled := Row;
end;

{ ===========================================================================
  TfrPartsEditor.AddChildObject / ChangeChildObject / RemoveChildObject  (functions)
  Returns:
    Boolean - True when the library accepted the change
  Notes:
    The child object edits without any question (see TPartsLibrary.AddObject for the rules and the parameters). The tree is shown again and OnChanged fires; on a
    refusal LastError holds the reason and the file is unchanged. The part list is read again too: the part's revision and modified stamp changed.
  =========================================================================== }
function TfrPartsEditor.AddChildObject(PartID, ParentID, KindID: Int64; const AName, ADesignator, ADescription: String; ASort: Integer): Boolean;
var
  Id: Int64;
begin
  Result := False;
  FLastError := '';
  try
    Id := FLib.AddObject(PartID, ParentID, KindID, AName, ADesignator, ADescription, ASort);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  FillObjParts(PartID);
  FillObjects(Id);
  Changed;
  Result := True;
end;

function TfrPartsEditor.ChangeChildObject(ObjectID, ParentID, KindID: Int64; const AName, ADesignator, ADescription: String; ASort: Integer): Boolean;
var
  PartID: Int64;
begin
  Result := False;
  FLastError := '';
  PartID := CurrentObjPartID;
  try
    FLib.UpdateObject(ObjectID, ParentID, KindID, AName, ADesignator, ADescription, ASort);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  FillObjParts(PartID);
  FillObjects(ObjectID);
  Changed;
  Result := True;
end;

function TfrPartsEditor.RemoveChildObject(ObjectID: Int64): Boolean;
var
  PartID: Int64;
begin
  Result := False;
  FLastError := '';
  PartID := CurrentObjPartID;
  try
    FLib.DeleteObject(ObjectID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  FillObjParts(PartID);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.CmdAddObject  (procedure)
  Notes:
    Parts > Add Object...: the Object dialog for a new child object of the part shown, starting inside the object chosen in the tree; a refusal is explained and
    the dialog opens again with the entries.
  =========================================================================== }
procedure TfrPartsEditor.CmdAddObject;
var
  Dlg: TfrmObjectEdit;
  PartID: Int64;
begin
  PartID := CurrentObjPartID;
  if (FLib = nil) or (PartID = 0) then
    Exit;
  Dlg := TfrmObjectEdit.Create(Self);
  try
    Dlg.Setup(FLib, PartID, 0, SelectedObjectID);
    while Dlg.ShowModal = mrOK do
    begin
      if AddChildObject(PartID, Dlg.ParentID, Dlg.KindID, Dlg.edName.Text, Dlg.edDesignator.Text, Dlg.edDescription.Text, Dlg.SortValue) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdObjectProperties  (procedure)
  Notes:
    Parts > Object Properties...: the Object dialog for the chosen object.
  =========================================================================== }
procedure TfrPartsEditor.CmdObjectProperties;
var
  Dlg: TfrmObjectEdit;
  Id: Int64;
begin
  Id := SelectedObjectID;
  if (FLib = nil) or (Id = 0) then
    Exit;
  Dlg := TfrmObjectEdit.Create(Self);
  try
    Dlg.Setup(FLib, CurrentObjPartID, Id, 0);
    while Dlg.ShowModal = mrOK do
    begin
      if ChangeChildObject(Id, Dlg.ParentID, Dlg.KindID, Dlg.edName.Text, Dlg.edDesignator.Text, Dlg.edDescription.Text, Dlg.SortValue) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ===========================================================================
  TfrPartsEditor.CmdDeleteObject  (procedure)
  Notes:
    Parts > Delete Object: asks to confirm (saying how many objects inside go with it) and deletes the chosen object.
  =========================================================================== }
procedure TfrPartsEditor.CmdDeleteObject;
var
  Idx, Inner: Integer;
  Msg: String;
begin
  Idx := ObjectIndexOfID(SelectedObjectID);
  if (FLib = nil) or (Idx < 0) then
    Exit;
  Inner := FLib.ObjectSubtreeCount(FObjects[Idx].ID);
  Msg := Format(rsDeleteTheObject, [FObjects[Idx].Name]);
  if Inner > 0 then
    Msg := Format(rsTheObjectSInsideIt, [Msg, Inner]);
  Msg := Format(rsItsRequirementsAndValuesGo, [Msg]);
  if MessageDlg(rsDeleteObject, Msg, mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    if not RemoveChildObject(FObjects[Idx].ID) then
      ShowError(FLastError);
end;

{ ===========================================================================
  TfrPartsEditor.FillProdParts  (procedure)
  Parameters:
    WantID: Int64 - the part to judge the products against; 0 keeps the one shown now
  Notes:
    Lists "(no part)" and the parts in the Products page's part box, then shows the products with their verdicts for the wanted part.
  =========================================================================== }
procedure TfrPartsEditor.FillProdParts(WantID: Int64);
var
  i, At: Integer;
begin
  if WantID = 0 then
    WantID := CurrentProdPartID;
  cbProdPart.Items.BeginUpdate;
  try
    cbProdPart.Items.Clear;
    cbProdPart.Items.AddObject(rsNoPart, TObject(PtrInt(0)));
    if FLib <> nil then
      for i := 0 to FLib.PartCount - 1 do
        cbProdPart.Items.AddObject(FLib.Parts[i].Name + '  (' + FLib.Parts[i].ClassName + ')', TObject(PtrInt(FLib.Parts[i].ID)));
  finally
    cbProdPart.Items.EndUpdate;
  end;
  At := 0;
  for i := 0 to cbProdPart.Items.Count - 1 do
    if PtrInt(cbProdPart.Items.Objects[i]) = WantID then
      At := i;
  cbProdPart.ItemIndex := At;
  FillProducts(0);
end;

function TfrPartsEditor.CurrentProdPartID: Int64;
begin
  Result := 0;
  if cbProdPart.ItemIndex >= 0 then
    Result := PtrInt(cbProdPart.Items.Objects[cbProdPart.ItemIndex]);
end;

{ ===========================================================================
  TfrPartsEditor.FitText  (function)
  Parameters:
    const P: TProductRow - a product
  Returns:
    String - how the product fits the part in the part box: '' with no part, '(other class)', 'no requirements', 'fits', 'fits, oversized' or 'does not fit: 2 undersized, 1 missing'
  Notes:
    The verdict is the library's (ProductFitSummary), read when the list was filled.
  =========================================================================== }
function TfrPartsEditor.FitText(const P: TProductRow): String;
var
  i: Integer;

  procedure Add(N: Integer; const What: String);
  begin
    if N > 0 then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + IntToStr(N) + ' ' + What;
    end;
  end;
begin
  Result := '';
  if CurrentProdPartID = 0 then
    Exit;
  for i := 0 to High(FProdFit) do
    if FProdFit[i].ID = P.ID then
    begin
      if FProdFit[i].Verdict = 'fits' then
        Result := rsFits2
      else if FProdFit[i].Verdict = 'fits_oversized' then
        Result := rsFitsOversized2
      else if FProdFit[i].Verdict = 'no_requirements' then
        Result := rsNoRequirements2
      else
      begin
        Add(FProdFit[i].Undersized, rsUndersized2);
        Add(FProdFit[i].Missing, rsMissing2);
        Add(FProdFit[i].Mismatch, rsMismatch);
        Result := Format(rsDoesNotFit2, [Result]);
      end;
      Exit;
    end;
  Result := rsOtherClass;
end;

{ ===========================================================================
  TfrPartsEditor.FillProducts  (procedure)
  Parameters:
    SelectID: Int64 - the product to choose afterwards; 0 keeps the one chosen now
  Notes:
    Shows every product of the library (manufacturer, model number, series, class, status, revision, fit for the part in the part box, suggestion, description).
  =========================================================================== }
procedure TfrPartsEditor.FillProducts(SelectID: Int64);
var
  i, S: Integer;
  It, Chosen: TListItem;
  Sug: String;
begin
  Chosen := nil;
  if SelectID = 0 then
    SelectID := SelectedProductID;
  lvProducts.Items.BeginUpdate;
  try
    lvProducts.Items.Clear;
    SetLength(FProducts, 0);
    SetLength(FProdFit, 0);
    if FLib <> nil then
    begin
      FProducts := FLib.ProductRows;
      if CurrentProdPartID <> 0 then
        FProdFit := FLib.Products(CurrentProdPartID);
      for i := 0 to High(FProducts) do
      begin
        It := lvProducts.Items.Add;
        It.Caption := FProducts[i].Manufacturer;
        It.SubItems.Add(FProducts[i].MPN);
        It.SubItems.Add(FProducts[i].Series);
        It.SubItems.Add(FProducts[i].ClassName);
        It.SubItems.Add(FProducts[i].Status);
        It.SubItems.Add(FProducts[i].Revision);
        It.SubItems.Add(FitText(FProducts[i]));
        Sug := '';
        if CurrentProdPartID <> 0 then
        begin
          S := FLib.SuggestionState(CurrentProdPartID, FProducts[i].ID);
          if S = 0 then
            Sug := 'suggested'
          else if S = 1 then
            Sug := 'preferred';
        end;
        It.SubItems.Add(Sug);
        It.SubItems.Add(FProducts[i].Description);
        It.Data := Pointer(PtrInt(i));
        if FProducts[i].ID = SelectID then
          Chosen := It;
      end;
    end;
  finally
    lvProducts.Items.EndUpdate;
  end;
  if Chosen <> nil then
    lvProducts.Selected := Chosen;
  FillProdRatings(0);
end;

function TfrPartsEditor.ProductIndexOfID(ProductID: Int64): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FProducts) do
    if FProducts[i].ID = ProductID then
      Exit(i);
end;

function TfrPartsEditor.SelectedProductID: Int64;
begin
  Result := 0;
  if (lvProducts.Selected <> nil) and (PtrInt(lvProducts.Selected.Data) <= High(FProducts)) then
    Result := FProducts[PtrInt(lvProducts.Selected.Data)].ID;
end;

function TfrPartsEditor.ProductIDOfRow(Row: Integer): Int64;
begin
  Result := 0;
  if (Row >= 0) and (Row < lvProducts.Items.Count) and (PtrInt(lvProducts.Items[Row].Data) <= High(FProducts)) then
    Result := FProducts[PtrInt(lvProducts.Items[Row].Data)].ID;
end;

{ ===========================================================================
  TfrPartsEditor.FillProdRatings  (procedure)
  Parameters:
    SelectID: Int64 - the rating to choose afterwards; 0 keeps the one chosen now
  Notes:
    Shows what the chosen product is rated for (applies to, quantity, min, typ, max, unit, condition).
  =========================================================================== }
procedure TfrPartsEditor.FillProdRatings(SelectID: Int64);
var
  i: Integer;
  It, Chosen: TListItem;

  function Num(Has: Boolean; V: Double): String;
  begin
    if Has then
      Result := FormatRatingNumber(V)
    else
      Result := '';
  end;
begin
  Chosen := nil;
  if SelectID = 0 then
    SelectID := SelectedProdRatingID;
  lvProdRatings.Items.BeginUpdate;
  try
    lvProdRatings.Items.Clear;
    SetLength(FProdRatings, 0);
    if (FLib <> nil) and (SelectedProductID <> 0) then
    begin
      FProdRatings := FLib.ProductRatings(SelectedProductID);
      for i := 0 to High(FProdRatings) do
      begin
        It := lvProdRatings.Items.Add;
        if FProdRatings[i].ObjectName = '' then
          It.Caption := rsTheWholeProduct
        else
          It.Caption := FProdRatings[i].ObjectName;
        It.SubItems.Add(FProdRatings[i].Quantity);
        It.SubItems.Add(Num(FProdRatings[i].HasMin, FProdRatings[i].Min));
        It.SubItems.Add(Num(FProdRatings[i].HasTyp, FProdRatings[i].Typ));
        It.SubItems.Add(Num(FProdRatings[i].HasMax, FProdRatings[i].Max));
        It.SubItems.Add(FProdRatings[i].Unit_);
        It.SubItems.Add(FProdRatings[i].Condition);
        It.Data := Pointer(PtrInt(i));
        if FProdRatings[i].ID = SelectID then
          Chosen := It;
      end;
    end;
  finally
    lvProdRatings.Items.EndUpdate;
  end;
  if Chosen <> nil then
    lvProdRatings.Selected := Chosen;
  UpdateProdButtons;
end;

function TfrPartsEditor.ProdRatingIndexOfID(RatingID: Int64): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FProdRatings) do
    if FProdRatings[i].ID = RatingID then
      Exit(i);
end;

function TfrPartsEditor.SelectedProdRatingID: Int64;
begin
  Result := 0;
  if (lvProdRatings.Selected <> nil) and (PtrInt(lvProdRatings.Selected.Data) <= High(FProdRatings)) then
    Result := FProdRatings[PtrInt(lvProdRatings.Selected.Data)].ID;
end;

function TfrPartsEditor.ProdRatingIDOfRow(Row: Integer): Int64;
begin
  Result := 0;
  if (Row >= 0) and (Row < lvProdRatings.Items.Count) and (PtrInt(lvProdRatings.Items[Row].Data) <= High(FProdRatings)) then
    Result := FProdRatings[PtrInt(lvProdRatings.Items[Row].Data)].ID;
end;

{ ===========================================================================
  TfrPartsEditor.UpdateProdButtons  (procedure)
  Notes:
    Enables the product buttons (and the pop-up menus') that can be used now: Add with the library open, the others with a product (and a rating) chosen; the two
    suggestion buttons need a part in the part box and a product of its class; their captions say what the next click does.
  =========================================================================== }
procedure TfrPartsEditor.UpdateProdButtons;
var
  Prod, Rat, Sug: Boolean;
  Pi, S: Integer;
begin
  Prod := SelectedProductID <> 0;
  Rat := SelectedProdRatingID <> 0;
  Sug := False;
  S := -1;
  Pi := ProductIndexOfID(SelectedProductID);
  if (FLib <> nil) and Prod and (CurrentProdPartID <> 0) and (Pi >= 0) and (FLib.PartIndexOfID(CurrentProdPartID) >= 0) then
  begin
    Sug := FLib.Parts[FLib.PartIndexOfID(CurrentProdPartID)].ClassID = FProducts[Pi].ClassID;
    S := FLib.SuggestionState(CurrentProdPartID, SelectedProductID);
  end;
  btnProdAdd.Enabled := FLib <> nil;
  btnProdEdit.Enabled := Prod;
  btnProdDelete.Enabled := Prod;
  btnProdSuggest.Enabled := Sug;
  btnProdPreferred.Enabled := Sug;
  if S >= 0 then
    btnProdSuggest.Caption := rsRemoveSuggestion
  else
    btnProdSuggest.Caption := rsSuggestForPart;
  if S = 1 then
    btnProdPreferred.Caption := rsNotPreferred
  else
    btnProdPreferred.Caption := rsPreferredForPart;
  btnProdRatAdd.Enabled := Prod;
  btnProdRatEdit.Enabled := Rat;
  btnProdRatDelete.Enabled := Rat;
  miProdAdd.Enabled := FLib <> nil;
  miProdEdit.Enabled := Prod;
  miProdDelete.Enabled := Prod;
  miProdRatAdd.Enabled := Prod;
  miProdRatEdit.Enabled := Rat;
  miProdRatDelete.Enabled := Rat;
end;

{ ===========================================================================
  TfrPartsEditor.AddProductRow / ChangeProductRow / RemoveProductRow / SuggestProductFor  (functions)
  Returns:
    Boolean - True when the library accepted the change
  Notes:
    The product edits without any question (see TPartsLibrary.AddProduct, UpdateProduct, DeleteProduct, SetSuggestion). The lists are shown again and OnChanged fires;
    on a refusal LastError holds the reason and the file is unchanged.
  =========================================================================== }
function TfrPartsEditor.AddProductRow(ClassID: Int64; const AManufacturer, AMPN, ASeries, ADescription, AStatus: String): Boolean;
var
  Id: Int64;
begin
  Result := False;
  FLastError := '';
  try
    Id := FLib.AddProduct(ClassID, AManufacturer, AMPN, ASeries, ADescription, AStatus);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  FillProducts(Id);
  Changed;
  Result := True;
end;

function TfrPartsEditor.ChangeProductRow(ProductID, ClassID: Int64; const AManufacturer, AMPN, ASeries, ADescription, AStatus: String): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.UpdateProduct(ProductID, ClassID, AManufacturer, AMPN, ASeries, ADescription, AStatus);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  FillProducts(ProductID);
  Changed;
  Result := True;
end;

function TfrPartsEditor.RemoveProductRow(ProductID: Int64): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.DeleteProduct(ProductID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  Changed;
  Result := True;
end;

function TfrPartsEditor.SuggestProductFor(ProductID: Int64; State: Integer): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.SetSuggestion(CurrentProdPartID, ProductID, State);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  FillProducts(ProductID);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.AddProdRatingRow / ChangeProdRatingRow / RemoveProdRatingRow  (functions)
  Returns:
    Boolean - True when the library accepted the change
  Notes:
    The product rating edits without any question (see TPartsLibrary.AddProductRating). The product's revision changes, so the product list is shown again too.
  =========================================================================== }
function TfrPartsEditor.AddProdRatingRow(ProductID: Int64; const AAppliesTo, AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Boolean;
var
  Id: Int64;
begin
  Result := False;
  FLastError := '';
  try
    Id := FLib.AddProductRating(ProductID, AAppliesTo, AQuantity, AUnit, ACondition, HasMin, HasTyp, HasMax, AMin, ATyp, AMax);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  FillProducts(ProductID);
  FillProdRatings(Id);
  Changed;
  Result := True;
end;

function TfrPartsEditor.ChangeProdRatingRow(RatingID: Int64; const AAppliesTo, AQuantity, AUnit, ACondition: String; HasMin, HasTyp, HasMax: Boolean; AMin, ATyp, AMax: Double): Boolean;
var
  Pid: Int64;
begin
  Result := False;
  FLastError := '';
  Pid := SelectedProductID;
  try
    FLib.UpdateProductRating(RatingID, AAppliesTo, AQuantity, AUnit, ACondition, HasMin, HasTyp, HasMax, AMin, ATyp, AMax);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  FillProducts(Pid);
  FillProdRatings(RatingID);
  Changed;
  Result := True;
end;

function TfrPartsEditor.RemoveProdRatingRow(RatingID: Int64): Boolean;
var
  Pid: Int64;
begin
  Result := False;
  FLastError := '';
  Pid := SelectedProductID;
  try
    FLib.DeleteProductRating(RatingID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  FillProducts(Pid);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.CmdAddProduct / CmdProductProperties / CmdDeleteProduct  (procedures)
  Notes:
    Parts > Add Product..., Product Properties..., Delete Product: the Product dialog (a refusal is explained and the dialog opens again with the entries); delete
    asks to confirm and says what goes with the product.
  =========================================================================== }
procedure TfrPartsEditor.CmdAddProduct;
var
  Dlg: TfrmProductEdit;
  Dflt: Int64;
  Pi: Integer;
begin
  if FLib = nil then
    Exit;
  Dflt := 0;
  Pi := ProductIndexOfID(SelectedProductID);
  if Pi >= 0 then
    Dflt := FProducts[Pi].ClassID
  else if (CurrentProdPartID <> 0) and (FLib.PartIndexOfID(CurrentProdPartID) >= 0) then
    Dflt := FLib.Parts[FLib.PartIndexOfID(CurrentProdPartID)].ClassID;
  Dlg := TfrmProductEdit.Create(Self);
  try
    Dlg.Setup(FLib, 0, Dflt);
    while Dlg.ShowModal = mrOK do
    begin
      if AddProductRow(Dlg.ClassID, Dlg.edManufacturer.Text, Dlg.edMPN.Text, Dlg.edSeries.Text, Dlg.edDescription.Text, Dlg.cbStatus.Text) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrPartsEditor.CmdProductProperties;
var
  Dlg: TfrmProductEdit;
  Id: Int64;
begin
  Id := SelectedProductID;
  if (FLib = nil) or (Id = 0) then
    Exit;
  Dlg := TfrmProductEdit.Create(Self);
  try
    Dlg.Setup(FLib, Id, 0);
    while Dlg.ShowModal = mrOK do
    begin
      if ChangeProductRow(Id, Dlg.ClassID, Dlg.edManufacturer.Text, Dlg.edMPN.Text, Dlg.edSeries.Text, Dlg.edDescription.Text, Dlg.cbStatus.Text) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrPartsEditor.CmdDeleteProduct;
var
  Pi: Integer;
begin
  Pi := ProductIndexOfID(SelectedProductID);
  if (FLib = nil) or (Pi < 0) then
    Exit;
  if MessageDlg(rsDeleteProduct, Format(rsDeleteWithItsRatingsSuggestions, [FProducts[Pi].Manufacturer, FProducts[Pi].MPN]),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    if not RemoveProductRow(FProducts[Pi].ID) then
      ShowError(FLastError);
end;

{ ===========================================================================
  TfrPartsEditor.CmdSuggestProduct / CmdPreferProduct  (procedures)
  Notes:
    The chosen product is suggested for the part in the part box (or the suggestion removed); Preferred makes it the part's preferred product (or a plain suggestion again).
  =========================================================================== }
procedure TfrPartsEditor.CmdSuggestProduct;
var
  S: Integer;
begin
  if (FLib = nil) or (SelectedProductID = 0) or (CurrentProdPartID = 0) then
    Exit;
  S := FLib.SuggestionState(CurrentProdPartID, SelectedProductID);
  if S >= 0 then
    S := -1
  else
    S := 0;
  if not SuggestProductFor(SelectedProductID, S) then
    ShowError(FLastError);
end;

procedure TfrPartsEditor.CmdPreferProduct;
var
  S: Integer;
begin
  if (FLib = nil) or (SelectedProductID = 0) or (CurrentProdPartID = 0) then
    Exit;
  if FLib.SuggestionState(CurrentProdPartID, SelectedProductID) = 1 then
    S := 0
  else
    S := 1;
  if not SuggestProductFor(SelectedProductID, S) then
    ShowError(FLastError);
end;

{ ===========================================================================
  TfrPartsEditor.CmdAddProdRating / CmdProdRatingProperties / CmdDeleteProdRating  (procedures)
  Notes:
    Parts > Add Product Rating..., Product Rating Properties..., Delete Product Rating: the Rating dialog in its product form (applies to the whole product, a kind
    or an object name).
  =========================================================================== }
procedure TfrPartsEditor.CmdAddProdRating;
var
  Dlg: TfrmRatingEdit;
  HMin, HTyp, HMax: Boolean;
  VMin, VTyp, VMax: Double;
  Pid: Int64;
begin
  Pid := SelectedProductID;
  if (FLib = nil) or (Pid = 0) then
    Exit;
  Dlg := TfrmRatingEdit.Create(Self);
  try
    Dlg.SetupProduct(FLib, Pid, Default(TPartRating));
    while Dlg.ShowModal = mrOK do
    begin
      Dlg.Values(HMin, HTyp, HMax, VMin, VTyp, VMax);
      if AddProdRatingRow(Pid, Dlg.AppliesTo, Dlg.Quantity, '', Dlg.edCondition.Text, HMin, HTyp, HMax, VMin, VTyp, VMax) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrPartsEditor.CmdProdRatingProperties;
var
  Dlg: TfrmRatingEdit;
  R: TPartRating;
  HMin, HTyp, HMax: Boolean;
  VMin, VTyp, VMax: Double;
  Idx: Integer;
begin
  Idx := ProdRatingIndexOfID(SelectedProdRatingID);
  if (FLib = nil) or (Idx < 0) then
    Exit;
  R := FProdRatings[Idx];
  Dlg := TfrmRatingEdit.Create(Self);
  try
    Dlg.SetupProduct(FLib, SelectedProductID, R);
    while Dlg.ShowModal = mrOK do
    begin
      Dlg.Values(HMin, HTyp, HMax, VMin, VTyp, VMax);
      if ChangeProdRatingRow(R.ID, Dlg.AppliesTo, Dlg.Quantity, '', Dlg.edCondition.Text, HMin, HTyp, HMax, VMin, VTyp, VMax) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrPartsEditor.CmdDeleteProdRating;
var
  Idx: Integer;
begin
  Idx := ProdRatingIndexOfID(SelectedProdRatingID);
  if (FLib = nil) or (Idx < 0) then
    Exit;
  if MessageDlg(rsDeleteRating, Format(rsDeleteTheRatingForOf, [FProdRatings[Idx].Quantity, FProdRatings[Idx].Condition]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    if not RemoveProdRatingRow(FProdRatings[Idx].ID) then
      ShowError(FLastError);
end;

{ ===========================================================================
  TfrPartsEditor.FillValParts  (procedure)
  Parameters:
    WantID: Int64 - the part to show; 0 keeps the one shown now
  Notes:
    Lists the parts in the Values page's part box (name and class) and shows the field values of the wanted one (else the first).
  =========================================================================== }
procedure TfrPartsEditor.FillValParts(WantID: Int64);
var
  i, At: Integer;
begin
  if WantID = 0 then
    WantID := CurrentValPartID;
  cbValPart.Items.BeginUpdate;
  try
    cbValPart.Items.Clear;
    if FLib <> nil then
      for i := 0 to FLib.PartCount - 1 do
        cbValPart.Items.AddObject(FLib.Parts[i].Name + '  (' + FLib.Parts[i].ClassName + ')', TObject(PtrInt(FLib.Parts[i].ID)));
  finally
    cbValPart.Items.EndUpdate;
  end;
  At := -1;
  for i := 0 to cbValPart.Items.Count - 1 do
    if PtrInt(cbValPart.Items.Objects[i]) = WantID then
      At := i;
  if (At < 0) and (cbValPart.Items.Count > 0) then
    At := 0;
  cbValPart.ItemIndex := At;
  FillValues(-1);
end;

function TfrPartsEditor.CurrentValPartID: Int64;
begin
  Result := 0;
  if cbValPart.ItemIndex >= 0 then
    Result := PtrInt(cbValPart.Items.Objects[cbValPart.ItemIndex]);
end;

{ ===========================================================================
  TfrPartsEditor.FillValues  (procedure)
  Parameters:
    SelectIndex: Integer - the row to choose afterwards; -1 keeps the row chosen now (by object and field)
  Notes:
    Shows every field the part can hold a value for: the fields of its class (applies to "(the part)") and the fields of each child object's kind, with the stored value
    (empty when none; required fields without a value say so in the Required column).
  =========================================================================== }
procedure TfrPartsEditor.FillValues(SelectIndex: Integer);
var
  i, Keep: Integer;
  It, Chosen: TListItem;
  KeepObj, KeepFld: Int64;
begin
  Chosen := nil;
  KeepObj := -1;
  KeepFld := -1;
  Keep := SelectedValueRow;
  if (SelectIndex < 0) and (Keep >= 0) then
  begin
    KeepObj := FValues[Keep].ObjectID;
    KeepFld := FValues[Keep].FieldID;
  end;
  lvValues.Items.BeginUpdate;
  try
    lvValues.Items.Clear;
    SetLength(FValues, 0);
    if (FLib <> nil) and (CurrentValPartID <> 0) then
    begin
      FValues := FLib.FieldValues(CurrentValPartID);
      for i := 0 to High(FValues) do
      begin
        It := lvValues.Items.Add;
        if FValues[i].ObjectID = 0 then
          It.Caption := rsThePart
        else
          It.Caption := FValues[i].ObjectName;
        It.SubItems.Add(FValues[i].FieldName);
        It.SubItems.Add(FValues[i].FieldType);
        It.SubItems.Add(FValues[i].Unit_);
        It.SubItems.Add(FValues[i].ValueText);
        if FValues[i].Required and (not FValues[i].HasValue) then
          It.SubItems.Add(rsRequiredMissing)
        else if FValues[i].Required then
          It.SubItems.Add(rsRequired2)
        else
          It.SubItems.Add('');
        It.SubItems.Add(FValues[i].DeclaredBy);
        It.Data := Pointer(PtrInt(i));
        if (i = SelectIndex) or ((FValues[i].ObjectID = KeepObj) and (FValues[i].FieldID = KeepFld)) then
          Chosen := It;
      end;
    end;
  finally
    lvValues.Items.EndUpdate;
  end;
  if Chosen <> nil then
    lvValues.Selected := Chosen;
  UpdateValButtons;
end;

function TfrPartsEditor.SelectedValueRow: Integer;
begin
  Result := -1;
  if (lvValues.Selected <> nil) and (PtrInt(lvValues.Selected.Data) <= High(FValues)) then
    Result := PtrInt(lvValues.Selected.Data);
end;

function TfrPartsEditor.ValueRowObject(Row: Integer): Int64;
begin
  Result := 0;
  if (Row >= 0) and (Row <= High(FValues)) then
    Result := FValues[Row].ObjectID;
end;

function TfrPartsEditor.ValueRowField(Row: Integer): Int64;
begin
  Result := 0;
  if (Row >= 0) and (Row <= High(FValues)) then
    Result := FValues[Row].FieldID;
end;

function TfrPartsEditor.ValueRowAt(Row: Integer): TValueRow;
begin
  Result := Default(TValueRow);
  if (Row >= 0) and (Row <= High(FValues)) then
    Result := FValues[Row];
end;

procedure TfrPartsEditor.UpdateValButtons;
var
  Row: Integer;
begin
  Row := SelectedValueRow;
  btnValEdit.Enabled := Row >= 0;
  btnValClear.Enabled := (Row >= 0) and FValues[Row].HasValue;
  miValEdit.Enabled := btnValEdit.Enabled;
  miValClear.Enabled := btnValClear.Enabled;
end;

{ ===========================================================================
  TfrPartsEditor.SetValue  (function)
  Parameters:
    ObjectID: Int64 - 0 for a field of the part, else the child object
    FieldID: Int64 - the field
    const AValue: String - the value as typed; empty removes it
  Returns:
    Boolean - True when the library accepted it
  Notes:
    The value edit without any question (see TPartsLibrary.SetFieldValue). The list is shown again, the part list too (the part's revision changed), and OnChanged fires;
    on a refusal LastError holds the reason and the file is unchanged.
  =========================================================================== }
function TfrPartsEditor.SetValue(ObjectID, FieldID: Int64; const AValue: String): Boolean;
var
  PartID: Int64;
  i: Integer;
begin
  Result := False;
  FLastError := '';
  PartID := CurrentValPartID;
  try
    FLib.SetFieldValue(PartID, ObjectID, FieldID, AValue);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  FillValParts(PartID);
  for i := 0 to High(FValues) do
    if (FValues[i].ObjectID = ObjectID) and (FValues[i].FieldID = FieldID) then
      FillValues(i);
  Changed;
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.CmdEditValue / CmdClearValue  (procedures)
  Notes:
    Parts > Set Field Value...: the Field Value dialog for the chosen row (a refusal is explained and the dialog opens again); Clear Field Value removes the stored value.
  =========================================================================== }
procedure TfrPartsEditor.CmdEditValue;
var
  Dlg: TfrmValueEdit;
  Row: Integer;
begin
  Row := SelectedValueRow;
  if (FLib = nil) or (Row < 0) then
    Exit;
  Dlg := TfrmValueEdit.Create(Self);
  try
    Dlg.Setup(FValues[Row]);
    while Dlg.ShowModal = mrOK do
    begin
      if SetValue(FValues[Row].ObjectID, FValues[Row].FieldID, Dlg.ValueText) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrPartsEditor.CmdClearValue;
var
  Row: Integer;
begin
  Row := SelectedValueRow;
  if (FLib = nil) or (Row < 0) or (not FValues[Row].HasValue) then
    Exit;
  if not SetValue(FValues[Row].ObjectID, FValues[Row].FieldID, '') then
    ShowError(FLastError);
end;

procedure TfrPartsEditor.ValEditClick(Sender: TObject);
begin
  CmdEditValue;
end;

procedure TfrPartsEditor.ValClearClick(Sender: TObject);
begin
  CmdClearValue;
end;

procedure TfrPartsEditor.ValSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateValButtons;
end;

procedure TfrPartsEditor.ValPartChange(Sender: TObject);
begin
  FillValues(-1);
end;

{ ===========================================================================
  TfrPartsEditor.FillSymParts  (procedure)
  Parameters:
    WantID: Int64 - the part to show; 0 keeps the one shown now
  Notes:
    Lists the parts in the Symbols page's part box and shows the symbols of the wanted one (else the first).
  =========================================================================== }
procedure TfrPartsEditor.FillSymParts(WantID: Int64);
var
  i, At: Integer;
begin
  if WantID = 0 then
    WantID := CurrentSymPartID;
  cbSymPart.Items.BeginUpdate;
  try
    cbSymPart.Items.Clear;
    if FLib <> nil then
      for i := 0 to FLib.PartCount - 1 do
        cbSymPart.Items.AddObject(FLib.Parts[i].Name + '  (' + FLib.Parts[i].ClassName + ')', TObject(PtrInt(FLib.Parts[i].ID)));
  finally
    cbSymPart.Items.EndUpdate;
  end;
  At := -1;
  for i := 0 to cbSymPart.Items.Count - 1 do
    if PtrInt(cbSymPart.Items.Objects[i]) = WantID then
      At := i;
  if (At < 0) and (cbSymPart.Items.Count > 0) then
    At := 0;
  cbSymPart.ItemIndex := At;
  FillSymbols(0);
end;

function TfrPartsEditor.CurrentSymPartID: Int64;
begin
  Result := 0;
  if cbSymPart.ItemIndex >= 0 then
    Result := PtrInt(cbSymPart.Items.Objects[cbSymPart.ItemIndex]);
end;

{ ===========================================================================
  TfrPartsEditor.FillSymbols  (procedure)
  Parameters:
    WantID: Int64 - the symbol to choose afterwards; 0 keeps the one chosen now
  =========================================================================== }
procedure TfrPartsEditor.FillSymbols(WantID: Int64);
var
  i: Integer;
  It, Chosen: TListItem;
begin
  Chosen := nil;
  if WantID = 0 then
    WantID := SelectedSymbolID;
  lvSymbols.Items.BeginUpdate;
  try
    lvSymbols.Items.Clear;
    SetLength(FSymbols, 0);
    if (FLib <> nil) and (CurrentSymPartID <> 0) then
    begin
      FSymbols := FLib.SymbolRows(CurrentSymPartID);
      for i := 0 to High(FSymbols) do
      begin
        It := lvSymbols.Items.Add;
        It.Caption := FSymbols[i].Name;
        It.SubItems.Add(FSymbols[i].Standard);
        It.SubItems.Add(FSymbols[i].Purpose);
        if FSymbols[i].IsDefault then
          It.SubItems.Add(rsDefault)
        else
          It.SubItems.Add('');
        It.SubItems.Add(IntToStr(FSymbols[i].Bytes));
        It.SubItems.Add(FSymbols[i].ShowsName);
        It.Data := Pointer(PtrInt(i));
        if FSymbols[i].ID = WantID then
          Chosen := It;
      end;
    end;
  finally
    lvSymbols.Items.EndUpdate;
  end;
  if Chosen <> nil then
    lvSymbols.Selected := Chosen;
  UpdateSymButtons;
end;

function TfrPartsEditor.SelectedSymbolRow: Integer;
begin
  Result := -1;
  if (lvSymbols.Selected <> nil) and (PtrInt(lvSymbols.Selected.Data) <= High(FSymbols)) then
    Result := PtrInt(lvSymbols.Selected.Data);
end;

function TfrPartsEditor.SymbolIDOfRow(Row: Integer): Int64;
begin
  Result := 0;
  if (Row >= 0) and (Row <= High(FSymbols)) then
    Result := FSymbols[Row].ID;
end;

function TfrPartsEditor.SelectedSymbolID: Int64;
begin
  Result := SymbolIDOfRow(SelectedSymbolRow);
end;

function TfrPartsEditor.SymbolRowAt(Row: Integer): TSymbolRow;
begin
  Result := Default(TSymbolRow);
  if (Row >= 0) and (Row <= High(FSymbols)) then
    Result := FSymbols[Row];
end;

procedure TfrPartsEditor.UpdateSymButtons;
var
  Row: Integer;
  HasPart: Boolean;
begin
  Row := SelectedSymbolRow;
  HasPart := CurrentSymPartID <> 0;
  btnSymNew.Enabled := HasPart and Assigned(FOnEditSymbol);
  btnSymImport.Enabled := HasPart and Assigned(FOnImportSymbol);
  btnSymEdit.Enabled := (Row >= 0) and Assigned(FOnEditSymbol);
  btnSymProps.Enabled := Row >= 0;
  btnSymDefault.Enabled := (Row >= 0) and (FSymbols[Row].Purpose = 'schematic') and (not FSymbols[Row].IsDefault);
  btnSymDelete.Enabled := Row >= 0;
end;

{ ===========================================================================
  TfrPartsEditor.AddSymbolDrawing / StoreSymbolDrawing / ChangeSymbolInfo / MakeDefaultSymbol / RemoveSymbol  (functions)
  Returns:
    Boolean - True when the library accepted the change
  Notes:
    The symbol edits without any question (see TPartsLibrary.AddSymbol, UpdateSymbolDrawing, UpdateSymbolInfo, SetDefaultSymbol, DeleteSymbol). The lists are shown again
    (the part list too, the revision changed) and OnChanged fires; on a refusal LastError holds the reason and the file is unchanged.
  =========================================================================== }
function TfrPartsEditor.AddSymbolDrawing(PartID: Int64; const AStandard, APurpose, AName, ABlob: String; out NewID: Int64): Boolean;
begin
  Result := False;
  NewID := 0;
  FLastError := '';
  try
    NewID := FLib.AddSymbol(PartID, AStandard, APurpose, AName, ABlob);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  ReloadAfterSymbolStore(PartID);
  FillSymbols(NewID);
  Result := True;
end;

function TfrPartsEditor.StoreSymbolDrawing(SymbolID: Int64; const ABlob: String): Boolean;
var
  PartID: Int64;
begin
  Result := False;
  FLastError := '';
  PartID := FLib.SymbolPartID(SymbolID);
  try
    FLib.UpdateSymbolDrawing(SymbolID, ABlob);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  ReloadAfterSymbolStore(PartID);
  FillSymbols(SymbolID);
  Result := True;
end;

function TfrPartsEditor.ChangeSymbolInfo(SymbolID: Int64; const AStandard, APurpose, AName: String): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.UpdateSymbolInfo(SymbolID, AStandard, APurpose, AName);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  ReloadAfterSymbolStore(CurrentSymPartID);
  FillSymbols(SymbolID);
  Result := True;
end;

function TfrPartsEditor.ChangeSymbolShows(SymbolID, ObjectID: Int64): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.SetSymbolShows(SymbolID, ObjectID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  ReloadAfterSymbolStore(CurrentSymPartID);
  FillSymbols(SymbolID);
  Result := True;
end;

function TfrPartsEditor.MakeDefaultSymbol(SymbolID: Int64): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.SetDefaultSymbol(CurrentSymPartID, SymbolID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  ReloadAfterSymbolStore(CurrentSymPartID);
  FillSymbols(SymbolID);
  Result := True;
end;

function TfrPartsEditor.RemoveSymbol(SymbolID: Int64): Boolean;
begin
  Result := False;
  FLastError := '';
  try
    FLib.DeleteSymbol(SymbolID);
  except
    on E: EPartsError do
    begin
      FLastError := E.Message;
      Exit;
    end;
  end;
  ReloadAfterSymbolStore(CurrentSymPartID);
  FillSymbols(0);
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.ReloadAfterSymbolStore  (procedure)
  Parameters:
    PartID: Int64 - the part whose symbols changed
  Notes:
    Shows the part list, every part box and the symbol list again (the part's revision changed) and tells the owner. Used by the edits above and by the symbol editor
    document when it stores a symbol into the file.
  =========================================================================== }
procedure TfrPartsEditor.ReloadAfterSymbolStore(PartID: Int64);
var
  Keep: Int64;
begin
  Keep := SelectedSymbolID;
  if PartID <> 0 then
    RegenerateGlyphs(FLib, PartID);      // (the part's default symbol may be another one now)
  Refresh(SelectedPartID);
  if PartID <> 0 then
    FillSymParts(PartID)
  else
    FillSymParts(0);
  FillSymbols(Keep);
  Changed;
end;

{ ===========================================================================
  TfrPartsEditor.CmdSymNew / CmdSymEdit / CmdSymImport  (procedures)
  Notes:
    Parts > New Part Symbol / Edit Part Symbol / Import Symbol from Library Panel: handed to the main form (OnEditSymbol with symbol 0 is "draw a new one"; OnImportSymbol
    takes the symbol chosen in the library panel).
  =========================================================================== }
procedure TfrPartsEditor.CmdSymNew;
begin
  if (CurrentSymPartID <> 0) and Assigned(FOnEditSymbol) then
    FOnEditSymbol(Self, CurrentSymPartID, 0);
end;

procedure TfrPartsEditor.CmdSymEdit;
begin
  if (SelectedSymbolID <> 0) and Assigned(FOnEditSymbol) then
    FOnEditSymbol(Self, CurrentSymPartID, SelectedSymbolID);
end;

procedure TfrPartsEditor.CmdSymImport;
begin
  if (CurrentSymPartID <> 0) and Assigned(FOnImportSymbol) then
    FOnImportSymbol(Self, CurrentSymPartID, 0);
end;

{ ===========================================================================
  TfrPartsEditor.CmdSymProps / CmdSymDefault / CmdSymDelete  (procedures)
  Notes:
    Parts > Part Symbol Properties..., Make Default Symbol, Delete Part Symbol. A refusal of the properties is explained and the dialog opens again; deleting asks first.
  =========================================================================== }
procedure TfrPartsEditor.CmdSymProps;
var
  Dlg: TfrmSymbolInfo;
  Row: Integer;
begin
  Row := SelectedSymbolRow;
  if (FLib = nil) or (Row < 0) then
    Exit;
  Dlg := TfrmSymbolInfo.Create(Self);
  try
    Dlg.Setup(FSymbols[Row].Standard, FSymbols[Row].Purpose, FSymbols[Row].Name, FLib.FunctionObjects(CurrentSymPartID), FSymbols[Row].ShowsID);
    while Dlg.ShowModal = mrOK do
    begin
      if ChangeSymbolInfo(FSymbols[Row].ID, Dlg.Standard, Dlg.Purpose, Dlg.SymName) and ChangeSymbolShows(FSymbols[Row].ID, Dlg.ShowsID) then
        Break;
      ShowError(FLastError);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrPartsEditor.CmdSymDefault;
var
  ID: Int64;
begin
  ID := SelectedSymbolID;
  if (FLib <> nil) and (ID <> 0) and (not MakeDefaultSymbol(ID)) then
    ShowError(FLastError);
end;

procedure TfrPartsEditor.CmdSymDelete;
var
  Row: Integer;
begin
  Row := SelectedSymbolRow;
  if (FLib = nil) or (Row < 0) then
    Exit;
  if MessageDlg(rsDeleteSymbol, Format(rsDeleteTheSymbolWithIts, [FSymbols[Row].Name]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    if not RemoveSymbol(FSymbols[Row].ID) then
      ShowError(FLastError);
end;

procedure TfrPartsEditor.SymPartChange(Sender: TObject);
begin
  FillSymbols(0);
end;

procedure TfrPartsEditor.SymSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateSymButtons;
end;

procedure TfrPartsEditor.SymNewClick(Sender: TObject);
begin
  CmdSymNew;
end;

procedure TfrPartsEditor.SymEditClick(Sender: TObject);
begin
  CmdSymEdit;
end;

procedure TfrPartsEditor.SymImportClick(Sender: TObject);
begin
  CmdSymImport;
end;

procedure TfrPartsEditor.SymPropsClick(Sender: TObject);
begin
  CmdSymProps;
end;

procedure TfrPartsEditor.SymDefaultClick(Sender: TObject);
begin
  CmdSymDefault;
end;

procedure TfrPartsEditor.SymDeleteClick(Sender: TObject);
begin
  CmdSymDelete;
end;

{ ===========================================================================
  TfrPartsEditor.ImportProductsFile  (function)
  Parameters:
    const AFile: String - a CSV file (see TPartsLibrary.ImportProductsCsv for the columns)
    out Msg: String - the summary, or why nothing was imported
  Returns:
    Boolean - True when the file was imported; on False the parts file is unchanged
  Notes:
    The lists are shown again and OnChanged fires after an import.
  =========================================================================== }
function TfrPartsEditor.ImportProductsFile(const AFile: String; out Msg: String): Boolean;
var
  Csv: String;
  R: TProductImportResult;
  FS: TFileStream;
begin
  Result := False;
  Msg := '';
  try
    FS := TFileStream.Create(AFile, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Csv, FS.Size);
      if FS.Size > 0 then
        FS.ReadBuffer(Csv[1], FS.Size);
    finally
      FS.Free;
    end;
  except
    on E: Exception do
    begin
      Msg := Format(rsTheFileCannotBeRead, [E.Message]);
      Exit;
    end;
  end;
  try
    R := FLib.ImportProductsCsv(Csv);
  except
    on E: EPartsError do
    begin
      Msg := E.Message;
      FLastError := Msg;
      Exit;
    end;
  end;
  Refresh(SelectedPartID);
  Changed;
  Msg := Format(rsProductsAddedChangedRatingsAdded, [R.ProductsAdded, R.ProductsUpdated, R.RatingsAdded, R.RatingsUpdated, R.Suggestions]);
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.ExportProductsFile  (function)
  Parameters:
    const AFile: String - the CSV file to write (UTF-8)
    out Msg: String - the summary, or why it could not be written
  Returns:
    Boolean - True when written
  =========================================================================== }
function TfrPartsEditor.ExportProductsFile(const AFile: String; out Msg: String): Boolean;
var
  Csv: String;
  FS: TFileStream;
begin
  Result := False;
  Msg := '';
  try
    Csv := FLib.ExportProductsCsv;
    FS := TFileStream.Create(AFile, fmCreate);
    try
      if Length(Csv) > 0 then
        FS.WriteBuffer(Csv[1], Length(Csv));
    finally
      FS.Free;
    end;
  except
    on E: Exception do
    begin
      Msg := Format(rsTheFileCannotBeWritten, [E.Message]);
      Exit;
    end;
  end;
  Msg := Format(rsProductsWritten, [Length(FLib.ProductRows)]);
  Result := True;
end;

{ ===========================================================================
  TfrPartsEditor.CmdImportProducts / CmdExportProducts  (procedures)
  Notes:
    Parts > Import Products from CSV...: asks for the file and imports it (all or nothing), then says what was done or why not. Export Products to CSV...: writes every product,
    its ratings and suggestions in the same layout.
  =========================================================================== }
procedure TfrPartsEditor.CmdImportProducts;
var
  Dlg: TOpenDialog;
  Msg: String;
begin
  if FLib = nil then
    Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := rsImportProductsFromCSV;
    Dlg.Filter := rsCSVFilesCsvCsvAll;
    if Dlg.Execute then
    begin
      if ImportProductsFile(Dlg.FileName, Msg) then
        MessageDlg(rsPartsLibrary, Msg, mtInformation, [mbOK], 0)
      else
        ShowError(Msg);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrPartsEditor.CmdExportProducts;
var
  Dlg: TSaveDialog;
  Msg: String;
begin
  if FLib = nil then
    Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := rsExportProductsToCSV;
    Dlg.Filter := rsCSVFilesCsvCsvAll;
    Dlg.DefaultExt := 'csv';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if Dlg.Execute then
    begin
      if ExportProductsFile(Dlg.FileName, Msg) then
        MessageDlg(rsPartsLibrary, Msg, mtInformation, [mbOK], 0)
      else
        ShowError(Msg);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TfrPartsEditor.ProdAddClick(Sender: TObject);
begin
  CmdAddProduct;
end;

procedure TfrPartsEditor.ProdEditClick(Sender: TObject);
begin
  CmdProductProperties;
end;

procedure TfrPartsEditor.ProdDeleteClick(Sender: TObject);
begin
  CmdDeleteProduct;
end;

procedure TfrPartsEditor.ProdSuggestClick(Sender: TObject);
begin
  CmdSuggestProduct;
end;

procedure TfrPartsEditor.ProdPreferredClick(Sender: TObject);
begin
  CmdPreferProduct;
end;

procedure TfrPartsEditor.ProdSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected then
    FillProdRatings(0);
  UpdateProdButtons;
end;

procedure TfrPartsEditor.ProdPartChange(Sender: TObject);
begin
  FillProducts(0);
end;

procedure TfrPartsEditor.ProdRatAddClick(Sender: TObject);
begin
  CmdAddProdRating;
end;

procedure TfrPartsEditor.ProdRatEditClick(Sender: TObject);
begin
  CmdProdRatingProperties;
end;

procedure TfrPartsEditor.ProdRatDeleteClick(Sender: TObject);
begin
  CmdDeleteProdRating;
end;

procedure TfrPartsEditor.ProdRatSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateProdButtons;
end;

procedure TfrPartsEditor.ObjAddClick(Sender: TObject);
begin
  CmdAddObject;
end;

procedure TfrPartsEditor.ObjEditClick(Sender: TObject);
begin
  CmdObjectProperties;
end;

procedure TfrPartsEditor.ObjDeleteClick(Sender: TObject);
begin
  CmdDeleteObject;
end;

procedure TfrPartsEditor.ObjDblClick(Sender: TObject);
begin
  CmdObjectProperties;
end;

procedure TfrPartsEditor.ObjChange(Sender: TObject; Node: TTreeNode);
begin
  UpdateObjButtons;
end;

procedure TfrPartsEditor.ObjPartChange(Sender: TObject);
begin
  FillObjects(0);
end;

procedure TfrPartsEditor.RatAddClick(Sender: TObject);
begin
  CmdAddRating;
end;

procedure TfrPartsEditor.RatEditClick(Sender: TObject);
begin
  CmdRatingProperties;
end;

procedure TfrPartsEditor.RatDeleteClick(Sender: TObject);
begin
  CmdDeleteRating;
end;

procedure TfrPartsEditor.RatDblClick(Sender: TObject);
begin
  CmdRatingProperties;
end;

procedure TfrPartsEditor.RatSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateRatButtons;
end;

procedure TfrPartsEditor.RatPartChange(Sender: TObject);
begin
  FillRatings(0);
end;

procedure TfrPartsEditor.AddClick(Sender: TObject);
begin
  CmdAdd;
end;

procedure TfrPartsEditor.EditClick(Sender: TObject);
begin
  CmdProperties;
end;

procedure TfrPartsEditor.DuplicateClick(Sender: TObject);
begin
  CmdDuplicate;
end;

procedure TfrPartsEditor.DeleteClick(Sender: TObject);
begin
  CmdDelete;
end;

procedure TfrPartsEditor.LibApplyClick(Sender: TObject);
begin
  if (FLib <> nil) and (not ApplyLibraryInfo(edLibName.Text, edLibDesc.Text, edLibAuthor.Text)) then
    ShowError(FLastError);
end;

procedure TfrPartsEditor.PartsDblClick(Sender: TObject);
begin
  CmdProperties;
end;

procedure TfrPartsEditor.PartsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
  if Selected and (FLib <> nil) then
  begin
    FillObjParts(SelectedPartID);
    FillRatParts(SelectedPartID);
    FillProdParts(SelectedPartID);
    FillValParts(SelectedPartID);
  end;
end;

end.
