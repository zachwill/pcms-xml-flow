#!/usr/bin/env python3
"""
Validate Excel workbook formulas for common XlsxWriter/Mac Excel issues.

This script performs comprehensive XML sanity checks on generated .xlsx files
to catch issues that cause Mac Excel repair dialogs.

Checks performed:
1. LET/LAMBDA variable names must have `_xlpm.` prefix
2. No spill operator (`#`) in defined names
3. (Future) Additional formula validation rules

Usage:
    uv run excel/validate_xlsx_formulas.py shared/capbook.xlsx

Exit codes:
    0 - All checks passed
    1 - Validation errors found
    2 - File not found or other error
"""

from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path


def extract_xml_content(xlsx_path: Path, pattern: str) -> list[tuple[str, str]]:
    """Extract XML content from xlsx file matching a glob pattern.
    
    Returns list of (filename, content) tuples.
    """
    results = []
    with zipfile.ZipFile(xlsx_path, 'r') as zf:
        for name in zf.namelist():
            if pattern == "*" or re.match(pattern.replace("*", ".*"), name):
                try:
                    content = zf.read(name).decode('utf-8')
                    results.append((name, content))
                except UnicodeDecodeError:
                    pass  # Skip binary files
    return results


def find_bare_let_lambda_variables(xml_content: str) -> list[dict]:
    """Find LET/LAMBDA variables missing the _xlpm. prefix.
    
    This validates ALL variables, not just the first one.
    
    LET syntax: LET(var1, expr1, var2, expr2, ..., result_expr)
    LAMBDA syntax: LAMBDA(param1, param2, ..., body_expr)
    
    Returns list of dicts with:
        - function: 'LET' or 'LAMBDA'
        - variable: the bare variable name
        - context: surrounding text for debugging
    """
    issues = []
    
    # Pattern to find LET( or LAMBDA( (case insensitive, may have _xlfn. prefix)
    # We need to parse the arguments to find variable names
    
    # First, find all LET/LAMBDA expressions
    # XlsxWriter writes _xlfn.LET or _xlfn._xlws.LET etc.
    let_pattern = r'(?:_xlfn\.(?:_xlws\.)?)?LET\s*\('
    lambda_pattern = r'(?:_xlfn\.(?:_xlws\.)?)?LAMBDA\s*\('
    
    # For LET: variables are at positions 0, 2, 4, ... (even positions) before the final result
    # LET(var1, val1, var2, val2, ..., result)
    # We need to parse carefully because values can contain nested parentheses
    
    for match in re.finditer(let_pattern, xml_content, re.IGNORECASE):
        start = match.end()
        # Parse the arguments
        args = _parse_function_args(xml_content, start)
        if args is None:
            continue
        
        # LET has pairs (var, value) with final result
        # Variables are at even indices: 0, 2, 4, ... up to len-2
        # (last element is the result expression)
        if len(args) >= 3:  # Minimum: var, value, result
            for i in range(0, len(args) - 1, 2):
                var = args[i].strip()
                if _is_bare_variable(var):
                    context_start = max(0, match.start() - 20)
                    context_end = min(len(xml_content), match.end() + 100)
                    issues.append({
                        'function': 'LET',
                        'variable': var,
                        'context': xml_content[context_start:context_end]
                    })
    
    for match in re.finditer(lambda_pattern, xml_content, re.IGNORECASE):
        start = match.end()
        # Parse the arguments
        args = _parse_function_args(xml_content, start)
        if args is None:
            continue
        
        # LAMBDA: all args except the last are parameters
        if len(args) >= 2:  # Minimum: param, body
            for i in range(len(args) - 1):
                var = args[i].strip()
                if _is_bare_variable(var):
                    context_start = max(0, match.start() - 20)
                    context_end = min(len(xml_content), match.end() + 100)
                    issues.append({
                        'function': 'LAMBDA',
                        'variable': var,
                        'context': xml_content[context_start:context_end]
                    })
    
    return issues


