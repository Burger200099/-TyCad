-- TyCAD parts database ("TCParts"): NOT compatible with TinyCAD's .TCLib. Draft 3.
-- Two levels: a PART is generic (what the design needs: class, symbol, terminals/contacts/coils, the REQUIRED ratings) and a PRODUCT is a catalog item
-- (manufacturer, model number, what it actually is rated for, datasheets, 3D model, footprint, offers). A design places generic parts and may name the
-- product in the placed part's details; a product that is bigger than the part needs is fine, a smaller one is reported (view ProductFit).
-- Inheritance rule: a class (of parts) or a kind (of child objects) has every field and every allowed child kind
-- of all its ancestors, plus its own. Fields are declared once, on the highest class that needs them.
PRAGMA foreign_keys = ON;
PRAGMA user_version = 1;             -- the same number as FormatInfo.SchemaVersion (a quick read for tools); keep both in step

CREATE TABLE FormatInfo (            -- one row: lets the program warn on first use and keeps TinyCAD from opening the file by mistake
  Format TEXT NOT NULL CHECK (Format = 'TyCAD-Parts'),
  SchemaVersion INTEGER NOT NULL,
  TinyCADCompatible INTEGER NOT NULL DEFAULT 0 CHECK (TinyCADCompatible = 0),
  Created TEXT, Generator TEXT);

CREATE TABLE LibraryInfo (           -- who and what this parts library is (shown in the library list)
  LibraryUID TEXT NOT NULL, Name TEXT, Description TEXT, Author TEXT, Created TEXT, Modified TEXT, Website TEXT);

CREATE TABLE SchemaHistory (         -- one row per upgrade: the file's own record of how it got to its version
  FromVersion INTEGER NOT NULL, ToVersion INTEGER NOT NULL, Applied TEXT NOT NULL, Program TEXT, Note TEXT);

-- ---------------------------------------------------------------- classes of parts
CREATE TABLE PartClass (
  ClassID INTEGER PRIMARY KEY, ParentID INTEGER REFERENCES PartClass(ClassID),
  Name TEXT NOT NULL UNIQUE, Abstract INTEGER NOT NULL DEFAULT 0, Description TEXT);

CREATE TABLE FieldDef (              -- a field declared by a class; the descendants inherit it
  FieldID INTEGER PRIMARY KEY, ClassID INTEGER NOT NULL REFERENCES PartClass(ClassID),
  Name TEXT NOT NULL, Type TEXT NOT NULL CHECK (Type IN ('text','int','real','bool','enum','ref')),
  Unit TEXT, EnumValues TEXT, Required INTEGER NOT NULL DEFAULT 0, Description TEXT,
  UNIQUE (ClassID, Name));

-- ---------------------------------------------------------------- kinds of child objects (active / passive)
CREATE TABLE ObjectKind (
  KindID INTEGER PRIMARY KEY, ParentID INTEGER REFERENCES ObjectKind(KindID),
  Name TEXT NOT NULL UNIQUE, Abstract INTEGER NOT NULL DEFAULT 0, Description TEXT);

CREATE TABLE KindFieldDef (
  FieldID INTEGER PRIMARY KEY, KindID INTEGER NOT NULL REFERENCES ObjectKind(KindID),
  Name TEXT NOT NULL, Type TEXT NOT NULL CHECK (Type IN ('text','int','real','bool','enum','ref')),
  Unit TEXT, EnumValues TEXT, Required INTEGER NOT NULL DEFAULT 0, Description TEXT,
  UNIQUE (KindID, Name));

CREATE TABLE ClassAllowsKind (       -- which child kinds a class may have (and, through the kind tree, their sub-kinds)
  ClassID INTEGER NOT NULL REFERENCES PartClass(ClassID), KindID INTEGER NOT NULL REFERENCES ObjectKind(KindID),
  MinCount INTEGER NOT NULL DEFAULT 0, MaxCount INTEGER, PRIMARY KEY (ClassID, KindID));

-- ---------------------------------------------------------------- the parts
CREATE TABLE Part (                  -- a GENERIC part: the function and ratings a design needs, whoever makes it
  PartID INTEGER PRIMARY KEY, UID TEXT NOT NULL UNIQUE,   -- UID: a GUID that never changes, so designs and other libraries can refer to the part; PartID is only this file's row number
  ClassID INTEGER NOT NULL REFERENCES PartClass(ClassID),
  Name TEXT NOT NULL, Description TEXT, RefPrefix TEXT,      -- RefPrefix: the reference letters a placed part starts with ('K' gives K1, K2 ...)
  Status TEXT NOT NULL DEFAULT 'active' CHECK (Status IN ('active','obsolete','preview','custom')),
  BaseDefault INTEGER REFERENCES Symbol(SymbolID),
  Revision TEXT, Modified TEXT, UNIQUE (ClassID, Name));

