unit Finput;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Fbase;

type

  { TfrmNumInput }

  TfrmNumInput = class(TfrmBase)
    edInput: TEdit;
    lbInputText: TLabel;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    function ValidInput: Boolean;
    function ErrorText: String;
  public
    FInput: string;
  private
    FRangeLow, FRangeHigh: double;

  public
    constructor Create(AOwner: TComponent; Buttons: TfrmControlButtons; RangeLow, RangeHigh: double; InputText: string); virtual;
    destructor Destroy; override;
  end;

var
  frmNumInput: TfrmNumInput;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmNumInput.FormCloseQuery  (procedure)
  Parameters:
    Sender: TObject - the form
    var CanClose: Boolean - set False to keep the dialog open
  Notes:
    Event handler: Cancel always closes. OK closes only if the entry is a number in range;
    otherwise a message names the range and the dialog stays open.
  =========================================================================== }
procedure TfrmNumInput.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if ModalResult = mrCancel then
  begin
    FInput := edInput.Text;
    CanClose := True;
  end
  else if ValidInput then
    CanClose := True
  else
  begin
    MessageDlg(rsInput, ErrorText, mtInformation, [mbOK], 0);
    CanClose := False;
  end;
end;

{ ===========================================================================
  TfrmNumInput.ValidInput  (function)
  Parameters:  none
  Returns:
    Boolean - True if the entry is acceptable
  Notes:
    Checks what was typed: a number (a comma is accepted as the decimal point) within the range
    given to the dialog, ends included. When it is valid the text is kept in FInput with a
    decimal point, so StrToFloat with a point reads it whatever the system language.
  =========================================================================== }
function TfrmNumInput.ValidInput: Boolean;
var
  V: Double;
  Fs: TFormatSettings;
  S: String;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  { a comma is accepted as the decimal point; the text is kept with a point so StrToFloat(FInput, a point) reads it }
  S := StringReplace(Trim(edInput.Text), ',', '.', [rfReplaceAll]);
  Result := TryStrToFloat(S, V, Fs) and (V >= FRangeLow) and (V <= FRangeHigh);
  if Result then
    FInput := S;
end;

{ ===========================================================================
  TfrmNumInput.ErrorText  (function)
  Parameters:  none
  Returns:
    String - the message
  Notes:
    The message for an entry that is not acceptable, naming the range that is allowed.
  =========================================================================== }
function TfrmNumInput.ErrorText: String;
var
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Result := Format(rsPleaseEnterANumberBetween, [FloatToStr(FRangeLow, Fs), FloatToStr(FRangeHigh, Fs)]);
end;

{ ===========================================================================
  TfrmNumInput.Create  (constructor)
  Parameters:
    AOwner: TComponent - owner of the dialog
    Buttons: TfrmControlButtons - the buttons to show
    RangeLow: double - lowest number allowed
    RangeHigh: double - highest number allowed
    InputText: string - the prompt
  Notes:
    Creates the number input dialog: which of OK, Cancel and Apply to show, the range a number
    must lie in, and the prompt above the entry.
  =========================================================================== }
constructor TfrmNumInput.Create(AOwner: TComponent;
  Buttons: TfrmControlButtons; RangeLow, RangeHigh: double; InputText: string);
begin
  inherited Create(AOwner);
  SetButtons(Buttons);
  FRangeLow := RangeLow;
  FRangeHigh := RangeHigh;
  lbInputText.Caption := InputText;
end;

{ ===========================================================================
  TfrmNumInput.Destroy  (destructor)
  Parameters:  none
  Notes:
    Frees the dialog.
  =========================================================================== }
destructor TfrmNumInput.Destroy;
begin
  inherited Destroy;
end;

end.

