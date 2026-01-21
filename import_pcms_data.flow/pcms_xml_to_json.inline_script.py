# /// script
# requires-python = ">=3.11"
# dependencies = ["lxml", "orjson", "wmill"]
# ///
import hashlib
import json
import os
import re
import shutil
import zipfile
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Any

import wmill
from lxml import etree
import orjson


DEFAULT_S3_KEY = "pcms/nba_pcms_full_extract.zip"
SHARED_DIR = Path("./shared/pcms")

# ─────────────────────────────────────────────────────────────────────────────
# Cleaning utilities
# ─────────────────────────────────────────────────────────────────────────────

CAMEL_TO_SNAKE_RE = re.compile(r'(?<!^)(?=[A-Z])')

def camel_to_snake(name: str) -> str:
    return CAMEL_TO_SNAKE_RE.sub('_', name).lower()

def dump_json(obj: Any, path: Path):
    path.write_bytes(orjson.dumps(obj, option=orjson.OPT_INDENT_2))

def clean(obj: Any) -> Any:
    """Transform messy XML-parsed data into clean, usable Python dicts."""
    if obj is None:
        return None
    if isinstance(obj, list):
        return [clean(item) for item in obj]
    if isinstance(obj, dict):
        # Handle xsi:nil → None
        if obj.get('@xsi:nil') == 'true' or '@xsi:nil' in obj:
            return None
        # Handle empty objects {} → None (XML elements with no content)
        if len(obj) == 0:
            return None
        result = {}
        for k, v in obj.items():
            # Skip XML metadata attributes
            if k.startswith('@') or k.startswith('?'):
                continue
            result[camel_to_snake(k)] = clean(v)
        return result if result else None
    return obj


# ─────────────────────────────────────────────────────────────────────────────
# XML → Dict conversion using lxml
# ─────────────────────────────────────────────────────────────────────────────

ARRAY_TAGS = frozenset([
    "player", "contract", "version", "salary", "bonus", "trade", "transaction",
    "teamException", "teamExceptionDetail", "draftPick", "twoWayDailyStatus",
    "paymentSchedule", "paymentScheduleDetail", "bonusCriteria",
    "contractProtection", "contractProtectionCondition", "playerServiceYear",
    "protectionType", "teamBudget", "budgetLineItem", "transactionLedgerEntry",
    "waiverPriority", "rookieScaleAmount", "yearlySystemValue",
    "nonContractAmount", "capProjection", "taxRate", "taxTeam", "teamTransaction",
    "yearlySalaryScale", "transactionWaiverAmount",
    # Lookups
    "lkAgency", "lkWApronLevel", "lkBudgetGroup", "lkContractBonusType",
    "lkContractPaymentType", "lkContractType", "lkCriterium", "lkCriteriaOperator",
    "lkDlgExperienceLevel", "lkDlgSalaryLevel", "lkDraftPickConditional",
    "lkEarnedType", "lkExceptionAction", "lkExceptionType", "lkExclusivityStatuses",
    "lkFreeAgentDesignation", "lkFreeAgentStatus", "lkLeague", "lkMaxContract",
    "lkMinContract", "lkModifier", "lkOptionDecision", "lkOption",
    "lkPaymentScheduleType", "lkPersonType", "lkPlayerConsent", "lkPlayerStatus",
    "lkPosition", "lkProtectionCoverage", "lkProtectionType", "lkRecordStatus",
    "lkSalaryOverrideReason", "lkSeasonType", "lkSignedMethod",
    "lkSubjectToApronReason", "lkTradeEntry", "lkTradeRestriction",
    "lkTransactionDescription", "lkTransactionType", "lkTwoWayDailyStatus",
    "lkWithinDay", "lkSchool", "lkTeam",
])


def xml_to_dict(element: etree._Element) -> Any:
    """Convert lxml element to dict, handling arrays and attributes."""
    # Get local tag name (strip namespace)
    tag = etree.QName(element.tag).localname if '}' in element.tag else element.tag
    
    result: dict[str, Any] = {}
    
    # Add attributes (prefixed with @)
    for attr_name, attr_value in element.attrib.items():
        # Clean up namespace prefixes in attribute names
        if '}' in attr_name:
            attr_name = attr_name.split('}')[1]
        result[f'@{attr_name}'] = try_parse_value(attr_value)
    
    # Process children
    children_by_tag: dict[str, list] = {}
    for child in element:
        child_tag = etree.QName(child.tag).localname if '}' in child.tag else child.tag
        if child_tag not in children_by_tag:
            children_by_tag[child_tag] = []
        children_by_tag[child_tag].append(xml_to_dict(child))
    
    # Add children to result
    for child_tag, children in children_by_tag.items():
        if child_tag in ARRAY_TAGS or len(children) > 1:
            result[child_tag] = children
        else:
            result[child_tag] = children[0]
    
    # If no children but has text content
    if not children_by_tag and element.text and element.text.strip():
        text = element.text.strip()
        if result:  # Has attributes
            result['#text'] = try_parse_value(text)
        else:
            return try_parse_value(text)
    
    return result if result else None


