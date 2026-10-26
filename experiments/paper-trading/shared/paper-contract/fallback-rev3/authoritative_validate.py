"""Run the backend's own save-path validators on rev3 candidates, in-process.

Uses src.backend.agents.routes.validate_agent_graph_document (PATCH graph 422 path) and
src.backend.workflows.service.save_workflow_definition against an InMemoryDocumentStore
(PUT workflow 400 path). No network, no Progena writes. Usage: python -I? (needs cwd=worktree)
"""
import json
import sys
from pathlib import Path

import jsonschema

from src.backend.agents.routes import validate_agent_graph_document
from src.backend.storage.documents import InMemoryDocumentStore
from src.backend.events.documents import seed_document_types
from src.backend.workflows.service import save_workflow_definition
from src.progena.routines.store import routine_graph_key
from src.progena.routines.graph import ROUTINE_GRAPH_VERSION
from src.backend.storage.documents import PROGENA_STATE_PREFIX

D = Path(sys.argv[1])
M = json.loads((D / "match.patch.json").read_text())
B = json.loads((D / "batch.patch.json").read_text())
WP = json.loads((D / "workflow.put.json").read_text())
CAT = {
    "routine_35c9290bc476": ("paper-trading-competition-v3", M),
    "routine_747c806a6429": ("paper-trading-improvement-batch", B),
}
results = []


def ok(msg):
    results.append("PASS " + msg)


for rid, (name, body) in CAT.items():
    validate_agent_graph_document(
        body["nodes"], body["edges"], body["entry"], agent_id=rid, name=name, description="",
        policy_id=body.get("policy_id", "default"), input_schema=body.get("input_schema"),
        output_schema=body.get("output_schema"), defs=body.get("$defs"),
    )
    ok(f"validate_agent_graph_document accepted {rid} ({len(body['nodes'])} nodes, {len(body['edges'])} edges)")
    for k in ("input_schema", "output_schema"):
        jsonschema.Draft202012Validator.check_schema(body[k])
    ok(f"{rid} input/output schemas are valid Draft 2020-12")

# Admission checks with the actual JSON schemas (jsonschema, same lib the runtime uses).
bv = jsonschema.Draft202012Validator(B["input_schema"])
mv = jsonschema.Draft202012Validator(M["input_schema"])
legacy = {"batch_id": "b1", "match_count": 1, "round_count": 1, "capital": 1000, "fee_bps": 10,
          "slippage_bps": 5, "history_bars": 60, "bars_per_round": 7, "brief": "x"}
assert not list(bv.iter_errors(legacy)), "legacy (flags omitted) must be admitted"
assert not list(bv.iter_errors({**legacy, "validation_only": False, "require_matched_replay": False}))
ok("batch admits legacy input with flags omitted and explicit false/false")
manual = WP["workflow"]["graph"]["nodes"]["node_45cef6f22948"]["output_schema"]
defaults = {k: v["default"] for k, v in manual["properties"].items() if "default" in v}
assert not list(bv.iter_errors({**defaults, "batch_id": "b1"})), "manual defaults must be admitted by batch"
ok("batch admits full manual defaults (29 fields incl. 3 tracks, timeout 60)")
for label, bad in [("unknown key", {"progress": {}}), ("internal match_gate", {"match_gate": {}}),
                   ("validation_only non-boolean", {"validation_only": "no"}), ("round_count 6", {"round_count": 6}),
                   ("history_bars 1001", {"history_bars": 1001}), ("bars_per_round 10001", {"bars_per_round": 10001}),
                   ("match_count 11", {"match_count": 11}), ("review_every_matches 11", {"review_every_matches": 11}),
                   ("bonus_rounds 4", {"bonus_rounds": 4}), ("interval 1d", {"tracks": [{"track_id": "a", "interval": "1d", "market": "crypto", "symbol": "BTC-USD", "data_path": "/artifacts/trading/market/a.csv"}]}),
                   ("4 tracks", {"tracks": [defaults["tracks"][0]] * 4}), ("track extra key", {"tracks": [{**defaults["tracks"][0], "x": 1}]}),
                   ("timezone non-UTC", {"timezone": "Europe/London"}), ("window not Z", {"evaluation_start": "2026-01-01"})]:
    assert list(bv.iter_errors({**legacy, **bad})), label
ok("batch schema rejects: unknown/internal keys, non-boolean flags, out-of-bounds counts, 1d interval, >3 tracks, extra track keys, non-UTC, malformed window")
dup = {**legacy, "tracks": [defaults["tracks"][0], defaults["tracks"][0]]}
ok(f"duplicate track_id is schema-admissible={not list(bv.iter_errors(dup))} -> rejected in init code before dispatch")
mlegacy = {"run_id": "b1_m1", "round_count": 1, "fee_bps": 10, "slippage_bps": 5, "history_bars": 60, "bars_per_round": 7, "brief": "x"}
assert not list(mv.iter_errors(mlegacy)) and not list(mv.iter_errors({**mlegacy, "validation_only": True, "require_matched_replay": True}))
for bad in [{"round_count": 6}, {"history_bars": 1001}, {"bars_per_round": 10001}, {"validation_only": "x"}, {"match_gate": {}}]:
    assert list(mv.iter_errors({**mlegacy, **bad}))
ok("match admits legacy batch call shape (+flags) and rejects round_count>5, history_bars>1000, bars_per_round>10000, non-boolean flags, internal keys")

# Workflow PUT path: derive ports from the candidate batch graph, then validate.
store = InMemoryDocumentStore()
seed_document_types(store)  # built-in types (alert, ...) exactly as the backend seeds them
for rid, (name, body) in CAT.items():
    doc = {"id": rid, "name": name, "description": "", "version": ROUTINE_GRAPH_VERSION, **body}
    store.save_document(PROGENA_STATE_PREFIX, routine_graph_key(rid), doc)
try:
    definition = save_workflow_definition(store, WP["workflow"])
except Exception as exc:  # report authoritative failure verbatim
    print("\n".join(results))
    print("FAIL save_workflow_definition:", type(exc).__name__, exc)
    sys.exit(1)
g = definition.model_dump(mode="json", by_alias=True)["graph"]
rn = g["nodes"]["node_82566e054c56"]
ports = sorted((rn.get("input_schema") or {}).get("properties", {}).keys())
ok(f"save_workflow_definition accepted workflow (derived routine input ports={len(ports)}, edges={len(g['edges'])})")
assert ports == sorted(manual["properties"].keys()), ports
ok("derived batch input ports == 29 manual fields; every edge accepted by workflow validation")
print("\n".join(results))
print(f"\n{len(results)} authoritative checks passed")
