{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit TyCad_Components;

{$warn 5023 off : no warning about unused units}
interface

uses
  CSplitButton, CFontNameCombo, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('CSplitButton', @CSplitButton.Register);
  RegisterUnit('CFontNameCombo', @CFontNameCombo.Register);
end;

initialization
  RegisterPackage('TyCad_Components', @Register);
end.
