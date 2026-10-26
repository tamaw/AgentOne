from decimal import Decimal, InvalidOperation
from pathlib import Path
import argparse
import csv
import fcntl
import json
import os
import re
import sys
import tempfile
from contextlib import contextmanager

AGENTS = ("agent-one", "agent-two")
PRIVATE_BASE = Path("/app/shell-workspaces/repo-manager/trading")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


def _atomic_write(path: Path, data: str, mode: int):
    if path.exists() and path.is_symlink():
        raise ValueError("symlink not allowed")
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def read_json(path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json_private(path, obj):
    _atomic_write(path, json.dumps(obj, indent=2, sort_keys=True), 0o600)


def write_json_public(path, obj):
    _atomic_write(path, json.dumps(obj, indent=2, sort_keys=True), 0o644)


def write_text_public(path, text):
    _atomic_write(path, text, 0o644)


@contextmanager
def run_lock(run_id):
    PRIVATE_BASE.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(str(PRIVATE_BASE / f"{run_id}.lock"), os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _decimal(v, positive=False, nonnegative=False):
    try:
        d = Decimal(str(v))
    except (InvalidOperation, TypeError, ValueError):
        raise ValueError("invalid decimal")
    if not d.is_finite():
        raise ValueError("invalid decimal")
    if positive and d <= 0:
        raise ValueError("invalid decimal")
    if nonnegative and d < 0:
        raise ValueError("invalid decimal")
    return d


def _int(v, name):
    if isinstance(v, bool) or not isinstance(v, int):
        raise ValueError(f"invalid {name}")
    return v


def _ensure_no_symlink(path: Path):
    cur = path
    while True:
        if cur.is_symlink():
            raise ValueError("symlink not allowed")
        if cur.parent == cur:
            break
        cur = cur.parent


def _safe_abs_under(path_str, root):
    if not isinstance(path_str, str):
        raise ValueError("invalid path")
    p = Path(path_str)
    if ".." in p.parts:
        raise ValueError("path escape")
    if not p.is_absolute():
        raise ValueError("absolute path required")
    _ensure_no_symlink(p)
    r = p.resolve(strict=False)
    if not r.is_relative_to(root.resolve()):
        raise ValueError("path escape")
    return r


def validate_config(cfg):
    if not isinstance(cfg, dict):
        raise ValueError("invalid config")
    required = {"run_id","round_count","common_brief","market_window","evaluation_window","fill_settings","work_period","shared_artifact_root"}
    if set(cfg) != required:
        raise ValueError("invalid config")

    if not isinstance(cfg["run_id"], str) or not RUN_ID_RE.fullmatch(cfg["run_id"]) or cfg["run_id"] in {".",".."}:
        raise ValueError("invalid run_id")

    _int(cfg["round_count"], "round_count")
    _int(cfg["work_period"], "work_period")
    if cfg["round_count"] < 1 or not (1 <= cfg["work_period"] <= 840):
        raise ValueError("invalid config")

    if not isinstance(cfg["common_brief"], str) or not cfg["common_brief"].strip():
        raise ValueError("invalid brief")

    mw = cfg["market_window"]
    ew = cfg["evaluation_window"]
    fs = cfg["fill_settings"]

    if not isinstance(mw, dict) or not isinstance(ew, dict) or not isinstance(fs, dict):
        raise ValueError("invalid config")

    if not isinstance(mw.get("symbol"), str) or not mw["symbol"].strip():
        raise ValueError("invalid symbol")

    _safe_abs_under(mw["csv_path"], Path("/shared/market"))
    _safe_abs_under(cfg["shared_artifact_root"], Path("/shared"))

    if _int(ew["start_row"], "start_row") < 0 or _int(ew["bars_per_round"], "bars_per_round") < 2:
        raise ValueError("invalid evaluation_window")

    if fs.get("policy") != "next_close":
        raise ValueError("invalid policy")

    _decimal(fs["fee_bps"], nonnegative=True)
    if _decimal(fs["slippage_bps"], nonnegative=True) >= Decimal("10000"):
        raise ValueError("invalid slippage")
    return cfg


def load_market_csv(path):
    rows = []
    last = None
    with path.open("r", encoding="utf-8", newline="") as f:
        rdr = csv.DictReader(f)
        if not rdr.fieldnames or "close" not in rdr.fieldnames:
            raise ValueError("invalid market header")
        for row in rdr:
            ts = row.get("timestamp") or row.get("date")
            if not ts:
                raise ValueError("invalid market data")
            if last is not None and ts <= last:
                raise ValueError("timestamps not increasing")
            last = ts
            rows.append({"timestamp": ts, "close": str(_decimal(row["close"], positive=True))})
    if not rows:
        raise ValueError("empty market")
    return rows


def _market_csv_write(path, rows):
    if path.exists() and path.is_symlink():
        raise ValueError("symlink not allowed")
    fd, tmp = tempfile.mkstemp(dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["timestamp", "close"])
            w.writeheader()
            w.writerows(rows)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def _paths(run_id):
    root = PRIVATE_BASE / run_id / "private"
    return {"root": root, "state": root / "state.json", "config": root / "config.json"}


def _round_window(cfg, idx):
    start = cfg["evaluation_window"]["start_row"] + idx * (cfg["evaluation_window"]["bars_per_round"] - 1)
    end = start + cfg["evaluation_window"]["bars_per_round"] - 1
    return start, end


def _public_round_dir(cfg, idx):
    return Path(cfg["shared_artifact_root"]).resolve() / cfg["run_id"] / f"round-{idx}"


def _publish_record(public_dir, round_record, evidence_text):
    settlement_json = public_dir / "settlement.json"
    settlement_txt = public_dir / "comparative_evidence.txt"
    write_json_public(settlement_json, round_record)
    write_text_public(settlement_txt, evidence_text)


def prepare(config_path, round_index):
    cfg = validate_config(read_json(Path(config_path)))
    round_index = _int(round_index, "round_index")

    with run_lock(cfg["run_id"]):
        p = _paths(cfg["run_id"])

        if not p["state"].exists():
            if round_index != 0:
                raise ValueError("first round must be 0")
            rows = load_market_csv(_safe_abs_under(cfg["market_window"]["csv_path"], Path("/shared/market")))
            needed = cfg["evaluation_window"]["start_row"] + cfg["round_count"] * (cfg["evaluation_window"]["bars_per_round"] - 1) + 1
            if len(rows) < needed:
                raise ValueError("insufficient market rows")

            PRIVATE_BASE.mkdir(mode=0o700, parents=True, exist_ok=True)
            (PRIVATE_BASE / cfg["run_id"]).mkdir(mode=0o700, parents=True, exist_ok=True)
            p["root"].mkdir(mode=0o700, parents=True, exist_ok=True)
            os.chmod(p["root"], 0o700)

            state = {
                "config": cfg,
                "market_snapshot": rows[:needed],
                "accounts": {a: {"cash": "1000", "position": "0"} for a in AGENTS},
                "results": [],
                "settlements": {},
                "prepared": {},
                "next_round": 0,
                "unverifiable": []
            }
            write_json_private(p["config"], cfg)
            write_json_private(p["state"], state)

        state = read_json(p["state"])
        if state["config"] != cfg:
            raise ValueError("config mismatch")

        if round_index < 0 or round_index >= cfg["round_count"]:
            raise ValueError("round out of range")

        if str(round_index) in state["prepared"]:
            return state["prepared"][str(round_index)]

        if round_index != state["next_round"]:
            raise ValueError("unexpected round")

        public_dir = _public_round_dir(cfg, round_index)
        _ensure_no_symlink(public_dir)
        public_dir.mkdir(mode=0o755, parents=True, exist_ok=True)
        os.chmod(public_dir, 0o755)

        for a in AGENTS:
            d = public_dir / a
            _ensure_no_symlink(d)
            d.mkdir(mode=0o755, parents=True, exist_ok=True)
            os.chmod(d, 0o755)

        market_file = public_dir / "market.csv"
        brief_file = public_dir / "brief.txt"
        _market_csv_write(market_file, state["market_snapshot"])
        write_text_public(brief_file, cfg["common_brief"])

        start, end = _round_window(cfg, round_index)
        market = state["market_snapshot"]
        start_ts = market[start]["timestamp"]
        end_ts = market[end]["timestamp"]
        prior = state["results"][-1]["evidence_text"] if state["results"] else "none"

        submission_lines = []
        for a in AGENTS:
            submission_lines.append(
                f"{a} MUST write {public_dir / a / 'manifest.json'} and {public_dir / a / 'trades.csv'}"
            )

        work_request = (
            f"run_id={cfg['run_id']}\nround={round_index}\n"
            f"decision_timestamp_start={start_ts}\n"
            f"decision_timestamp_end_exclusive={end_ts}\n"
            f"mark_timestamp={end_ts}\n"
            f"symbol={cfg['market_window']['symbol']}\n"
            f"policy=next_close uses row(i+1) close from decision timestamp\n"
            f"initial_capital=1000 carry_forward_accounts={state['accounts']}\n"
            f"work_period_seconds={cfg['work_period']}\n"
            f"fees_bps={cfg['fill_settings']['fee_bps']} slippage_bps={cfg['fill_settings']['slippage_bps']}\n"
            f"market_csv={market_file}\n"
            f"brief_file={brief_file}\n"
            f"public_dir_permissions=755 file_permissions=644\n"
            f"{chr(10).join(submission_lines)}\n"
            f"manifest.json: code_ref(string nonempty), approach(string nonempty), changes(string|list)\n"
            f"trades.csv: decision_time,side,quantity ; side=buy|sell ; header-only valid\n"
            f"end_mark=highest marked equity wins\n"
            f"prior_evidence={prior}\n"
            f"brief={cfg['common_brief']}\n"
            f"paper only, free communication, free self-code changes, short/negative allowed"
        )

        result = {
            "work_request": work_request,
            "private_dir": str(p["root"]),
            "public_dir": str(public_dir),
            "round_index": round_index,
            "config_path": str(p["config"]),
        }

        state["prepared"][str(round_index)] = result
        write_json_private(p["state"], state)
        return result


def _load_submission(peer_dir: Path):
    peer_dir = Path(peer_dir)

    manifest_path = peer_dir / "manifest.json"
    trades_path = peer_dir / "trades.csv"

    _ensure_no_symlink(manifest_path)
    _ensure_no_symlink(trades_path)

    if not manifest_path.is_file():
        raise ValueError("manifest.json must be a regular file")
    if not trades_path.is_file():
        raise ValueError("trades.csv must be a regular file")

    manifest = read_json(manifest_path)
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be an object")

    code_ref = manifest.get("code_ref")
    approach = manifest.get("approach")

    if not isinstance(code_ref, str) or not code_ref.strip():
        raise ValueError("manifest.code_ref must be a non-empty string")
    if not isinstance(approach, str) or not approach.strip():
        raise ValueError("manifest.approach must be a non-empty string")

    if "changes" not in manifest:
        raise ValueError("manifest.changes is required")

    changes = manifest["changes"]
    if isinstance(changes, str):
        pass
    elif isinstance(changes, list):
        if not all(isinstance(item, str) for item in changes):
            raise ValueError("manifest.changes list entries must be strings")
    else:
        raise ValueError("manifest.changes must be a string or list of strings")

    trades = []
    with trades_path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            raise ValueError("trades.csv missing header")

        if header != ["decision_time", "side", "quantity"]:
            raise ValueError("trades.csv header must be exactly: decision_time,side,quantity")

        for row_num, row in enumerate(reader, start=2):
            if len(row) != 3:
                raise ValueError(f"invalid row {row_num}")

            decision_time, side, quantity_raw = row

            if side not in ("buy", "sell"):
                raise ValueError(f"invalid side on row {row_num}")

            quantity = _decimal(quantity_raw, positive=True)

            trades.append(
                {
                    "decision_time": decision_time,
                    "side": side,
                    "quantity": str(quantity),
                }
            )

    return manifest, trades


def settle(config_path, round_index, evidence_root):
    cfg = validate_config(read_json(Path(config_path)))
    round_index = _int(round_index, "round_index")

    if round_index < 0 or round_index >= cfg["round_count"]:
        raise ValueError("round index out of range")

    with run_lock(cfg["run_id"]):
        p = _paths(cfg["run_id"])
        state = read_json(p["state"])

        if state["config"] != cfg:
            raise ValueError("config mismatch")

        if str(round_index) in state["settlements"]:
            prepared = state["prepared"].get(str(round_index))
            if prepared is None:
                raise ValueError("round not prepared")

            expected_public = Path(prepared["public_dir"]).resolve()
            supplied = _safe_abs_under(evidence_root, Path("/shared"))
            if supplied != expected_public:
                raise ValueError("evidence root mismatch")

            result = state["settlements"][str(round_index)]
            round_record = state["results"][round_index]
            _publish_record(expected_public, round_record, result["evidence_text"])
            return result

        if str(round_index) not in state["prepared"]:
            raise ValueError("round not prepared")

        if round_index != state["next_round"]:
            raise ValueError("unexpected round")

        prepared = state["prepared"][str(round_index)]

        if prepared["config_path"] != str(config_path):
            raise ValueError("prepared config mismatch")

        if prepared["round_index"] != round_index:
            raise ValueError("prepared round mismatch")

        expected_public = Path(prepared["public_dir"]).resolve()
        supplied = _safe_abs_under(evidence_root, Path("/shared"))
        if supplied != expected_public:
            raise ValueError("evidence root mismatch")

        start, end = _round_window(cfg, round_index)
        market = state["market_snapshot"]

        fee_bps = Decimal(str(cfg["fill_settings"]["fee_bps"]))
        slip_bps = Decimal(str(cfg["fill_settings"]["slippage_bps"]))
        end_close = Decimal(market[end]["close"])

        timestamps = {market[i]["timestamp"]: i for i in range(start, end)}

        round_record = {
            "round_index": round_index,
            "mark_close": str(end_close),
            "agents": {}
        }

        failures = []
        notable_changes = []
        final_balances = {}

        for agent in AGENTS:
            acct = state["accounts"][agent]
            orig_cash = Decimal(acct["cash"])
            orig_pos = Decimal(acct["position"])

            cash = orig_cash
            pos = orig_pos
            verified = True
            fills = []
            manifest_copy = None

            try:
                manifest, trades = _load_submission(expected_public / agent)
                manifest_copy = manifest

                staged_cash = cash
                staged_pos = pos

                for trade in trades:
                    idx = timestamps.get(trade["decision_time"])
                    if idx is None:
                        raise ValueError("decision outside interval")

                    qty = Decimal(trade["quantity"])
                    base_close = Decimal(market[idx + 1]["close"])

                    if trade["side"] == "buy":
                        exec_price = base_close * (Decimal("1") + slip_bps / Decimal("10000"))
                        gross = qty * exec_price
                        fee_amt = abs(gross) * fee_bps / Decimal("10000")
                        staged_cash -= gross + fee_amt
                        staged_pos += qty
                    else:
                        exec_price = base_close * (Decimal("1") - slip_bps / Decimal("10000"))
                        gross = qty * exec_price
                        fee_amt = abs(gross) * fee_bps / Decimal("10000")
                        staged_cash += gross - fee_amt
                        staged_pos -= qty

                    fills.append({
                        "decision_time": trade["decision_time"],
                        "side": trade["side"],
                        "quantity": str(qty),
                        "base_close": str(base_close),
                        "execution_price": str(exec_price),
                        "fee": str(fee_amt)
                    })

                cash = staged_cash
                pos = staged_pos
                state["accounts"][agent] = {"cash": str(cash), "position": str(pos)}

                notable_changes.append({"agent": agent, "changes": manifest["changes"]})

            except (ValueError, OSError, InvalidOperation, KeyError, TypeError) as exc:
                verified = False
                cash = orig_cash
                pos = orig_pos
                fills = []
                failures.append(f"{agent}: {exc}")
                state["unverifiable"].append(f"round {round_index} {agent}: {exc}")

            equity = cash + pos * end_close

            final_balances[agent] = {
                "cash": str(cash),
                "position": str(pos),
                "equity": str(equity)
            }

            round_record["agents"][agent] = {
                "verified": verified,
                "manifest": manifest_copy,
                "fills": fills,
                "balance": final_balances[agent]
            }

        all_failures = []
        all_changes = []
        all_evidence = []

        for rr in state["results"]:
            all_failures.extend(rr.get("failures", []))
            all_changes.extend(rr.get("notable_changes", []))
            all_evidence.extend(rr.get("evidence_paths", []))

        all_failures.extend(failures)
        all_changes.extend(notable_changes)

        settlement_json = expected_public / "settlement.json"
        settlement_txt = expected_public / "comparative_evidence.txt"

        evidence_paths = [str(settlement_json), str(settlement_txt)]
        all_evidence = all_evidence + evidence_paths

        status = "unverifiable" if state["unverifiable"] else (
            "complete" if round_index == cfg["round_count"] - 1 else "running"
        )

        winner = None
        if status == "complete":
            e1 = Decimal(final_balances[AGENTS[0]]["equity"])
            e2 = Decimal(final_balances[AGENTS[1]]["equity"])
            winner = "draw" if e1 == e2 else (AGENTS[0] if e1 > e2 else AGENTS[1])

        evidence_text = (
            f"round={round_index}; "
            f"evidence_paths={evidence_paths}; "
            f"cumulative_failures={all_failures}; "
            f"{AGENTS[0]} cash={final_balances[AGENTS[0]]['cash']} "
            f"pos={final_balances[AGENTS[0]]['position']} "
            f"equity={final_balances[AGENTS[0]]['equity']}; "
            f"{AGENTS[1]} cash={final_balances[AGENTS[1]]['cash']} "
            f"pos={final_balances[AGENTS[1]]['position']} "
            f"equity={final_balances[AGENTS[1]]['equity']}; "
            f"changes={notable_changes}"
        )

        round_record["evidence_paths"] = evidence_paths
        round_record["notable_changes"] = notable_changes
        round_record["evidence_text"] = evidence_text
        round_record["failures"] = failures

        result = {
            "status": status,
            "final_balances": final_balances,
            "winner": winner,
            "round_results": state["results"] + [round_record],
            "evidence_paths": all_evidence,
            "notable_changes": all_changes,
            "failures": all_failures,
            "evidence_text": evidence_text
        }

        state["results"].append(round_record)
        state["settlements"][str(round_index)] = json.loads(json.dumps(result))
        state["next_round"] += 1

        write_json_private(p["state"], state)

        _publish_record(expected_public, round_record, evidence_text)

        return result


def final(config_path):
    cfg = validate_config(read_json(Path(config_path)))

    with run_lock(cfg["run_id"]):
        state = read_json(_paths(cfg["run_id"])["state"])

        if state["config"] != cfg:
            raise ValueError("config mismatch")

        if len(state["results"]) != cfg["round_count"]:
            raise ValueError("competition incomplete")

        if str(cfg["round_count"] - 1) not in state["settlements"]:
            raise ValueError("competition incomplete")

        return state["settlements"][str(cfg["round_count"] - 1)]


def _main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("prepare")
    p.add_argument("config")
    p.add_argument("round_index", type=int)

    s = sub.add_parser("settle")
    s.add_argument("config")
    s.add_argument("round_index", type=int)
    s.add_argument("evidence_root")

    f = sub.add_parser("final")
    f.add_argument("config")

    args = parser.parse_args()

    try:
        if args.cmd == "prepare":
            out = prepare(args.config, args.round_index)
        elif args.cmd == "settle":
            out = settle(args.config, args.round_index, args.evidence_root)
        else:
            out = final(args.config)

        json.dump(out, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0
    except Exception as exc:
        json.dump({"error": str(exc), "type": exc.__class__.__name__}, sys.stderr)
        sys.stderr.write("\n")
        return 1


if __name__ == "__main__":
    sys.exit(_main())
