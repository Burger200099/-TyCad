{ The Check Design Rules dialog (TinyCAD's CDlgERCBox): eleven check boxes in two groups, the "design errors" (duplicated references, unconnected
  items, more than one item on a no-connect net, unassigned reference designators) and the "design warnings" (power connected to power, power
  connected to an output, output connected to an output, no output driving input(s), unconnected nets, multiple net names on the same net and
  non-case distinct net names). OK is called Check. The choices are kept between runs as the registry WORD "ERC" that TinyCAD uses (all on to begin
  with). The dialog only holds the values; the main form runs the check.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit Fercopts;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Fbase, UErc, USettings, consts;

type

  { TfrmErcOptions }

  TfrmErcOptions = class(TfrmBase)
    cbDupRef: TCheckBox;
    cbNoConnect: TCheckBox;
    cbNonCase: TCheckBox;
    cbNoOutput: TCheckBox;
    cbMultiple: TCheckBox;
    cbOutput: TCheckBox;
    cbOutputPwr: TCheckBox;
    cbPower: TCheckBox;
    cbUnassigned: TCheckBox;
    cbUnConnect: TCheckBox;
    cbUnConnected: TCheckBox;
    gbErrors: TGroupBox;
    gbWarnings: TGroupBox;
    procedure FormCreate(Sender: TObject);
  private
    procedure ErcActivate(Sender: TObject);
  public
    { start with the choices kept in the program settings }
    procedure LoadFromSettings;
    { remember the dialog's choices in the program settings (done when Check is pressed) }
    procedure KeepInSettings;
    function Options: TErcOptions;
    procedure SetOptions(const O: TErcOptions);
  end;

var
  frmErcOptions: TfrmErcOptions;

implementation


uses UStrings;

{$R *.lfm}

{ ===========================================================================
  TfrmErcOptions.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Makes the OK button say Check.
  =========================================================================== }
procedure TfrmErcOptions.FormCreate(Sender: TObject);
begin
  OnActivate := @ErcActivate;
  btnOK.Caption := rsCheck;
end;

{ ===========================================================================
  TfrmErcOptions.ErcActivate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    Shows the Check and Cancel buttons.
  =========================================================================== }
procedure TfrmErcOptions.ErcActivate(Sender: TObject);
begin
  SetButtons([fcbOK, fcbCancel]);
  btnOK.Caption := rsCheck;
end;

{ ===========================================================================
  TfrmErcOptions.SetOptions  (procedure)
  Parameters:
    const O: TErcOptions - the checks to show as on
  Notes:
    CDlgERCBox::OnInitDialog: copies the choices into the check boxes.
  =========================================================================== }
procedure TfrmErcOptions.SetOptions(const O: TErcOptions);
begin
  cbDupRef.Checked := O.DupRef;
  cbUnConnect.Checked := O.UnConnect;
  cbNoConnect.Checked := O.NoConnect;
  cbPower.Checked := O.Power;
  cbOutputPwr.Checked := O.OutputPwr;
  cbOutput.Checked := O.Output;
  cbNoOutput.Checked := O.NoOutput;
  cbUnConnected.Checked := O.UnConnected;
  cbMultiple.Checked := O.MultipleNetNames;
  cbNonCase.Checked := O.NonCaseDistinctNetNames;
  cbUnassigned.Checked := O.UnAssignedRefDes;
end;

{ ===========================================================================
  TfrmErcOptions.Options  (function)
  Parameters:  none
  Returns:
    TErcOptions - the checks that are ticked
  Notes:
    CDlgERCBox::OnOK: reads the check boxes.
  =========================================================================== }
function TfrmErcOptions.Options: TErcOptions;
begin
  Result.DupRef := cbDupRef.Checked;
  Result.UnConnect := cbUnConnect.Checked;
  Result.NoConnect := cbNoConnect.Checked;
  Result.Power := cbPower.Checked;
  Result.OutputPwr := cbOutputPwr.Checked;
  Result.Output := cbOutput.Checked;
  Result.NoOutput := cbNoOutput.Checked;
  Result.UnConnected := cbUnConnected.Checked;
  Result.MultipleNetNames := cbMultiple.Checked;
  Result.NonCaseDistinctNetNames := cbNonCase.Checked;
  Result.UnAssignedRefDes := cbUnassigned.Checked;
end;

{ ===========================================================================
  TfrmErcOptions.LoadFromSettings  (procedure)
  Parameters:  none
  Notes:
    Fills the dialog with the choices kept in the settings (the registry WORD, all on by
    default).
  =========================================================================== }
procedure TfrmErcOptions.LoadFromSettings;
begin
  SetOptions(ErcOptionsFromWord(Word(ProgramSettings.ErcWord)));
end;

{ ===========================================================================
  TfrmErcOptions.KeepInSettings  (procedure)
  Parameters:  none
  Notes:
    Puts the dialog's choices into the program settings as the WORD (the caller saves them).
  =========================================================================== }
procedure TfrmErcOptions.KeepInSettings;
begin
  ProgramSettings.ErcWord := ErcOptionsToWord(Options);
end;

end.