CREATE TABLE Product (               -- a catalog item from one manufacturer; it can be chosen for any generic part of its class (see ProductFit)
  ProductID INTEGER PRIMARY KEY, UID TEXT NOT NULL UNIQUE,
  ClassID INTEGER NOT NULL REFERENCES PartClass(ClassID),
  Manufacturer TEXT NOT NULL, MPN TEXT NOT NULL, Series TEXT, Description TEXT,
  Status TEXT NOT NULL DEFAULT 'active' CHECK (Status IN ('active','obsolete','preview','custom')),
  ReplacedBy INTEGER REFERENCES Product(ProductID), Revision TEXT, Modified TEXT, UNIQUE (Manufacturer, MPN));

CREATE TABLE PartProduct (           -- the library author's suggestions: products that suit a generic part (a short list; any product of the class may still be chosen)
  PartID INTEGER NOT NULL REFERENCES Part(PartID) ON DELETE CASCADE, ProductID INTEGER NOT NULL REFERENCES Product(ProductID) ON DELETE CASCADE,
  Preferred INTEGER NOT NULL DEFAULT 0, Note TEXT, PRIMARY KEY (PartID, ProductID));

CREATE TABLE PartGlyph (             -- the icon of a part for lists and trees: one PNG per size in pixels (square: 16, 24, 32, 48 ...); the program takes the nearest size to what it needs
  PartID INTEGER NOT NULL REFERENCES Part(PartID) ON DELETE CASCADE, Size INTEGER NOT NULL CHECK (Size BETWEEN 8 AND 512),
  Png BLOB NOT NULL, PRIMARY KEY (PartID, Size));

CREATE TABLE PartValue (             -- the values of the part's inherited fields (one of the three value columns is used)
  PartID INTEGER NOT NULL REFERENCES Part(PartID) ON DELETE CASCADE, FieldID INTEGER NOT NULL REFERENCES FieldDef(FieldID),
  ValueNum REAL, ValueText TEXT, PRIMARY KEY (PartID, FieldID));

CREATE TABLE PartObject (            -- a child of a part (or of another child: a pole holds its contacts, a channel its terminals)
  ObjectID INTEGER PRIMARY KEY, PartID INTEGER NOT NULL REFERENCES Part(PartID) ON DELETE CASCADE,
  ParentObjectID INTEGER REFERENCES PartObject(ObjectID) ON DELETE CASCADE,
  KindID INTEGER NOT NULL REFERENCES ObjectKind(KindID), Name TEXT NOT NULL, Designator TEXT,   -- the terminal number or channel name as printed
  Sort INTEGER NOT NULL DEFAULT 0, Description TEXT);

CREATE TABLE ObjectValue (
  ObjectID INTEGER NOT NULL REFERENCES PartObject(ObjectID) ON DELETE CASCADE, FieldID INTEGER NOT NULL REFERENCES KindFieldDef(FieldID),
  ValueNum REAL, ValueText TEXT, PRIMARY KEY (ObjectID, FieldID));

CREATE TABLE RatingQuantity (        -- what can be rated, its one unit, and how a product is judged against a part: 'min' = the product must be at least as much (current, power),
  Name TEXT PRIMARY KEY, Unit TEXT NOT NULL,   -- 'max' = at most (coil power, voltage drop), 'match' = equal (coil voltage, poles); the value compared is Max, else Typ, else Min
  Sense TEXT NOT NULL CHECK (Sense IN ('min','max','match')), Description TEXT);

CREATE TABLE Rating (                -- of a PART (PartID): what the design REQUIRES;  of a PRODUCT (ProductID): what it is actually RATED for. On the whole thing, or on one object.
  RatingID INTEGER PRIMARY KEY,
  PartID INTEGER REFERENCES Part(PartID) ON DELETE CASCADE, ProductID INTEGER REFERENCES Product(ProductID) ON DELETE CASCADE,
  ObjectID INTEGER REFERENCES PartObject(ObjectID) ON DELETE CASCADE,       -- part ratings: the child object (null = the whole part)
  AppliesTo TEXT,                                                           -- product ratings: null = the whole product, an object's name ('Pole 1'), or 'kind:Contact' = every object of that kind
  Quantity TEXT NOT NULL REFERENCES RatingQuantity(Name), Min REAL, Typ REAL, Max REAL, Unit TEXT NOT NULL, Condition TEXT,   -- e.g. 'AC-15 230 V'; a product value counts against a part value of the same Condition
  CHECK ((PartID IS NULL) <> (ProductID IS NULL)), CHECK (ProductID IS NOT NULL OR AppliesTo IS NULL), CHECK (PartID IS NOT NULL OR ObjectID IS NULL));
