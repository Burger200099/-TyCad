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
    procedure ControlsHidden(const AHidden: array of TControl); virtual;
    procedure DoShow; virtual;
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

{ ===========================================================================
  TfmPropertyBase.ControlsHidden  (procedure)
  Parameters:
    const AHidden: array of TControl - the controls BindPropFrame hid (editors the tool or
      selection has no property for, their captions, and panels left with nothing visible)
  Notes:
    Called once after every bind, also when nothing was hidden (AHidden is then empty), so a
    frame can lay itself out again for whichever controls are showing (move the ones to the
    right of a hidden one, change its Width). Override it in a frame that needs this; it does
    nothing here.
  =========================================================================== }
procedure TfmPropertyBase.ControlsHidden(const AHidden: array of TControl);
begin

end;

procedure TfmPropertyBase.DoShow;
begin

end;

end.

