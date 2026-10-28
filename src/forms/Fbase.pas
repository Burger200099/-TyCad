// SPDX-License-Identifier: LGPL-2.1-or-later
unit Fbase;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, LCLType, ExtCtrls, StdCtrls;

type

  frmControlButtons = (fcbOk, fcbCancel, fcbApply);
  TfrmControlButtons = set of frmControlButtons;

  TCustomCallback = procedure (Sender: TObject) of Object;

  { TfrmBase }

  TfrmBase = class(TForm)
    btnOK: TButton;
    btnCancel: TButton;
    btnApply: TButton;
    pnlButtons: TPanel;
    procedure btnApplyClick(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FDefaultButton: frmControlButtons;
    FCustomButton: TButton;
    FCustomCallback: TCustomCallback;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure SetButtons(Buttons: TfrmControlButtons);
    procedure SetDefaultBtn(FDefBtn: frmControlButtons);
  public
    ApplyCallback: procedure;  // assigned to a callback function.
    property SetDefaultButton: frmControlButtons read FDefaultButton write SetDefaultBtn;
    property CustomButton: TButton read FCustomButton;   // the button AddCustomButton made (nil before)
    procedure AddCustomButton(ACaption: string; AResult :TModalResult; Callback: TCustomCallback = nil);
  end;

var
  frmBase: TfrmBase;

implementation

{$R *.lfm}

{ ===========================================================================
  TfrmBase.btnApplyClick  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TfrmBase
  =========================================================================== }
procedure TfrmBase.btnApplyClick(Sender: TObject);
begin
  if Assigned(ApplyCallback) then
    ApplyCallback;
end;

{ ===========================================================================
  TfrmBase.FormActivate  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    OnActivate handler: shows the OK and Cancel buttons by default; forms that inherit from this
    one change that by calling SetButtons themselves.
  =========================================================================== }
procedure TfrmBase.FormActivate(Sender: TObject);
begin
  SetButtons([fcbOK, fcbCancel]);   // default ok & cancel, let it be changed elsewhere
end;

{ ===========================================================================
  TfrmBase.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    OnCreate handler of the base dialog; nothing to do here, inheriting forms add their own set-
    up.
  =========================================================================== }
procedure TfrmBase.FormCreate(Sender: TObject);
begin

end;

{ ===========================================================================
  TfrmBase.KeyDown  (procedure)
  Parameters:
    var Key: Word
    Shift: TShiftState
  Notes:
    Esc presses the Cancel button (when it is shown and enabled), whichever control has the focus (KeyPreview is on).
  =========================================================================== }
procedure TfrmBase.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if (Key = VK_ESCAPE) and (Shift = []) and btnCancel.Visible and btnCancel.Enabled then
  begin
    Key := 0;
    btnCancel.Click;
  end;
end;

{ ===========================================================================
  TfrmBase.SetButtons  (procedure)
  Parameters:
    Buttons: TfrmControlButtons - the set of buttons to show
  Notes:
    Shows only the chosen buttons (OK, Cancel, Apply) at the bottom of the dialog and slides the
    visible ones to the right so no gap is left.
  =========================================================================== }
procedure TfrmBase.SetButtons(Buttons: TfrmControlButtons);
var i: integer;
begin
  btnOK.Visible := fcbOK in Buttons;
  btnApply.Visible := fcbApply in Buttons;
  btnCancel.Visible := fcbCancel in Buttons;
  if Assigned(FCustomButton) then
    FCustomButton.Visible := true;  // why assign it then hide it?  may be a use for this in the future
  pnlButtons.Height := Scale96toForm(58);
{  btnCancel.Width := Scale96toForm(82);
  btnOK.Width := btnCancel.Width;
  btnApply.Width := btnOk.Width; }
  i := Scale96toForm(128);
  btnCancel.Left := Width - i; //Scale96toForm(128);
  btnOk.Left := btnCancel.Left - i; //Scale96toForm(128);
  btnApply.Left := btnOk.Left - i;
  if Assigned(FCustomButton) then
    FCustomButton.Left := btnApply.Left - i;
  i := Scale96toForm(30);
  btnCancel.Height := i;
  btnOk.Height := i;
  btnApply.Height := i;
  if Assigned(FCustomButton) then
    FCustomButton.Height := i;
  btnCancel.Top := {round}((pnlButtons.Height div 2) - (btnCancel.Height div 2)) - 1;
  btnOk.Top := btnCancel.Top;
  btnApply.Top := btnOk.Top;
  if Assigned(FCustomButton) then
    FCustomButton.Top := btnApply.Top;
  if not btnCancel.Visible then
    begin
      if Assigned(FCustomButton) then
        FCustomButton.Left := btnApply.Left;
      btnApply.Left := btnOK.Left;
      btnOK.Left := btnCancel.Left;
    end;
  if not btnOK.Visible then
    if not btnOK.Visible then
      begin
        if Assigned(FCustomButton) then
          FCustomButton.Left := btnApply.Left;
        btnApply.Left := btnOK.Left;
      end;
  if not btnApply.Visible then
    begin
      if Assigned(FCustomButton) then
        FCustomButton.Left := btnApply.Left;
    end;
end;

{ ===========================================================================
  TfrmBase.SetDefaultBtn  (procedure)
  Parameters:
    FDefBtn: frmControlButtons
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfrmBase.SetDefaultBtn(FDefBtn: frmControlButtons);
begin
  FDefaultButton := FDefBtn;
  if fDefBtn = fcbOK then
    btnOK.Default := true
  else if fDefBtn = fcbApply then
    btnApply.Default := true
  else if fDefBtn = fcbCancel then
    btnCancel.Default := true
  else
    btnOK.Default := true;
end;

{ ===========================================================================
  TfrmBase.AddCustomButton  (procedure)
  Parameters:
    ACaption: string - caption text
    AResult: TModalResult
    Callback: TCustomCallback
  Notes:
    Must call this procedure before SetButtons.
  =========================================================================== }
procedure TfrmBase.AddCustomButton(ACaption: string; AResult: TModalResult;
  Callback: TCustomCallback);
begin
  FCustomButton := TButton.Create(Self);
  FCustomButton.Parent := pnlButtons;
  FCustomButton.Color := btnApply.Color;
  FCustomButton.ParentDoubleBuffered := true;
  FCustomButton.Enabled := true;
  FCustomButton.ParentFont := true;
  FCustomButton.TabStop := true;
  FCustomButton.TabOrder := btnApply.TabOrder + 1;
  FCustomButton.Height := btnApply.Height;
  FCustomButton.Width := btnApply.Width;
//  FCustomButton.Assign(btnApply);
  if Assigned(Callback) then
    FCustomButton.OnClick := Callback;
  FCustomButton.ModalResult := AResult;
  FCustomButton.Caption := ACaption;;
//  SetButtons;
end;

end.

