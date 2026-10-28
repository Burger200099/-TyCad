// SPDX-License-Identifier: LGPL-2.1-or-later
{ The property frame of a pin of a symbol being drawn (CEditDlgPinEdit as ribbon controls). Every editor is bound to its property by QPropFrame, by its name:
    edPinName        the name of the pin                                   pin.name
    edPinNumber      the number (a text: 1, A3, ...)                       pin.number
    sePinLength      the length of the pin                                 pin.length
    sePinNumPos      where along the pin its number is written             pin.numpos
    cbPinShape       the type of the pin (Normal, Dot, Clock ...)          pin.shape
    cbPinElec        the electrical type (Input, Output ...)               pin.elec
    sbPinShowName    whether the name is shown                             pin.showname
    sbPinShowNumber  whether the number is shown                           pin.shownumber
    sbPinCentre      whether the name is centred on the pin                pin.centre
  Nothing is wired by hand: the choices of the two lists, the values, the limits and the changes (undo steps) are made by the main window like for every frame.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit QPin;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Spin, Buttons, QPropBase, FSharedCtls;

type

  { TfmPin }

  TfmPin = class(TfmPropertyBase)
    cbPinElec: TComboBox;
    cbPinShape: TComboBox;
    edPinName: TEdit;
    edPinNumber: TEdit;
    lbElec: TLabel;
    lbLength: TLabel;
    lbName: TLabel;
    lbNumber: TLabel;
    lbNumPos: TLabel;
    lbShape: TLabel;
    sbPinCentre: TSpeedButton;
    sbPinShowName: TSpeedButton;
    sbPinShowNumber: TSpeedButton;
    sePinLength: TSpinEdit;
    sePinNumPos: TSpinEdit;
  end;

implementation

{$R *.lfm}

end.
