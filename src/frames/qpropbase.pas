// SPDX-License-Identifier: LGPL-2.1-or-later
unit QPropBase;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls;

type

  { TfmPropertyBase }

  TfmPropertyBase = class(TFrame)
    lbCaption: TLabel;
  private

  public
    procedure AfterCreate; virtual;

  end;

implementation

{$R *.lfm}

{ TfmPropertyBase }

{ ===========================================================================
  TfmPropertyBase.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    Call this after creation for frame specific setup.
  =========================================================================== }
procedure TfmPropertyBase.AfterCreate;
begin

end;

end.

