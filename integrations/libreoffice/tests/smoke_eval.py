"""Evaluate CoworkingView formulas in a headless Calc document."""

import sys

import uno
from com.sun.star.beans import PropertyValue

SOURCE = "Data: CoworkingView https://coworkingview.com"


def connect(port):
    local = uno.getComponentContext()
    resolver = local.ServiceManager.createInstanceWithContext(
        "com.sun.star.bridge.UnoUrlResolver", local
    )
    return resolver.resolve(
        "uno:socket,host=127.0.0.1,port="
        + str(port)
        + ";urp;StarOffice.ComponentContext"
    )


def cell_text(cell):
    error = cell.getError()
    return {
        "formula": cell.getFormula(),
        "string": cell.getString(),
        "value": cell.getValue(),
        "error": error,
    }


def put(sheet, formula):
    cell = sheet.getCellByPosition(0, 0)
    cell.setFormula(formula)
    return cell


def main():
    port = sys.argv[1]
    ctx = connect(port)
    desktop = ctx.ServiceManager.createInstanceWithContext(
        "com.sun.star.frame.Desktop", ctx
    )
    hidden = PropertyValue()
    hidden.Name = "Hidden"
    hidden.Value = True
    doc = desktop.loadComponentFromURL("private:factory/scalc", "_blank", 0, (hidden,))
    sheet = doc.getSheets().getByIndex(0)
    doc.calculateAll()

    names = [
        "=CWV_SOURCE()",
        "=cwv_source()",
        "=COWORKINGVIEW.CWV_SOURCE()",
        "=COM.COWORKINGVIEW.CALC.COWORKINGVIEW.CWV_SOURCE()",
    ]
    tried = []
    working = None
    for formula in names:
        cell = put(sheet, formula)
        doc.calculateAll()
        got = cell_text(cell)
        tried.append((formula, got))
        if got["error"] in (0, None) and got["string"] == SOURCE:
            working = formula
            break
    print("SOURCE attempts:")
    for formula, got in tried:
        print(" ", formula, got)
    if working != "=CWV_SOURCE()":
        print("CWV_SOURCE() did not return the credit line", file=sys.stderr)
        return 1

    checks = [
        ('=CWV_SPACES("berlin")', "spaces-comma"),
        ('=CWV_PRICE("berlin","flex_desk")', "price-comma"),
        ('=CWV_PRICE("berlin";"flex_desk")', "price-semicolon"),
        ('=CWV_ATTRIBUTION("berlin")', "attribution"),
        ('=CWV_PRICE("berlin","not_a_product")', "bad-product-comma"),
        ('=CWV_PRICE("berlin";"not_a_product")', "bad-product-semicolon"),
    ]
    results = {}
    for formula, label in checks:
        cell = put(sheet, formula)
        doc.calculateAll()
        results[label] = cell_text(cell)
        print(label, results[label])

    spaces = results["spaces-comma"]
    if spaces["error"] not in (0, None) or spaces["value"] <= 0:
        # Some locales store the call with a semicolon. Try that spelling.
        cell = put(sheet, '=CWV_SPACES("berlin")')
        doc.calculateAll()
        spaces = cell_text(cell)
        print("spaces-retry", spaces)
    if not (spaces["error"] in (0, None) and spaces["value"] > 0):
        print("CWV_SPACES did not return a positive count", file=sys.stderr)
        return 1

    price = results["price-comma"]
    if price["error"] not in (0, None) or price["value"] <= 0:
        price = results["price-semicolon"]
    if not (price["error"] in (0, None) and price["value"] > 0):
        print("CWV_PRICE did not return a positive median", file=sys.stderr)
        return 1

    bad = results["bad-product-comma"]["string"]
    if not str(bad).startswith("CWV:"):
        bad = results["bad-product-semicolon"]["string"]
    if not str(bad).startswith("CWV:"):
        print("unknown product did not return a CWV error", bad, file=sys.stderr)
        return 1

    credit = results["attribution"]["string"]
    if "CoworkingView" not in credit or "CC BY" not in credit:
        print("attribution missing", credit, file=sys.stderr)
        return 1

    doc.close(True)
    print("evaluated CWV_SOURCE, CWV_SPACES, CWV_PRICE, CWV_ATTRIBUTION")
    return 0


if __name__ == "__main__":
    sys.exit(main())
