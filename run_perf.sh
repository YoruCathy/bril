#!/bin/bash
set -e

OUT=results.txt
echo "Trace-based Speculation Evaluation" > "$OUT"
echo "==================================" >> "$OUT"
echo "" >> "$OUT"

run_bench() {
    NAME="$1"   # e.g., factors, perfect, sum-of-cubes
    A="$2"      # training input
    B="$3"      # test input

    JSON="${NAME}.json"
    TRACE="${NAME}_trace.json"
    SPEC="${NAME}_spec.json"

    echo "----------------------------------------" >> "$OUT"
    echo "Benchmark: $NAME" >> "$OUT"
    echo "  Training input A = $A" >> "$OUT"
    echo "  Test input     B = $B" >> "$OUT"
    echo "" >> "$OUT"

    ############################
    # 1. Convert to JSON
    ############################
    bril2json < "benchmarks/core/${NAME}.bril" > "$JSON"

    ############################
    # 2. Generate trace on A
    ############################
    deno run --allow-read brili-trace.ts -t "$A" < "$JSON" > "$TRACE"

    ############################
    # 3. Inject speculative fast path
    ############################
    python3 trace_inject.py "$TRACE" < "$JSON" > "$SPEC"

    ############################
    # 4. Correctness checks
    ############################
    # original outputs
    deno run --allow-read brili.ts "$A" < "$JSON" > "${NAME}_orig_A.txt"
    deno run --allow-read brili.ts "$B" < "$JSON" > "${NAME}_orig_B.txt"

    # speculative outputs
    deno run --allow-read brili.ts "$A" < "$SPEC" > "${NAME}_spec_A.txt"
    deno run --allow-read brili.ts "$B" < "$SPEC" > "${NAME}_spec_B.txt"

    # diffs (don't crash script on mismatch)
    DIFF_A=$(diff "${NAME}_orig_A.txt" "${NAME}_spec_A.txt" || true)
    DIFF_B=$(diff "${NAME}_orig_B.txt" "${NAME}_spec_B.txt" || true)

    echo "Correctness on A ($A):" >> "$OUT"
    if [ -z "$DIFF_A" ]; then
        echo "  PASS" >> "$OUT"
    else
        echo "  FAIL (outputs differ)" >> "$OUT"
        echo "$DIFF_A" | sed 's/^/    /' >> "$OUT"
    fi

    echo "Correctness on B ($B):" >> "$OUT"
    if [ -z "$DIFF_B" ]; then
        echo "  PASS" >> "$OUT"
    else
        echo "  FAIL (outputs differ)" >> "$OUT"
        echo "$DIFF_B" | sed 's/^/    /' >> "$OUT"
    fi
    echo "" >> "$OUT"

    ############################
    # 5. Performance (dyn inst count)
    ############################
    deno run --allow-read brili.ts -p "$A" < "$JSON" 1>/dev/null 2> "${NAME}_perf_orig_A.txt"
    deno run --allow-read brili.ts -p "$B" < "$JSON" 1>/dev/null 2> "${NAME}_perf_orig_B.txt"

    deno run --allow-read brili.ts -p "$A" < "$SPEC" 1>/dev/null 2> "${NAME}_perf_spec_A.txt"
    deno run --allow-read brili.ts -p "$B" < "$SPEC" 1>/dev/null 2> "${NAME}_perf_spec_B.txt"

    O_A=$(grep total_dyn_inst "${NAME}_perf_orig_A.txt" | awk '{print $2}')
    O_B=$(grep total_dyn_inst "${NAME}_perf_orig_B.txt" | awk '{print $2}')
    S_A=$(grep total_dyn_inst "${NAME}_perf_spec_A.txt" | awk '{print $2}')
    S_B=$(grep total_dyn_inst "${NAME}_perf_spec_B.txt" | awk '{print $2}')

    echo "Dynamic Instruction Count:" >> "$OUT"
    echo "  Input A ($A): original=$O_A, spec=$S_A" >> "$OUT"
    echo "  Input B ($B): original=$O_B, spec=$S_B" >> "$OUT"
    echo "" >> "$OUT"
}

###############################################
# Run the three chosen benchmarks
###############################################

# factors.bril : main(n: int)
run_bench factors 60 97

# perfect.bril : main(n: int)  (28 is perfect; 12 is not)
run_bench perfect 28 12

# sum-of-cubes.bril : main(n: int)
run_bench sum-of-cubes 10 20

echo "==================================" >> "$OUT"
echo "Done. Results written to $OUT" >> "$OUT"
echo "=================================="

echo "Finished. See results in results.txt."
