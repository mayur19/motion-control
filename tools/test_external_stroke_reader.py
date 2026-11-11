"""Synthetic tests for tools/external-stroke-reader.py (TMB-033 external spike).

Every fixture is hand-authored here and written to pytest's tmp_path. No dataset
content is copied, and no fixture file is committed: tools/test_no_external_data.py
forbids tracked JSON that looks like raw dataset JSON.
"""
import hashlib
import importlib.util
import json
import math
import pathlib
import subprocess
import sys
import zipfile

import pytest

SCRIPT = pathlib.Path(__file__).with_name("external-stroke-reader.py")
REPO = SCRIPT.resolve().parent.parent
_spec = importlib.util.spec_from_file_location("external_stroke_reader", SCRIPT)
reader = importlib.util.module_from_spec(_spec)
sys.modules["external_stroke_reader"] = reader
_spec.loader.exec_module(reader)

STEP_MS = 10
WINDOW_MS = 2000


def gyro_profile(t_ms: int) -> float:
    """Angular-speed magnitude: rest 1, prior bump to 12 at 300 ms, main peak 30 at 1000 ms."""
    bump = 11.0 * math.exp(-((t_ms - 300) / 40.0) ** 2)
    if 700 <= t_ms <= 1000:
        main = 29.0 * (t_ms - 700) / 300.0
    elif 1000 < t_ms <= 1200:
        main = 29.0 * (1200 - t_ms) / 200.0
    else:
        main = 0.0
    return 1.0 + bump + main


def stroke(start: int = 10_000, *, record: str = "Man_Low_ForehandKill_Play3_1_2", stroke_type: str = "ForehandKill",
           times: list | None = None, gyro_scale: float = 1.0, accel_value: float = 9.8) -> dict:
    offsets = times if times is not None else list(range(0, WINDOW_MS, STEP_MS))
    ts = [start + o for o in offsets]
    mags = [gyro_profile(o) * gyro_scale for o in offsets]
    return {
        "info": {"recordName": record, "gender": "Man", "exp": "Low", "section": 1, "device": "2",
                 "startTimestamp": start, "endTimestamp": start + WINDOW_MS},
        "label": {"positionX": 0.1, "positionY": 0.5, "actionType": stroke_type, "actionEval": [3, 3, 3, 3, 3, 3, 3]},
        "data": {
            "ACCELEROMETER": {"Gx": [0.0] * len(ts), "Gy": [accel_value] * len(ts), "Gz": [0.0] * len(ts),
                              "timestamp": list(ts)},
            "GYROSCOPE": {"angularSpeedX": mags, "angularSpeedY": [0.0] * len(ts), "angularSpeedZ": [0.0] * len(ts),
                          "timestamp": list(ts)},
            "AUDIO": {"values": [0, 1], "timestamp": [start + 0.0625, start + 0.125]},
        },
    }


def write_section(directory: pathlib.Path, strokes: list[dict], name: str = "Man_Low_ForehandKill_Play3_1_2") -> pathlib.Path:
    folder = directory / name
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{name}.json"
    path.write_text(json.dumps(strokes), encoding="utf-8")
    return path


def test_parses_identifiers_and_preserves_original_values(tmp_path):
    path = write_section(tmp_path, [stroke(), stroke(start=30_000)])
    strokes = reader.read_section(path.read_bytes(), str(path))
    assert len(strokes) == 2
    s = strokes[0]
    assert (s.record_name, s.stroke_type, s.player, s.section, s.device, s.experience) == (
        "Man_Low_ForehandKill_Play3_1_2", "ForehandKill", "Play3", 1, "2", "Low")
    assert (s.start_ms, s.end_ms) == (10_000, 12_000)
    assert s.gyro_t_ms[:3] == (10_000, 10_010, 10_020)
    assert s.gyro_xyz[0] == (pytest.approx(gyro_profile(0)), 0.0, 0.0)
    assert s.accel_xyz[0] == (0.0, 9.8, 0.0)
    assert reader.UNITS == {"timestamp": "ms (relative session clock)", "gyroscope": "rad/s",
                            "accelerometer": "m/s^2 including gravity"}


def test_accepts_the_published_women_prefix(tmp_path):
    name = "Women_Low_BackhandTransition_Play11_1_1"
    path = write_section(tmp_path, [stroke(record=name, stroke_type="BackhandTransition")], name)
    assert reader.read_section(path.read_bytes(), str(path))[0].player == "Play11"


