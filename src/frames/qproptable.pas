// SPDX-License-Identifier: LGPL-2.1-or-later
{ The ribbon frame of a table: the Font part of the text frame (font, size, bold, italic, color) without its text panel; the font is the one the table is drawn in. }
unit QPropTable;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, QPropText;

type

  { TfmPropTable }

  TfmPropTable = class(TfmPropText)
  public
    procedure AfterCreate; override;
  end;

implementation

{$R *.lfm}

{ ===========================================================================
  TfmPropTable.AfterCreate  (procedure)
  Parameters:  none
  Notes:
    The text panel and the line beside it are hidden in the .lfm; the caption of the frame stays hidden as in the text frame.
  =========================================================================== }
procedure TfmPropTable.AfterCreate;
begin
  inherited AfterCreate;
end;

end.
