# Places chosen by hand for i18n_rewrite.py (file base name, line number of the file as it was when the tool ran).
EXTRA_LINES |= {("mainform.pas", n) for n in [6895, 6899, 6964, 8416, 9991, 10325] + list(range(12915, 12972))}
EXTRA_LINES |= {("Fproductpick.pas", n) for n in range(48, 76)}
EXTRA_LINES |= {("UPartData.pas", n) for n in range(380, 412)}
EXTRA_LINES |= {("QPartsEditor.pas", n) for n in range(1935, 1956)}
EXTRA_LINES |= {("Foptions.pas", n) for n in range(345, 380)}
EXTRA_LINES |= {("Fdetails.pas", 948), ("UNetWriters.pas", 344), ("UPainter.pas", 2282)}
EXTRA_LINES |= {("UPartCheck.pas", n) for n in range(125, 147)}
SKIP_LINES |= {("Fsymprops.pas", 490), ("Fvalueedit.pas", 67), ("Fvalueedit.pas", 68), ("QPartsEditor.pas", 844)}
SKIP_TEXTS |= {"package"}
def _r(f, *spans):
    for a in spans:
        if isinstance(a, tuple):
            EXTRA_LINES.update((f, n) for n in range(a[0], a[1] + 1))
        else:
            EXTRA_LINES.add((f, a))
_r("UDocs.pas", 91, 93, 99, 101, 106, 108)
_r("UErc.pas", (345, 358))
_r("UOptions.pas", (300, 310))
_r("Foptions.pas", 380, (441, 446))
_r("Fdetails.pas", (975, 983))
_r("Fexport.pas", 236, 238)
_r("Finput.pas", 104)
_r("Fpagesetup.pas", 527, 529)
_r("Fprint.pas", (329, 337), (356, 370), (437, 439), (477, 479), (799, 801))
_r("UPrint.pas", (561, 639))
_r("UPrintRun.pas", 425)
_r("Fproductpick.pas", 134)
_r("Fvalueedit.pas", 56)
_r("QPartsEditor.pas", 702, (860, 861), 1959)
_r("qsymbols.pas", 85)
_r("UXMLException.pas", 44)
_r("UPartCheck.pas", (118, 124))
