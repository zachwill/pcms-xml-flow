"""Generate minimal XlsxWriter workbooks to isolate Excel warnings.

These are intentionally tiny files you can open in Excel to see which feature
triggers warnings ("macros", "repaired", etc.).

Usage:
  uv run python excel/dev/make_xlsxwriter_tests.py

Outputs into: shared/xlsxwriter_tests/
"""

from __future__ import annotations

from pathlib import Path

import xlsxwriter


OUT_DIR = Path("shared/xlsxwriter_tests")


def _mk(name: str):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    return OUT_DIR / name


def test_data_validation_range() -> None:
    """List validation using a sheet range reference (like our PLAYGROUND inputs)."""

    path = _mk("test_data_validation_range.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")
    data = wb.add_worksheet("DATA")
    data.hide()

    # Populate a list.
    data.write_row("B1", ["player_name"])
    for i, name in enumerate(["Alpha", "Bravo", "Charlie", "Delta"], start=2):
        data.write(f"B{i}", name)

    ws.write("A1", "Pick:")
    ws.write("B1", "")

    # Mirror our pattern: source as sheet!$B$2:$B$20000.
    ws.data_validation(
        "B1",
        {
            "validate": "list",
            "source": "=DATA!$B$2:$B$20000",
        },
    )

    wb.close()


def test_defined_name_nested_equals_bad() -> None:
    """Deliberately-bad defined name with nested '=LET()' (should trigger repair)."""

    path = _mk("test_defined_name_nested_equals_BAD.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    wb.define_name(
        "BadName",
        "=LET(_xlpm.a,1,_xlpm.b,=LET(_xlpm.c,2,_xlpm.c),_xlpm.a+_xlpm.b)",
    )

    ws.write("A1", "BadName:")
    ws.write_formula("B1", "=BadName")

    wb.close()