@pytest.mark.parametrize("mutate, message", [
    (lambda s: s["data"].pop("GYROSCOPE"), "missing stream GYROSCOPE"),
    (lambda s: s["data"]["ACCELEROMETER"].pop("Gz"), "ACCELEROMETER missing key Gz"),
    (lambda s: s["data"]["GYROSCOPE"].update(angularSpeedW=[0.0]), "GYROSCOPE unknown key angularSpeedW"),
    (lambda s: s["data"]["GYROSCOPE"]["angularSpeedY"].pop(), "GYROSCOPE length mismatch"),
    (lambda s: s["data"]["GYROSCOPE"]["timestamp"].__setitem__(5, 10_050.5), "GYROSCOPE timestamp not an integer"),
    (lambda s: s["data"]["GYROSCOPE"]["timestamp"].__setitem__(5, 10_040), "GYROSCOPE timestamps not strictly increasing"),
    (lambda s: s["info"].pop("startTimestamp"), "info missing key startTimestamp"),
    (lambda s: s["info"].update(recordName="NotARecordName"), "unexpected recordName"),
    (lambda s: s["label"].pop("actionType"), "label missing key actionType"),
    (lambda s: s["data"]["GYROSCOPE"]["angularSpeedX"].__setitem__(3, "fast"), "GYROSCOPE value not a finite number"),
])
def test_rejects_malformed_strokes(tmp_path, mutate, message):
    bad = stroke()
    mutate(bad)
    path = write_section(tmp_path, [bad])
    with pytest.raises(reader.StrokeFormatError, match=message):
        reader.read_section(path.read_bytes(), str(path))


def placeholder(start: int = 50_000) -> dict:
    """Invalid attempt as published: info kept, label and data null."""
    entry = stroke(start=start)
    return {"info": entry["info"], "label": None, "data": None}


def test_counts_and_skips_published_invalid_placeholders(tmp_path):
    path = write_section(tmp_path, [stroke(), placeholder(), stroke(start=70_000)])
    section = reader.read_section(path.read_bytes(), str(path))
    assert [s.start_ms for s in section] == [10_000, 70_000]
    assert section.placeholders == 1


@pytest.mark.parametrize("label, data", [(None, {}), ({"actionType": "ForehandKill"}, None)])
def test_partially_null_entries_are_still_errors(tmp_path, label, data):
    bad = {**stroke(), "label": label, "data": data}
    path = write_section(tmp_path, [bad])
    with pytest.raises(reader.StrokeFormatError, match="stroke 0"):
        reader.read_section(path.read_bytes(), str(path))


def test_placeholders_are_reported_in_totals(tmp_path):
    write_section(tmp_path / "data", [stroke(), placeholder()])
    out = tmp_path / "report.json"
    assert run_cli(str(tmp_path / "data"), "--json", str(out)).returncode == 0
    totals = json.loads(out.read_text())["totals"]
    assert (totals["strokes"], totals["invalid_placeholders"]) == (1, 1)


@pytest.mark.parametrize("kwargs, message", [
    ({"gyro_scale": 57.2958}, "gyroscope values implausible for rad/s"),
    ({"accel_value": 1.0}, "accelerometer values implausible for m/s"),
])
def test_rejects_values_inconsistent_with_confirmed_units(tmp_path, kwargs, message):
    path = write_section(tmp_path, [stroke(**kwargs)])
    with pytest.raises(reader.UnitsError, match=message):
        reader.read_section(path.read_bytes(), str(path))


def test_descriptive_signals_of_a_synthetic_stroke(tmp_path):
    path = write_section(tmp_path, [stroke()])
    d = reader.describe(reader.read_section(path.read_bytes(), str(path))[0])
    assert d.peak_rad_s == pytest.approx(30.0)
    assert d.peak_offset_ms == 1000
    # 20 % of the peak is 6 rad/s; the main ramp crosses it at about 752 ms (1 + 29*(t-700)/300 = 6).
    assert d.rise_ms == pytest.approx(248, abs=STEP_MS)
    assert d.prior_peak_ratio == pytest.approx(12.0 / 30.0, abs=0.01)
    assert d.median_interval_ms == STEP_MS
    assert (d.gaps_over_limit, d.gyro_saturated, d.accel_saturated) == (0, False, False)


def test_prior_peak_ratio_is_not_floored_by_the_rise_threshold(tmp_path):
    """Without an earlier bump the ratio must reflect the resting level (1/30), not the 20 % rise threshold."""
    s = stroke()
    times = s["data"]["GYROSCOPE"]["timestamp"]
    s["data"]["GYROSCOPE"]["angularSpeedX"] = [gyro_profile(t - 10_000) if t - 10_000 >= 600 else 1.0 for t in times]
    path = write_section(tmp_path, [s])
    d = reader.describe(reader.read_section(path.read_bytes(), str(path))[0])
    assert d.prior_peak_ratio == pytest.approx(1.0 / 30.0, abs=0.01)
    assert d.rise_ms == pytest.approx(248, abs=STEP_MS)


