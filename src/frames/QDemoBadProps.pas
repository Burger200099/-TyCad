// SPDX-License-Identifier: LGPL-2.1-or-later
{ A demonstration of a property frame with mistakes (see QPropFrame), for the self-test script: a text box for a whole number, a number box for a color, and
  two drop-downs for the same property. The program shows the frame anyway, disables the editors it cannot use and reports each.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit QDemoBadProps;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Spin;

type

  { TfrDemoBad }

  TfrDemoBad = class(TFrame)
    cbLineStyle: TComboBox;
    cbStyleLineStyle: TComboBox;
    edLineWidth: TEdit;
    spLineColor: TSpinEdit;
  end;

implementation

{$R *.lfm}

end.