def _parse_function_args(xml_content: str, start: int) -> list[str] | None:
    """Parse function arguments starting after the opening parenthesis.
    
    Handles nested parentheses and quoted strings.
    Returns list of argument strings, or None if parsing fails.
    """
    args = []
    current_arg = []
    depth = 1  # We're inside the opening paren
    i = start
    in_string = False
    
    while i < len(xml_content) and depth > 0:
        ch = xml_content[i]
        
        if ch == '"' and (i == 0 or xml_content[i-1] != '\\'):
            in_string = not in_string
            current_arg.append(ch)
        elif in_string:
            current_arg.append(ch)
        elif ch == '(':
            depth += 1
            current_arg.append(ch)
        elif ch == ')':
            depth -= 1
            if depth == 0:
                # End of function
                if current_arg:
                    args.append(''.join(current_arg))
            else:
                current_arg.append(ch)
        elif ch == ',' and depth == 1:
            # Argument separator at top level
            args.append(''.join(current_arg))
            current_arg = []
        else:
            current_arg.append(ch)
        
        i += 1
        
        # Safety limit
        if i - start > 50000:
            return None
    
    return args if depth == 0 else None


def _is_bare_variable(arg: str) -> bool:
    """Check if an argument is a bare variable name (missing _xlpm. prefix).
    
    A variable name in LET/LAMBDA:
    - Is a simple identifier (letters, numbers, underscores, periods)
    - Should NOT start with _xlpm. if it's properly prefixed
    - Should NOT be a cell reference (like A1, $B$2)
    - Should NOT be a number
    - Should NOT be a string literal
    - Should NOT contain operators or special chars
    """
    arg = arg.strip()
    
    # Empty or whitespace
    if not arg:
        return False
    
    # Already prefixed
    if arg.startswith('_xlpm.'):
        return False
    
    # String literal
    if arg.startswith('"') or arg.startswith("'"):
        return False
    
    # Number
    if re.match(r'^-?[\d.]+$', arg):
        return False
    
    # Cell reference (A1, $B$2, Sheet!A1, etc.)
    if re.match(r'^[\$]?[A-Za-z]+[\$]?\d+$', arg):
        return False
    if re.match(r"^'?[^'!]+'\!?[\$]?[A-Za-z]+[\$]?\d+", arg):
        return False
    
    # Range reference
    if re.match(r'^[\$]?[A-Za-z]+[\$]?\d+:[\$]?[A-Za-z]+[\$]?\d+$', arg):
        return False
    
    # Named range or table reference (contains [ or :)
    if '[' in arg or ':' in arg:
        return False
    
    # Contains operators or parens (it's an expression, not a variable)
    if re.search(r'[+\-*/^&<>=()!]', arg):
        return False
    
    # Must be a simple identifier to be a variable
    # Variable names can contain letters, numbers, underscores, and periods
    # But they shouldn't start with a number
    if not re.match(r'^[A-Za-z_][A-Za-z0-9_.]*$', arg):
        return False
    
    # Check for reserved function names (not variables)
    reserved_functions = {
        'TRUE', 'FALSE', 'IF', 'AND', 'OR', 'NOT', 'SUM', 'AVERAGE',
        'COUNT', 'MAX', 'MIN', 'IFERROR', 'IFNA', 'CHOOSE', 'SWITCH',
        'FILTER', 'SORT', 'SORTBY', 'UNIQUE', 'TAKE', 'DROP',
        'XLOOKUP', 'XMATCH', 'INDEX', 'MATCH', 'VLOOKUP', 'HLOOKUP',
        'SUMIF', 'SUMIFS', 'COUNTIF', 'COUNTIFS', 'AVERAGEIF', 'AVERAGEIFS',
        'ROWS', 'COLUMNS', 'ROW', 'COLUMN', 'INDIRECT', 'OFFSET',
        'TEXT', 'VALUE', 'LEFT', 'RIGHT', 'MID', 'LEN', 'TRIM',
        'UPPER', 'LOWER', 'PROPER', 'CONCAT', 'CONCATENATE', 'TEXTJOIN',
        'TODAY', 'NOW', 'YEAR', 'MONTH', 'DAY', 'DATE', 'DATEVALUE',
        'ROUND', 'ROUNDUP', 'ROUNDDOWN', 'INT', 'MOD', 'ABS',
        'COUNTA', 'COUNTBLANK', 'ISBLANK', 'ISERROR', 'ISNA', 'ISNUMBER', 'ISTEXT',
        'SUBTOTAL', 'AGGREGATE', 'SUMPRODUCT',
        'ANCHORARRAY', 'SEQUENCE', 'RANDARRAY',
        'CHOOSECOLS', 'CHOOSEROWS', 'VSTACK', 'HSTACK',
        'NA', 'N', 'T',
    }
    if arg.upper() in reserved_functions:
        return False
    
    # It's a bare variable!
    return True


