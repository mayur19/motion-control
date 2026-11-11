"""Guard: BadminSense (BADS_CLL, CC BY-NC-ND) data must never enter this public MIT repo.

The license forbids redistribution of derived material and commercial use, so neither the
archive, its extracted section JSON / stroke GIFs, nor files derived from them may be tracked.
Only aggregate findings written as prose belong in docs/external-dataset-evaluation.md.
"""
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Archive / folder names and the dataset's own section naming:
# Gender_Exp_StrokeType_PlayerCode_Section_Device, e.g. Man_High_ForehandKill_Play6_1_1.json
FORBIDDEN_PATH = re.compile(
    r"(?i)(bads_cll|badminsense|(^|/)external-data/|"
    r"(^|/)(man|woman|male|female)_(low|medium|high)_[^/]*\.(json|gif|csv|npz|npy|parquet|pkl))"
)
# Keys that only appear in raw dataset JSON (the docs mention them in prose, never as JSON keys).
FORBIDDEN_JSON_KEY = re.compile(r'"(recordName|actionEval)"\s*:')

SHOULD_BE_IGNORED = [
    "BADS_CLL_OPENACCESS_V1.zip",
    "BADS_CLL_OPENACCESS_V1/Man_High_ForehandKill_Play6_1_1.json",
    "external-data/anything.json",
    "tools/Man_High_ForehandKill_Play6_1_1.json",
    "docs/evidence/Woman_Low_BackhandDrive_Play2_1_1.gif",
]


def tracked_files() -> list[str]:
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True)
    return [p for p in out.stdout.decode().split("\0") if p]


def test_no_external_dataset_paths_are_tracked():
    offenders = [p for p in tracked_files() if FORBIDDEN_PATH.search(p)]
    assert offenders == [], f"BadminSense data must not be committed: {offenders}"


def test_no_tracked_json_contains_raw_dataset_keys():
    offenders = []
    for path in tracked_files():
        if not path.endswith((".json", ".jsonl")):
            continue
        text = (ROOT / path).read_text(encoding="utf-8", errors="ignore")
        if FORBIDDEN_JSON_KEY.search(text):
            offenders.append(path)
    assert offenders == [], f"Files look like raw BadminSense JSON: {offenders}"


def test_gitignore_blocks_dataset_paths():
    result = subprocess.run(
        ["git", "check-ignore", "--no-index", "--stdin", "-z"],
        cwd=ROOT, input="\0".join(SHOULD_BE_IGNORED).encode(), capture_output=True,
    )
    ignored = {p for p in result.stdout.decode().split("\0") if p}
    missing = [p for p in SHOULD_BE_IGNORED if p not in ignored]
    assert missing == [], f".gitignore does not block: {missing}"
