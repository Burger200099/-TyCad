unit FShared;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs;

type

  { TfrmSharedControls }

  TfrmSharedControls = class(TForm)
    ColorDialog1: TColorDialog;
  private

  public

  end;

var
  frmSharedControls: TfrmSharedControls;

implementation

{$R *.lfm}

end.