def test_defined_name_future_functions_unprefixed() -> None:
    """Defined name using UNIQUE() without explicit _xlfn prefixes."""

    path = _mk("test_defined_name_future_unprefixed.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    ws.write_column("A1", [1, 2, 2, 3, 3, 3])

    # In defined names, XlsxWriter may not auto-prefix future functions.
    # Also: workbook-level names that reference cells may need a sheet qualifier.
    wb.define_name("U", "=UNIQUE(A1:A6)")
    ws.write_dynamic_array_formula("C1", "=U")

    wb.close()


def test_defined_name_future_functions_prefixed() -> None:
    """Defined name using explicit _xlfn prefixes (per XlsxWriter lambda example)."""

    path = _mk("test_defined_name_future_prefixed.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    ws.write_column("A1", [1, 2, 2, 3, 3, 3])

    wb.define_name("U", "=_xlfn.UNIQUE(A1:A6)")
    ws.write_dynamic_array_formula("C1", "=U")

    wb.close()


def test_defined_name_future_prefixed_with_sheetref() -> None:
    """Defined name with explicit _xlfn prefix AND explicit sheet reference.

    Hypothesis: workbook-level names that reference cells should include the
    sheet name (Excel tends to store them as Sheet!$A$1:$A$6).
    """

    path = _mk("test_defined_name_future_prefixed_sheetref.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    ws.write_column("A1", [1, 2, 2, 3, 3, 3])

    wb.define_name("U", "=_xlfn.UNIQUE(UI!$A$1:$A$6)")
    ws.write_dynamic_array_formula("C1", "=U")

    wb.close()


def test_defined_name_future_prefixed_not_used() -> None:
    """Defined name with _xlfn.UNIQUE but never referenced by any cell."""

    path = _mk("test_defined_name_future_prefixed_not_used.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    ws.write_column("A1", [1, 2, 2, 3, 3, 3])
    wb.define_name("U", "=_xlfn.UNIQUE(A1:A6)")

    # No usage.
    ws.write("C1", "(name U defined, not used)")

    wb.close()


def test_defined_name_future_used_write_formula() -> None:
    """Use a future-function defined name but call it with write_formula().

    If this opens cleanly but dynamic-array call doesn't, it suggests the issue
    is in how dynamic array calls to defined names are stored.
    """

    path = _mk("test_defined_name_future_used_write_formula.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    ws.write_column("A1", [1, 2, 2, 3, 3, 3])
    wb.define_name("U", "=_xlfn.UNIQUE(A1:A6)")

    # Call without dynamic array write.
    ws.write_formula("C1", "=U")

    wb.close()


def test_defined_name_let_scalar() -> None:
    """Scalar LET() stored as a defined name."""

    path = _mk("test_defined_name_let_scalar.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    wb.define_name("X", "=_xlfn.LET(_xlpm.a,1,_xlpm.a)")
    ws.write_formula("A1", "=X")

    wb.close()


def test_defined_name_points_to_cell_with_let() -> None:
    """Defined name is a plain cell ref; the cell contains LET().

    Hypothesis: Excel warnings are about *defined name formulas* that contain
    future functions, not about future functions in cells.
    """

    path = _mk("test_defined_name_points_to_cell_with_let.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    ws.write_formula("D1", "=_xlfn.LET(_xlpm.a,1,_xlpm.a)")
    wb.define_name("X", "=UI!$D$1")

    ws.write_formula("A1", "=X")

    wb.close()


def test_defined_name_plain_sum_with_metadata() -> None:
    """Plain defined name plus a dynamic array formula (forces metadata.xml).

    Used to test whether the combination of defined names + dynamic array
    metadata triggers Excel warnings.
    """

    path = _mk("test_defined_name_plain_sum_plus_metadata.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    wb.define_name("TwoPlusTwo", "=2+2")
    ws.write_formula("B1", "=TwoPlusTwo")

    ws.write_column("A1", [1, 2, 2, 3, 3, 3])
    ws.write_dynamic_array_formula("C1", "=UNIQUE(A1:A6)")

    wb.close()


def test_defined_name_plain_sum() -> None:
    """A plain defined name with basic arithmetic (should be universally safe)."""

    path = _mk("test_defined_name_plain_sum.xlsx")
    wb = xlsxwriter.Workbook(path)  # no future functions
    ws = wb.add_worksheet("UI")

    wb.define_name("TwoPlusTwo", "=2+2")
    ws.write("A1", "TwoPlusTwo:")
    ws.write_formula("B1", "=TwoPlusTwo")

    wb.close()


def test_dynamic_array_only_simple() -> None:
    """A workbook with a single dynamic array formula and no defined names."""

    path = _mk("test_dynamic_array_only_simple.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    ws.write_column("A1", [1, 2, 2, 3, 3, 3])
    ws.write_dynamic_array_formula("C1", "=UNIQUE(A1:A6)")

    wb.close()


def test_complicated_prefixed_no_future_functions() -> None:
    """Stress test: explicit _xlfn + _xlpm, without use_future_functions.

    Goal: determine whether warnings are triggered by XlsxWriter's
    use_future_functions behavior or by Excel's handling of these features.
    """

    path = _mk("test_complicated_prefixed_no_future_functions.xlsx")
    wb = xlsxwriter.Workbook(path)  # NOT using use_future_functions
    ws = wb.add_worksheet("UI")

    ws.write_column("A1", [1, 2, 2, 3, 3, 3])

    # Defined name: explicit future-function prefix.
    wb.define_name("U", "=_xlfn.UNIQUE(A1:A6)")

    # Call the defined name as a dynamic array formula.
    ws.write_dynamic_array_formula("C1", "=U")

    # Define a LAMBDA, explicitly prefixed (as per docs).
    wb.define_name("ToCelsius", "=_xlfn.LAMBDA(_xlpm.temp, (5/9) * (_xlpm.temp-32))")
    ws.write_dynamic_array_formula("C3", "=ToCelsius(212)")

    wb.close()


def main() -> None:
    test_data_validation_range()

    # Baselines
    test_defined_name_plain_sum()
    test_dynamic_array_only_simple()

    # Defined-name failure modes
    test_defined_name_plain_sum_with_metadata()
    test_defined_name_nested_equals_bad()

    # Future funcs in defined names
    test_defined_name_future_functions_unprefixed()
    test_defined_name_future_functions_prefixed()
    test_defined_name_future_prefixed_with_sheetref()
    test_defined_name_future_prefixed_not_used()
    test_defined_name_future_used_write_formula()

    # Stress
    test_complicated_prefixed_no_future_functions()

    # LET in defined names vs LET in cells
    test_defined_name_let_scalar()
    test_defined_name_points_to_cell_with_let()

    print(f"Wrote tests to: {OUT_DIR}")


if __name__ == "__main__":
    main()
