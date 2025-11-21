#!/usr/bin/env python3
import json
import sys
from copy import deepcopy


def main():
    if len(sys.argv) != 2:
        print(
            "usage: trace_inject.py TRACE_JSON < prog.json > prog_spec.json",
            file=sys.stderr,
        )
        sys.exit(1)

    trace_path = sys.argv[1]

    # --- read trace file, strip non-JSON prefix (e.g., printed output) ---
    try:
        with open(trace_path) as f:
            raw = f.read()
    except OSError as e:
        print(f"error: could not read trace file {trace_path}: {e}", file=sys.stderr)
        sys.exit(1)

    first_brace = raw.find("{")
    if first_brace == -1:
        print("error: no JSON object found in trace file", file=sys.stderr)
        print("trace file contents (first 200 chars):", raw[:200], file=sys.stderr)
        sys.exit(1)

    json_text = raw[first_brace:]
    try:
        trace_info = json.loads(json_text)
    except json.JSONDecodeError as e:
        print("error: failed to parse JSON from trace file:", e, file=sys.stderr)
        print("trace file contents (first 200 chars):", json_text[:200], file=sys.stderr)
        sys.exit(1)

    # --- extract trace info ---
    if "func" not in trace_info or "trace" not in trace_info:
        print("error: trace JSON missing 'func' or 'trace' fields", file=sys.stderr)
        sys.exit(1)

    trace_func = trace_info["func"]
    trace_instrs = trace_info["trace"]

    if not isinstance(trace_instrs, list) or len(trace_instrs) == 0:
        print("error: trace JSON has empty or invalid 'trace' list", file=sys.stderr)
        sys.exit(1)

    # --- read original program from stdin ---
    try:
        prog = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print("error: could not parse program JSON from stdin:", e, file=sys.stderr)
        sys.exit(1)

    if "functions" not in prog:
        print("error: program JSON missing 'functions' field", file=sys.stderr)
        sys.exit(1)

    funcs = prog["functions"]
    target = None
    for f in funcs:
        if f.get("name") == trace_func:
            target = f
            break

    if target is None:
        print(f"error: function {trace_func} not found in program", file=sys.stderr)
        sys.exit(1)

    instrs = target.get("instrs", [])
    if not isinstance(instrs, list):
        print("error: function 'instrs' is not a list", file=sys.stderr)
        sys.exit(1)

    # If the first instr is a label, use it as the original entry.
    # Otherwise, synthesize an entry label.
    if instrs and "label" in instrs[0]:
        orig_entry = instrs[0]["label"]
        has_entry_label = True
    else:
        orig_entry = f".{trace_func}_entry"
        has_entry_label = False

    slow_label = orig_entry + "_slow"
    after_label = orig_entry + "_after"

    # 1) Rewrite guards in the trace to bail to the slow path label
    patched_trace = []
    for instr in trace_instrs:
        instr = deepcopy(instr)
        if isinstance(instr, dict) and instr.get("op") == "guard":
            # our tracer used a placeholder label; we override it with slow_label
            instr["labels"] = [slow_label]
        patched_trace.append(instr)

    # 2) Fast path block at original entry
    fast_entry = []
    fast_entry.append({"label": orig_entry})
    fast_entry.append({"op": "speculate"})
    fast_entry.extend(patched_trace)
    fast_entry.append({"op": "commit"})
    fast_entry.append({"op": "jmp", "labels": [after_label]})

    # 3) Slow path: original body
    slow_block = []
    if has_entry_label:
        # Just relabel the existing entry label to slow_label
        for idx, instr in enumerate(instrs):
            instr = deepcopy(instr)
            if idx == 0 and "label" in instr:
                instr["label"] = slow_label
            slow_block.append(instr)
    else:
        # No original entry label: create one for the slow path, then copy body
        slow_block.append({"label": slow_label})
        for instr in instrs:
            slow_block.append(deepcopy(instr))

    # 4) After label (join point)
    after_block = [{"label": after_label}]

    # 5) Replace function body
    target["instrs"] = fast_entry + slow_block + after_block

    # 6) Output modified program
    json.dump(prog, sys.stdout, indent=2)
    # ensure trailing newline for sanity
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
