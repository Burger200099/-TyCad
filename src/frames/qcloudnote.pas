// SPDX-License-Identifier: LGPL-2.1-or-later
unit QCloudNote;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Spin, QPropWire, FSharedCtls;

type

  { TfmCloudRect }

  TfmCloudRect = class(TfmPropRibbonWire)
    fseScallop: TFloatSpinEdit;
    lbScallop: TLabel;
  private

  public
    procedure AfterCreate;

  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmCloudRect.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    TfmCloudRect
  =========================================================================== }
procedure TfmCloudRect.AfterCreate;
begin
  cbAngle.Visible := false;
end;

end.

