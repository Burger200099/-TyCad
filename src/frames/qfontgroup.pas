// SPDX-License-Identifier: LGPL-2.1-or-later
unit QFontGroup;

{ The font controls of the Properties panel as one frame: the face, the size in points, bold and italic, with the caption "Font" at the foot. It is laid out as the font
  panel (plFont) of the designed frames are (the wire label's, the text's), so a selection of different kinds of objects, which has no frame of its own and gets its editors
  made by the program, shows the font properties it shares in this one group and not as four separate captions and editors. The editors are named after their
  properties (cbFontFace font.face, cbFontHeight font.height, sbFontBold font.bold, sbFontItalic font.italic), so BindPropFrame links them without a list.

  Licence: LGPL 2.1 or later, as the rest of this port. }

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Buttons, CFontNameCombo, FSharedCtls;

type

  { TfmFontGroup }

  TfmFontGroup = class(TFrame)
    cbFontFace: TFontNameCombo;
    cbFontHeight: TComboBox;
    lbFont: TLabel;
    sbFontBold: TSpeedButton;
    sbFontItalic: TSpeedButton;
  end;

implementation

{$R *.lfm}

end.
