# Trace-Based Speculative Optimization for Bril

This project implements a simple trace-based speculative optimizer for [Bril](https://github.com/sampsyo/bril), inspired by tracing JITs. It extends the reference Bril interpreter to record a hot path trace and adds a transformation that injects this trace back into the program as a speculative fast path using the `speculate`, `guard`, and `commit` instructions.

The work was done for CS 6120 Lesson 12: Dynamic Compilers.

## Overview

The pipeline has three main components:

1. **Tracing interpreter (`brili-trace.ts`)**  
   Starts tracing at the beginning of `main`, records executed instructions, converts `br` to `guard`, and emits a linearized trace as JSON.

2. **Trace injector (`trace_inject.py`)**  
   Reads the JSON trace and injects a speculative fast path in front of the original function using Bril's speculation primitives.

3. **Evaluation script (`run_perf.sh`)**  
   Runs the full pipeline on three benchmarks, checks correctness, and measures dynamic instruction counts.

## Evaluation Summary

All three benchmarks (*factors*, *perfect*, *sum-of-cubes*) produced correct output on both traced and untraced inputs. The speculative versions did not reduce dynamic instruction counts and typically introduced small overhead due to guard checks and speculation scaffolding. This is expected for small benchmarks without further trace optimizations.

## Example Workflow

1. Generate a trace:
   ```
   deno run --allow-read brili-trace.ts -t 60 < factors.json > factors_trace.json
   ```

2. Inject the trace:
   ```
   python3 trace_inject.py factors_trace.json < factors.json > factors_spec.json
   ```

3. Run correctness checks:
   ```
   deno run --allow-read brili.ts 60 < factors.json > orig.txt
   deno run --allow-read brili.ts 60 < factors_spec.json > spec.txt
   diff orig.txt spec.txt
   ```

4. Measure performance:
   ```
   deno run --allow-read brili.ts -p 60 < factors.json
   deno run --allow-read brili.ts -p 60 < factors_spec.json
   ```

## Results Table

| Benchmark       | Input | Original Dyn Inst | Spec Dyn Inst | Correct? | Change |
|-----------------|--------|-------------------|----------------|----------|---------|
| factors         | 60     | 72                | 72             | PASS     | 0       |
|                 | 97     | 870               | 881            | PASS     | +11     |
| perfect         | 28     | 58                | 63             | PASS     | +5      |
|                 | 12     | 37                | 67             | PASS     | +30     |
| sum-of-cubes    | 10     | 8                 | 11             | PASS     | +3      |
|                 | 20     | 8                 | 11             | PASS     | +3      |

## Interpretation

The optimization is functionally correct but not performance-enhancing for these workloads. This demonstrates the core trade-off in tracing JITs: speculative paths are only beneficial when the traced region is substantial or further optimized.