def try_parse_value(value: str) -> Any:
    """Try to parse string value to appropriate Python type."""
    if value.lower() == 'true':
        return True
    if value.lower() == 'false':
        return False
    try:
        if '.' in value:
            return float(value)
        return int(value)
    except ValueError:
        return value


def parse_xml_file(filepath: Path) -> dict:
    """Parse XML file to dict using lxml."""
    tree = etree.parse(str(filepath))
    root = tree.getroot()
    tag = etree.QName(root.tag).localname if '}' in root.tag else root.tag
    return {tag: xml_to_dict(root)}


# ─────────────────────────────────────────────────────────────────────────────
# Extraction mappings
# ─────────────────────────────────────────────────────────────────────────────

def safe_get(data: dict, *keys: str) -> Any:
    """Safely navigate nested dict."""
    for key in keys:
        if not isinstance(data, dict):
            return None
        data = data.get(key)
        if data is None:
            return None
    return data


EXTRACT_MAP: dict[str, tuple[str, callable]] = {
    "player": ("players.json", lambda d: safe_get(d, "xml-extract", "player-extract", "player")),
    "contract": ("contracts.json", lambda d: safe_get(d, "xml-extract", "contract-extract", "contract")),
    "transaction": ("transactions.json", lambda d: safe_get(d, "xml-extract", "transaction-extract", "transaction")),
    "ledger": ("ledger.json", lambda d: safe_get(d, "xml-extract", "ledger-extract", "transactionLedgerEntry")),
    "trade": ("trades.json", lambda d: safe_get(d, "xml-extract", "trade-extract", "trade")),
    "dp-extract": ("draft_picks.json", lambda d: safe_get(d, "xml-extract", "dp-extract", "draftPick")),
    "team-exception": ("team_exceptions.json", lambda d: safe_get(d, "xml-extract", "team-exception-extract", "exceptionTeams")),
    "team-budget": ("team_budgets.json", lambda d: {
        "budget_teams": safe_get(d, "xml-extract", "team-budget-extract", "budgetTeams"),
        "tax_teams": safe_get(d, "xml-extract", "team-budget-extract", "taxTeams"),
    }),
    "lookup": ("lookups.json", lambda d: safe_get(d, "xml-extract", "lookups-extract")),
    "cap-projections": ("cap_projections.json", lambda d: safe_get(d, "xml-extract", "cap-projections-extract", "capProjection")),
    "yearly-system-values": ("yearly_system_values.json", lambda d: safe_get(d, "xml-extract", "yearly-system-values-extract", "yearlySystemValue")),
    "nca-extract": ("non_contract_amounts.json", lambda d: safe_get(d, "xml-extract", "nca-extract", "nonContractAmount")),
    "rookie-scale-amounts": ("rookie_scale_amounts.json", lambda d: safe_get(d, "xml-extract", "rookie-scale-amounts-extract", "rookieScaleAmount")),
    "team-tr-extract": ("team_transactions.json", lambda d: safe_get(d, "xml-extract", "tt-extract", "teamTransaction")),
    "tax-rates-extract": ("tax_rates.json", lambda d: safe_get(d, "xml-extract", "tax-rates-extract", "taxRate")),
    "tax-teams-extract": ("tax_teams.json", lambda d: safe_get(d, "xml-extract", "tax-teams-extract", "taxTeam")),
    "transactions-waiver-amounts": ("transaction_waiver_amounts.json", lambda d: safe_get(d, "xml-extract", "twa-extract", "transactionWaiverAmount")),
    "yearly-salary-scales-extract": ("yearly_salary_scales.json", lambda d: safe_get(d, "xml-extract", "yearly-salary-scales-extract", "yearlySalaryScale")),
    "dps": ("draft_pick_summaries.json", lambda d: safe_get(d, "xml-extract", "dps-extract", "draft-pick-summary")),
    "two-way": ("two_way.json", lambda d: {
        "daily_statuses": safe_get(d, "xml-extract", "two-way-extract", "daily-statuses"),
        "player_day_counts": safe_get(d, "xml-extract", "two-way-extract", "player-day-counts"),
        "two_way_seasons": safe_get(d, "xml-extract", "two-way-extract", "two-way-seasons"),
    }),
    "two-way-utility-extract": ("two_way_utility.json", lambda d: safe_get(d, "xml-extract", "two-way-utility-extract")),
    "waiver-priority-extract": ("waiver_priority.json", lambda d: safe_get(d, "xml-extract", "waiver-priority-extract")),
}