CREATE TRIGGER Rating_unit BEFORE INSERT ON Rating
WHEN NEW.Unit <> (SELECT Unit FROM RatingQuantity WHERE Name = NEW.Quantity)
BEGIN SELECT RAISE(ABORT, 'the unit is not the unit of this quantity'); END;

CREATE TABLE Link (                  -- internal relations: bridged terminals, a contact driven by a coil, a pole's terminals
  LinkID INTEGER PRIMARY KEY, PartID INTEGER NOT NULL REFERENCES Part(PartID) ON DELETE CASCADE,
  FromObject INTEGER NOT NULL REFERENCES PartObject(ObjectID), ToObject INTEGER NOT NULL REFERENCES PartObject(ObjectID),
  Relation TEXT NOT NULL CHECK (Relation IN ('bridged','driven_by','switches','powers','isolated_from','shares_return')));

-- ---------------------------------------------------------------- symbol and 3D model
CREATE TABLE Symbol (                    -- Drawing = the symbol as TinyCAD XML (the same BLOB as the Symbol table of a .TCLib), so the symbol loader and editor read it as is
  SymbolID INTEGER PRIMARY KEY, PartID INTEGER NOT NULL REFERENCES Part(PartID) ON DELETE CASCADE,
  Standard TEXT NOT NULL DEFAULT 'IEC', Purpose TEXT NOT NULL DEFAULT 'schematic' CHECK (Purpose IN ('schematic','oneline','panel','block')),
  PartNo INTEGER NOT NULL DEFAULT 0, Name TEXT, Drawing BLOB NOT NULL, OriginX REAL, OriginY REAL);
CREATE TABLE SymbolPin (             -- which child object each pin of a symbol is, so a symbol can be swapped without touching the data
  SymbolID INTEGER NOT NULL REFERENCES Symbol(SymbolID) ON DELETE CASCADE, ObjectID INTEGER NOT NULL REFERENCES PartObject(ObjectID),
  X REAL NOT NULL, Y REAL NOT NULL, Direction INTEGER, PRIMARY KEY (SymbolID, ObjectID));
CREATE TABLE Outline2D (             -- the product's footprint on a panel or rail: a drawing plus mounting holes and keep-out (its terminals are the generic part's objects)
  OutlineID INTEGER PRIMARY KEY, ProductID INTEGER NOT NULL REFERENCES Product(ProductID) ON DELETE CASCADE,
  Name TEXT, Drawing BLOB NOT NULL, Width REAL, Height REAL, Units TEXT NOT NULL DEFAULT 'mm', HolesJson TEXT, KeepOutJson TEXT);
CREATE TABLE OutlineTerminal (OutlineID INTEGER NOT NULL REFERENCES Outline2D(OutlineID) ON DELETE CASCADE,
  ObjectID INTEGER NOT NULL REFERENCES PartObject(ObjectID), X REAL NOT NULL, Y REAL NOT NULL, PRIMARY KEY (OutlineID, ObjectID));
CREATE TABLE PartTag (PartID INTEGER NOT NULL REFERENCES Part(PartID) ON DELETE CASCADE, Tag TEXT NOT NULL, PRIMARY KEY (PartID, Tag));   -- keywords for searching
CREATE TABLE Model3D (               -- a product's 3D model
  ModelID INTEGER PRIMARY KEY, ProductID INTEGER NOT NULL REFERENCES Product(ProductID) ON DELETE CASCADE,
  Format TEXT NOT NULL, Units TEXT NOT NULL DEFAULT 'mm', FileName TEXT, Data BLOB,
  Width REAL, Height REAL, Depth REAL, Mounting TEXT, OriginNote TEXT);
CREATE TABLE ModelTerminal (         -- where each terminal is in 3D (wire routing in the panel view)
  ModelID INTEGER NOT NULL REFERENCES Model3D(ModelID) ON DELETE CASCADE, ObjectID INTEGER NOT NULL REFERENCES PartObject(ObjectID),
  X REAL, Y REAL, Z REAL, NormalX REAL, NormalY REAL, NormalZ REAL, PRIMARY KEY (ModelID, ObjectID));

