"""
META sheet writer.

The META sheet records build metadata so every workbook snapshot is reproducible.
Fields:
- refreshed_at: UTC timestamp of workbook generation
- base_year: Base salary year (e.g., 2025)
- as_of_date: As-of date for the snapshot
- exporter_git_sha: Git commit SHA of the exporter
- validation_status: PASS or FAILED
- validation_errors: Error messages if validation failed

If validation fails, a prominent "FAILED" banner is displayed.
"""

from __future__ import annotations

from typing import Any

from xlsxwriter.worksheet import Worksheet


# Layout constants
COL_LABEL = 0
COL_VALUE = 1
BANNER_START_ROW = 0
FIELDS_START_ROW = 3


def write_meta_sheet(
    worksheet: Worksheet,
    formats: dict[str, Any],
    build_meta: dict[str, Any],
) -> None:
    """
    Write the META sheet with build metadata.

    The sheet includes:
    - A prominent validation status banner (PASS or FAILED)
    - Key-value pairs for metadata fields
    - Error details if validation failed

    Args:
        worksheet: The META worksheet
        formats: Standard format dict from xlsx.create_standard_formats()
        build_meta: Build metadata dict containing:
            - refreshed_at (str): ISO timestamp
            - base_year (int): Base salary year
            - as_of_date (str): ISO date
            - exporter_git_sha (str): Git commit SHA
            - validation_status (str): "PASS" or "FAILED"
            - validation_errors (list[str]): Error messages
    """
    validation_status = build_meta.get("validation_status", "UNKNOWN")
    validation_errors = build_meta.get("validation_errors", [])

    # Set column widths for readability
    worksheet.set_column(COL_LABEL, COL_LABEL, 22)  # Label column
    worksheet.set_column(COL_VALUE, COL_VALUE, 60)  # Value column

    # === Validation status banner ===
    # This is the most important visual element - analysts should see status immediately
    if validation_status == "PASS":
        worksheet.write(BANNER_START_ROW, COL_LABEL, "✓ VALIDATION PASSED", formats["alert_ok"])
        worksheet.write(BANNER_START_ROW, COL_VALUE, "", formats["alert_ok"])
    else:
        # FAILED banner - highly visible
        worksheet.write(BANNER_START_ROW, COL_LABEL, "✗ VALIDATION FAILED", formats["alert_fail"])
        worksheet.write(BANNER_START_ROW, COL_VALUE, "Do not trust these numbers!", formats["alert_fail"])

    # === Metadata fields ===
    row = FIELDS_START_ROW

    # refreshed_at
    worksheet.write(row, COL_LABEL, "refreshed_at")
    worksheet.write(row, COL_VALUE, build_meta.get("refreshed_at", ""))
    row += 1

    # base_year
    worksheet.write(row, COL_LABEL, "base_year")
    worksheet.write(row, COL_VALUE, build_meta.get("base_year", ""))
    row += 1

    # as_of_date
    worksheet.write(row, COL_LABEL, "as_of_date")
    worksheet.write(row, COL_VALUE, build_meta.get("as_of_date", ""))
    row += 1

    # exporter_git_sha
    worksheet.write(row, COL_LABEL, "exporter_git_sha")
    worksheet.write(row, COL_VALUE, build_meta.get("exporter_git_sha", ""))
    row += 1

    # validation_status
    worksheet.write(row, COL_LABEL, "validation_status")
    if validation_status == "PASS":
        worksheet.write(row, COL_VALUE, "PASS", formats["alert_ok"])
    else:
        worksheet.write(row, COL_VALUE, "FAILED", formats["alert_fail"])
    row += 1

    # === Validation errors (if any) ===
    if validation_status != "PASS" and validation_errors:
        row += 1  # Blank row
        worksheet.write(row, COL_LABEL, "Validation Errors:", formats["header"])
        row += 1

        for error in validation_errors:
            # Truncate long error messages and wrap if needed
            error_text = str(error)[:1000] if error else ""
            worksheet.write(row, COL_LABEL, error_text)
            row += 1
