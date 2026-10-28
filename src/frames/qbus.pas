unit QBus;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, Spin, StdCtrls, Buttons, QPropWire, Types, Graphics,
  LCLType, FSharedCtls, UEdit, UProps;
type
  { the property panel of the bus tool and of a selected bus: the wire's, and the Phases button (1 or 3 phase, and the distance between the wires; see FBusDropDown) }
  TfmBus = class(TfmPropRibbonWire)
    bbPhase: TSpeedButton;
  private

  public

  end;

implementation

{$R *.lfm}

end.