-- ---------------------------------------------------------------- the rest
CREATE TABLE Document (DocID INTEGER PRIMARY KEY, ProductID INTEGER NOT NULL REFERENCES Product(ProductID) ON DELETE CASCADE,
  Kind TEXT NOT NULL, Title TEXT, Url TEXT, FileName TEXT, Data BLOB, Revision TEXT, Sha256 TEXT);
CREATE TABLE Approval (ProductID INTEGER NOT NULL REFERENCES Product(ProductID) ON DELETE CASCADE, Body TEXT NOT NULL, Certificate TEXT, Scope TEXT, Expires TEXT);
CREATE TABLE Supplier (SupplierID INTEGER PRIMARY KEY, Name TEXT NOT NULL UNIQUE);
CREATE TABLE Offer (ProductID INTEGER NOT NULL REFERENCES Product(ProductID) ON DELETE CASCADE, SupplierID INTEGER NOT NULL REFERENCES Supplier(SupplierID),
  SKU TEXT, Url TEXT, Currency TEXT, UnitPrice REAL, MinQty INTEGER, LeadDays INTEGER, Checked TEXT);   -- time-stamped, may be stale
CREATE TABLE Substitute (ProductID INTEGER NOT NULL REFERENCES Product(ProductID), SubstituteID INTEGER NOT NULL REFERENCES Product(ProductID),
  DropIn INTEGER NOT NULL DEFAULT 0, Note TEXT, PRIMARY KEY (ProductID, SubstituteID));
CREATE TABLE PartRule (              -- hooks for the checker
  RuleID INTEGER PRIMARY KEY, PartID INTEGER NOT NULL REFERENCES Part(PartID) ON DELETE CASCADE,
  Kind TEXT NOT NULL CHECK (Kind IN ('requires','conflicts','recommends')), TargetClassID INTEGER REFERENCES PartClass(ClassID),
  TargetPartID INTEGER REFERENCES Part(PartID), Note TEXT);
CREATE TABLE ProductOption (         -- variants: a base product plus orderable options (coil voltage, terminal type)
  OptionID INTEGER PRIMARY KEY, ProductID INTEGER NOT NULL REFERENCES Product(ProductID) ON DELETE CASCADE,
  Code TEXT NOT NULL, Description TEXT, ChangesField INTEGER REFERENCES FieldDef(FieldID), Value TEXT);

-- ---------------------------------------------------------------- inheritance, resolved
CREATE VIEW ClassAncestors AS         -- (ClassID, AncestorID, Depth): every class with itself and all its parents
WITH RECURSIVE a(ClassID, AncestorID, Depth) AS (
  SELECT ClassID, ClassID, 0 FROM PartClass
  UNION ALL SELECT a.ClassID, p.ParentID, a.Depth + 1 FROM a JOIN PartClass p ON p.ClassID = a.AncestorID WHERE p.ParentID IS NOT NULL)
SELECT * FROM a;
CREATE VIEW KindAncestors AS
WITH RECURSIVE a(KindID, AncestorID, Depth) AS (
  SELECT KindID, KindID, 0 FROM ObjectKind
  UNION ALL SELECT a.KindID, k.ParentID, a.Depth + 1 FROM a JOIN ObjectKind k ON k.KindID = a.AncestorID WHERE k.ParentID IS NOT NULL)
SELECT * FROM a;
CREATE VIEW ClassFields AS            -- the whole field set of a class: its own and every ancestor's
SELECT ca.ClassID, f.* FROM ClassAncestors ca JOIN FieldDef f ON f.ClassID = ca.AncestorID;
CREATE VIEW KindFields AS
SELECT ka.KindID, f.* FROM KindAncestors ka JOIN KindFieldDef f ON f.KindID = ka.AncestorID;
CREATE VIEW ClassKinds AS             -- child kinds a class allows: its own and its ancestors', with their sub-kinds
SELECT DISTINCT ca.ClassID, ka.KindID FROM ClassAncestors ca JOIN ClassAllowsKind ck ON ck.ClassID = ca.AncestorID
JOIN KindAncestors ka ON ka.AncestorID = ck.KindID;

