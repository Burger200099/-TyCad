// SPDX-License-Identifier: LGPL-2.1-or-later
{ A demonstration property frame (see QPropFrame): the line color, width and style of a wire, and a fill type that a wire does not have (so it is hidden).
  It is not registered by the program; the self-test script registers it (registerframe) and a person can copy it as the start of a frame of their own.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit QDemoWireProps;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Spin, Dialogs;

type

  { TfrDemoWire }

  TfrDemoWire = class(TFrame)
    cbFillType: TComboBox;
    cbLineStyle: TComboBox;
    cbtnLineColor: TColorButton;
    lbFillType: TLabel;
    lbLineColor: TLabel;
    lbLineStyle: TLabel;
    lbLineWidth: TLabel;
    pnlFillType: TPanel;
    pnlLineColor: TPanel;
    pnlLineStyle: TPanel;
    pnlLineWidth: TPanel;
    spLineWidth: TSpinEdit;
  end;

implementation

{$R *.lfm}

end.
