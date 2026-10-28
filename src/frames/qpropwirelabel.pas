unit QPropWireLabel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Buttons, ExtCtrls, QPropBase, Types,
  Graphics, LCLType, CFontNameCombo;

type

  { TfmPropWireLabel }

  TfmPropWireLabel = class(TfmPropertyBase)
    cbTextDirection: TComboBox;
    cbTextDirection1: TComboBox;
    cbFont: TFontNameCombo;
    cbFontSize: TComboBox;
    edText: TEdit;
    lbFont: TLabel;
    lbWire: TLabel;
    lbDirection: TLabel;
    lbType: TLabel;
    lbSep1: TPanel;
    plFont: TPanel;
    plText: TPanel;
    sbBold: TSpeedButton;
    sbItalic: TSpeedButton;
    procedure cbTextDirectionChange(Sender: TObject);
  private
  public
    procedure AfterCreate; override;
  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmPropWireLabel.cbTextDirectionChange  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropWireLabel.cbTextDirectionChange(Sender: TObject);
begin

end;

{ ===========================================================================
  TfmPropWireLabel.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    TODO: describe.
  =========================================================================== }
procedure TfmPropWireLabel.AfterCreate;
begin
  lbCaption.Visible := false;
end;

end.