-- a value may only be stored for a field the part's class has (own or inherited); same for objects
CREATE TRIGGER PartValue_inherit BEFORE INSERT ON PartValue
WHEN NOT EXISTS (SELECT 1 FROM Part p JOIN ClassFields cf ON cf.ClassID = p.ClassID WHERE p.PartID = NEW.PartID AND cf.FieldID = NEW.FieldID)
BEGIN SELECT RAISE(ABORT, 'field is not a field of the part''s class or its ancestors'); END;
CREATE TRIGGER ObjectValue_inherit BEFORE INSERT ON ObjectValue
WHEN NOT EXISTS (SELECT 1 FROM PartObject o JOIN KindFields kf ON kf.KindID = o.KindID WHERE o.ObjectID = NEW.ObjectID AND kf.FieldID = NEW.FieldID)
BEGIN SELECT RAISE(ABORT, 'field is not a field of the object''s kind or its ancestors'); END;
CREATE TRIGGER PartObject_kind BEFORE INSERT ON PartObject
WHEN NOT EXISTS (SELECT 1 FROM Part p JOIN ClassKinds ck ON ck.ClassID = p.ClassID WHERE p.PartID = NEW.PartID AND ck.KindID = NEW.KindID)
BEGIN SELECT RAISE(ABORT, 'the part''s class does not allow this kind of child'); END;

-- ---------------------------------------------------------------- does a product fit a part?  (the design's verify check reads these)
-- Every requirement (a rating of the part) is looked up among the product's ratings: same quantity and condition, on the same object by name, or on its kind.
-- The most specific product rating wins (the object's own name before 'kind:...').
CREATE VIEW ProductFit AS
SELECT pr.ProductID, s.PartID, r.RatingID, r.Quantity, r.Condition, o.Name AS ObjectName, q.Sense, q.Unit,
       coalesce(r.Max, r.Typ, r.Min) AS Need, h.Have,
       CASE WHEN h.Have IS NULL THEN 'missing'
            WHEN q.Sense = 'match' THEN CASE WHEN h.Have = coalesce(r.Max, r.Typ, r.Min) THEN 'ok' ELSE 'mismatch' END
            WHEN h.Have = coalesce(r.Max, r.Typ, r.Min) THEN 'ok'
            WHEN (q.Sense = 'min' AND h.Have > coalesce(r.Max, r.Typ, r.Min)) OR (q.Sense = 'max' AND h.Have < coalesce(r.Max, r.Typ, r.Min)) THEN 'oversized'
            ELSE 'undersized' END AS Status
FROM Product pr JOIN Part s ON s.ClassID = pr.ClassID JOIN Rating r ON r.PartID = s.PartID JOIN RatingQuantity q ON q.Name = r.Quantity
LEFT JOIN PartObject o ON o.ObjectID = r.ObjectID
LEFT JOIN (SELECT pr2.ProductID AS ProductID, r2.RatingID AS RatingID, (SELECT coalesce(h.Max, h.Typ, h.Min) FROM Rating h
            WHERE h.ProductID = pr2.ProductID AND h.Quantity = r2.Quantity AND h.Condition IS r2.Condition
              AND ((r2.ObjectID IS NULL AND h.AppliesTo IS NULL)
                   OR (r2.ObjectID IS NOT NULL AND (h.AppliesTo = (SELECT Name FROM PartObject WHERE ObjectID = r2.ObjectID)
                        OR h.AppliesTo IN (SELECT 'kind:' || k.Name FROM PartObject po JOIN KindAncestors ka ON ka.KindID = po.KindID JOIN ObjectKind k ON k.KindID = ka.AncestorID WHERE po.ObjectID = r2.ObjectID))))
            ORDER BY h.AppliesTo LIKE 'kind:%' LIMIT 1) AS Have
           FROM Product pr2 JOIN Part s2 ON s2.ClassID = pr2.ClassID JOIN Rating r2 ON r2.PartID = s2.PartID) h
       ON h.ProductID = pr.ProductID AND h.RatingID = r.RatingID;

CREATE VIEW ProductFitSummary AS      -- one verdict per (product, part): 'does_not_fit' (anything undersized, missing or mismatched), 'fits_oversized', 'fits', or 'no_requirements'
SELECT pr.ProductID, s.PartID,
       sum(f.Status = 'ok') AS Ok, sum(f.Status = 'oversized') AS Oversized, sum(f.Status = 'undersized') AS Undersized,
       sum(f.Status = 'missing') AS Missing, sum(f.Status = 'mismatch') AS Mismatch,
       CASE WHEN count(f.RatingID) = 0 THEN 'no_requirements'
            WHEN sum(f.Status IN ('undersized','missing','mismatch')) > 0 THEN 'does_not_fit'
            WHEN sum(f.Status = 'oversized') > 0 THEN 'fits_oversized' ELSE 'fits' END AS Verdict
FROM Product pr JOIN Part s ON s.ClassID = pr.ClassID LEFT JOIN ProductFit f ON f.ProductID = pr.ProductID AND f.PartID = s.PartID
GROUP BY pr.ProductID, s.PartID;