# ─────────────────────────────────────────────────────────────────────────────
# Worker function for multiprocessing
# ─────────────────────────────────────────────────────────────────────────────

def process_xml_file(args: tuple[Path, str]) -> tuple[str, str | None, float]:
    """
    Process a single XML file. Returns (key, output_filename or None, elapsed_seconds).
    This runs in a separate process.
    """
    import time
    xml_path, key = args
    
    if key not in EXTRACT_MAP:
        return (key, None, 0.0)
    
    start = time.perf_counter()
    output_file, extractor = EXTRACT_MAP[key]
    
    try:
        parsed = parse_xml_file(xml_path)
        raw_data = extractor(parsed)
        clean_data = clean(raw_data)
        output_path = xml_path.parent / output_file
        dump_json(clean_data, output_path)
        elapsed = time.perf_counter() - start
        return (key, output_file, elapsed)
    except Exception as e:
        elapsed = time.perf_counter() - start
        print(f"  ❌ {key} failed: {e}")
        return (key, None, elapsed)


# ─────────────────────────────────────────────────────────────────────────────
# Main processing
# ─────────────────────────────────────────────────────────────────────────────

def download_extract_and_parse(s3_key: str) -> dict:
    """Download from S3, extract ZIP, parse XML files to JSON."""
    import time
    
    # Clean and create shared directory
    if SHARED_DIR.exists():
        shutil.rmtree(SHARED_DIR)
    SHARED_DIR.mkdir(parents=True, exist_ok=True)
    
    # Download from S3
    print(f"Downloading {s3_key} from S3...")
    s3_obj = {"s3": s3_key}
    data = wmill.load_s3_file(s3_obj)  # Returns bytes directly, no .read() needed
    
    if not data:
        raise RuntimeError(f"Failed to download {s3_key} from S3")
    
    # Compute hash
    file_hash = hashlib.sha256(data).hexdigest()
    print(f"File hash: {file_hash}")
    
    # Write and extract ZIP
    tmp_zip = SHARED_DIR / "extract.zip"
    tmp_zip.write_bytes(data)
    
    print(f"Extracting to {SHARED_DIR}...")
    with zipfile.ZipFile(tmp_zip, 'r') as zf:
        zf.extractall(SHARED_DIR)
    tmp_zip.unlink()
    
    # Find extracted directory
    entries = list(SHARED_DIR.iterdir())
    extract_dir = next((e for e in entries if e.is_dir()), SHARED_DIR)
    
    # List XML files
    xml_files = list(extract_dir.glob("*.xml"))
    print(f"Found {len(xml_files)} XML files")
    
    # Build work items
    work_items = []
    for xml_path in xml_files:
        # Extract key: "nba_pcms_full_extract_player.xml" → "player"
        key = xml_path.stem.replace("nba_pcms_full_extract_", "")
        work_items.append((xml_path, key))
    
    # Process in parallel using multiprocessing
    print(f"Parsing XML files in parallel (multiprocessing)...")
    json_files = []
    
    # Use number of CPUs, but cap at 8 to avoid memory issues
    max_workers = min(os.cpu_count() or 4, 8)
    
    with ProcessPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(process_xml_file, item): item for item in work_items}
        
        for future in as_completed(futures):
            key, output_file, elapsed = future.result()
            if output_file:
                print(f"  ✅ {key} → {output_file} ({elapsed:.1f}s)")
                json_files.append(output_file)
            elif key in EXTRACT_MAP:
                print(f"  ❌ {key} - failed")
            else:
                print(f"  ⏭️  {key} - no mapping")
    
    print(f"Parsed {len(json_files)} clean JSON files")
    
    return {
        "file_hash": file_hash,
        "extract_dir": str(extract_dir),
        "json_files": json_files,
    }


def main(dry_run: bool = False, s3_key: str = DEFAULT_S3_KEY) -> dict:
    from datetime import datetime, timezone
    
    started_at = datetime.now(timezone.utc).isoformat()
    errors = []
    
    try:
        result = download_extract_and_parse(s3_key)
        
        return {
            "dry_run": dry_run,
            "started_at": started_at,
            "finished_at": datetime.now(timezone.utc).isoformat(),
            "s3_key": s3_key,
            "extract_dir": result["extract_dir"],
            "json_files": result["json_files"],
            "file_hash": result["file_hash"],
            "tables": [],
            "errors": [],
        }
    except Exception as e:
        errors.append(str(e))
        return {
            "dry_run": dry_run,
            "started_at": started_at,
            "finished_at": datetime.now(timezone.utc).isoformat(),
            "s3_key": s3_key,
            "extract_dir": str(SHARED_DIR),
            "json_files": [],
            "file_hash": "",
            "tables": [],
            "errors": errors,
        }