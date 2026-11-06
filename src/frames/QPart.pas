unit QPart;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, QPropBase;

type

  { TfmPart }

  TfmPart = class(TfmPropertyBase)
    btnGoTo: TButton;
    cbPartObjects: TComboBox;
    lbPartObject: TLabel;
    lbPartTitle: TLabel;
    pbPartGlyph: TPaintBox;
  private

  public
    procedure ControlsHidden(const AHidden: array of TControl); override;
    procedure DoShow; override;
  end;

implementation

{$R *.lfm}

{ TfmPart }

procedure TfmPart.ControlsHidden(const AHidden: array of TControl);
begin
  inherited ControlsHidden(AHidden);
end;

procedure TfmPart.DoShow;
var i, j, textlen: integer;
begin
  inherited DoShow;
  textlen := 0;
  for i := 0 to cbPartObjects.Items.Count - 1 do
    begin
      j := cbPartObjects.Canvas.TextExtent(cbPartObjects.Items[i]).Width;
      if j > textlen then
        textlen := j;
    end;
  cbPartObjects.Width := textlen + Scale96toForm(40);
  btnGoTo.Left := cbPartObjects.Left + cbPartObjects.Width + Scale96toForm(8);
  Self.Width := btnGoTo.Left + btnGoTo.Width + Scale96toForm(4);
end;

end.