def find_spill_refs_in_defined_names(xml_content: str) -> list[dict]:
    """Find spill operator (#) in defined names, which causes Excel repair issues.
    
    Returns list of dicts with:
        - name: the defined name
        - context: the full definition
    """
    issues = []
    
    # Pattern for definedName elements
    pattern = r'<definedName[^>]*name="([^"]*)"[^>]*>([^<]*)</definedName>'
    
    for match in re.finditer(pattern, xml_content):
        name = match.group(1)
        value = match.group(2)
        
        if '#' in value:
            issues.append({
                'name': name,
                'context': match.group(0)
            })
    
    return issues


def validate_xlsx(xlsx_path: Path) -> dict:
    """Run all validation checks on an xlsx file.
    
    Returns dict with:
        - passed: bool
        - let_lambda_issues: list
        - spill_ref_issues: list
        - error: optional error message
    """
    result = {
        'passed': True,
        'let_lambda_issues': [],
        'spill_ref_issues': [],
        'error': None
    }
    
    if not xlsx_path.exists():
        result['passed'] = False
        result['error'] = f"File not found: {xlsx_path}"
        return result
    
    try:
        # Check worksheets for LET/LAMBDA issues
        worksheets = extract_xml_content(xlsx_path, r'xl/worksheets/.*\.xml')
        for filename, content in worksheets:
            issues = find_bare_let_lambda_variables(content)
            for issue in issues:
                issue['file'] = filename
                result['let_lambda_issues'].append(issue)
        
        # Check workbook.xml for spill refs in defined names
        workbook_files = extract_xml_content(xlsx_path, r'xl/workbook\.xml')
        for filename, content in workbook_files:
            issues = find_spill_refs_in_defined_names(content)
            for issue in issues:
                issue['file'] = filename
                result['spill_ref_issues'].append(issue)
        
        if result['let_lambda_issues'] or result['spill_ref_issues']:
            result['passed'] = False
            
    except Exception as e:
        result['passed'] = False
        result['error'] = str(e)
    
    return result


def main():
    """CLI entrypoint."""
    if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help'):
        print("Usage: uv run excel/validate_xlsx_formulas.py <path-to-xlsx>")
        print()
        print("Validates Excel workbook formulas for common XlsxWriter/Mac Excel issues:")
        print("  - LET/LAMBDA variable names must have '_xlpm.' prefix")
        print("  - No spill operator ('#') in defined names")
        print()
        print("Example:")
        print("  uv run excel/validate_xlsx_formulas.py shared/capbook.xlsx")
        sys.exit(0 if sys.argv[1:] and sys.argv[1] in ('-h', '--help') else 2)
    
    xlsx_path = Path(sys.argv[1])
    result = validate_xlsx(xlsx_path)
    
    if result['error']:
        print(f"❌ Error: {result['error']}")
        sys.exit(2)
    
    # Report LET/LAMBDA issues
    if result['let_lambda_issues']:
        print(f"❌ Found {len(result['let_lambda_issues'])} bare LET/LAMBDA variable(s) (missing _xlpm. prefix):")
        print()
        
        # Group by file
        by_file: dict[str, list] = {}
        for issue in result['let_lambda_issues']:
            file = issue['file']
            if file not in by_file:
                by_file[file] = []
            by_file[file].append(issue)
        
        for file, issues in sorted(by_file.items()):
            print(f"  📄 {file}:")
            seen = set()
            for issue in issues:
                key = (issue['function'], issue['variable'])
                if key not in seen:
                    seen.add(key)
                    print(f"     {issue['function']}({issue['variable']}, ...) — variable needs _xlpm.{issue['variable']}")
            print()
    
    # Report spill ref issues
    if result['spill_ref_issues']:
        print(f"❌ Found {len(result['spill_ref_issues'])} spill operator (#) in defined name(s):")
        print()
        for issue in result['spill_ref_issues']:
            print(f"  📄 {issue['file']}:")
            print(f"     Name: {issue['name']}")
            print()
    
    if result['passed']:
        print("✅ All formula validation checks passed!")
        sys.exit(0)
    else:
        total = len(result['let_lambda_issues']) + len(result['spill_ref_issues'])
        print(f"❌ Validation failed with {total} issue(s)")
        print()
        print("To fix LET/LAMBDA issues, prefix all variable names with '_xlpm.'")
        print("Example: LET(x, 1, x+1) → LET(_xlpm.x, 1, _xlpm.x+1)")
        sys.exit(1)


if __name__ == '__main__':
    main()
