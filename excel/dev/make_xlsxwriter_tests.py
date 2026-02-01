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
    """Defined name using LET/FILTER/UNIQUE without explicit _xlfn prefixes."""

    path = _mk("test_defined_name_future_unprefixed.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    ws.write_column("A1", [1, 2, 2, 3, 3, 3])

    # In defined names, XlsxWriter may not auto-prefix future functions.
    wb.define_name("U", "=UNIQUE(A1:A6)")
    ws.write_dynamic_array_formula("C1", "=U")

    wb.close()


def test_defined_name_future_functions_prefixed() -> None:
    """Defined name using explicit _xlfn prefixes (per XlsxWriter lambda example)."""

    path = _mk("test_defined_name_future_prefixed.xlsx")
    wb = xlsxwriter.Workbook(path, {"use_future_functions": True})
    ws = wb.add_worksheet("UI")

    ws.write_column("A1", [1, 2, 2, 3, 3, 3])

    # _xlfn.UNIQUE is the stored form.
    wb.define_name("U", "=_xlfn.UNIQUE(A1:A6)")
    ws.write_dynamic_array_formula("C1", "=U")

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
    test_defined_name_plain_sum()
    test_dynamic_array_only_simple()
    test_defined_name_nested_equals_bad()
    test_defined_name_future_functions_unprefixed()
    test_defined_name_future_functions_prefixed()
    test_complicated_prefixed_no_future_functions()
    print(f"Wrote tests to: {OUT_DIR}")


if __name__ == "__main__":
    main()