def test_flags_saturation_gaps_and_held_values(tmp_path):
    offsets = [o for o in range(0, WINDOW_MS, STEP_MS) if not 400 <= o < 460]  # a 70 ms gap
    s = stroke(times=offsets)
    gx = s["data"]["GYROSCOPE"]["angularSpeedX"]
    peak = offsets.index(1000)
    gx[peak] = gx[peak + 1] = 40.03
    s["data"]["ACCELEROMETER"]["Gx"][10] = -78.41
    path = write_section(tmp_path, [s])
    d = reader.describe(reader.read_section(path.read_bytes(), str(path))[0])
    assert d.gaps_over_limit == 1
    assert d.max_interval_ms == 70
    assert d.gyro_saturated and d.accel_saturated
    assert d.gyro_held_values >= 1  # the two clipped samples repeat exactly


def test_reads_zip_without_modifying_it(tmp_path):
    src = tmp_path / "src"
    write_section(src, [stroke()], "Man_Low_ForehandKill_Play3_1_2")
    write_section(src, [stroke(record="Woman_High_ForehandHigh_Play7_2_1", stroke_type="ForehandHigh")],
                  "Woman_High_ForehandHigh_Play7_2_1")
    archive = tmp_path / "archive.zip"
    with zipfile.ZipFile(archive, "w") as z:
        for p in sorted(src.rglob("*.json")):
            z.write(p, p.relative_to(src).as_posix())
        z.writestr("Man_Low_ForehandKill_Play3_1_2/Man_Low_ForehandKill_Play3_1_2@0.gif", b"GIF89a")
    before = hashlib.sha256(archive.read_bytes()).hexdigest()
    source = reader.load_source(archive)
    assert [s.stroke_type for s in source.strokes] == ["ForehandKill", "ForehandHigh"]
    assert source.sha256 == before == hashlib.sha256(archive.read_bytes()).hexdigest()
    assert source.section_files == 2


def run_cli(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-I", str(SCRIPT), *args], capture_output=True, text=True)


def test_cli_writes_labeled_aggregate_reports_without_per_stroke_identifiers(tmp_path):
    write_section(tmp_path / "data", [stroke(), stroke(start=30_000)])
    out_json, out_md = tmp_path / "out" / "report.json", tmp_path / "out" / "report.md"
    result = run_cli(str(tmp_path / "data"), "--json", str(out_json), "--markdown", str(out_md))
    assert result.returncode == 0, result.stderr
    report = json.loads(out_json.read_text())
    assert report["category"] == "external/off-domain"
    assert report["adapter"] == {"name": "external-stroke-reader", "version": reader.ADAPTER_VERSION}
    assert report["source"]["dataset_version"] == "1.0 (BADS_CLL_OPENACCESS_V1)"
    assert report["source"]["sha256"] is None  # directory input is not hashed
    assert report["totals"]["strokes"] == 2
    assert report["groups"]["stroke_type"]["ForehandKill"]["strokes"] == 2
    assert "parameters" in report and "limitations" in report
    markdown = out_md.read_text()
    assert markdown.startswith("# EXTERNAL / OFF-DOMAIN")
    assert "false triggers per 10 minutes" in markdown
    for text in (out_json.read_text(), markdown):
        assert "Man_Low_ForehandKill_Play3_1_2" not in text and "actionEval" not in text


def test_cli_refuses_to_write_reports_into_the_public_repository(tmp_path):
    write_section(tmp_path / "data", [stroke()])
    for target in (REPO / "docs" / "evidence" / "external-report.json", REPO / "external-report.md"):
        result = run_cli(str(tmp_path / "data"), "--json" if target.suffix == ".json" else "--markdown", str(target))
        assert result.returncode == 2
        assert "public repository" in result.stderr
        assert not target.exists()


def test_cli_allows_the_git_ignored_external_data_folder():
    assert reader.output_allowed(REPO / "external-data" / "r.json")
    assert not reader.output_allowed(REPO / "tools" / "r.json")


def test_cli_reports_format_errors_with_location(tmp_path):
    bad = stroke()
    bad["data"].pop("GYROSCOPE")
    path = write_section(tmp_path / "data", [stroke(), bad])
    result = run_cli(str(tmp_path / "data"))
    assert result.returncode == 2
    assert f"{path.name} stroke 1" in result.stderr and "missing stream GYROSCOPE" in result.stderr
