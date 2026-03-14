# Run and Evaluate LM-Meter

This guide walks through running LM-Meter on an Android target device from a Linux host machine and evaluating the profiled results.

## Prerequisites

- Completed [Installation](install.md) (including Linux setup if applicable)
- Android device with USB Debugging enabled, connected via ADB
- Conda environment activated (`lm-meter-infer` or `lm-meter-kernel`)

---

## 1. Verify Device Connection

```bash
adb devices
# Expected output:
# List of devices attached
# XXXXXXXX  device
```

If no device appears, check USB cable / wireless ADB connection and ensure USB Debugging is enabled.

---

## 2. Launch LM-Meter on the Android Device

1. Install the APK (built by `build_all_e2e_pure.sh` or `build_all_e2e_plus_opencl_kernel.sh`).
2. Open the **LM-Meter** app on the device.
3. Select a model (e.g., `Llama-3.2-3B-Instruct`, `Gemma-2-2B-it`).
4. Choose the profiling mode (**phase-level** or **kernel-level**).

---

## 3. Collect Latency Data

Run the data collection script from your **host machine** (Linux server):

```bash
conda activate lm-meter-infer      # or lm-meter-kernel for kernel-level
bash scripts/data_relavant/option2_stream_logcats_and_pull_traces.sh
```

The script will:

| Step | Action |
|------|--------|
| 1 | Remove old traces from the device |
| 2 | Clear logcat buffers |
| 3 | Begin streaming runtime logs (`TVM_RUNTIME`, `MLC_Profile`, `MLC_EVENT`) |
| 4 | Wait while you run inference on the device |
| 5 | Pull `trace_*.json` files from the device once you press **Ctrl-C** |
| 6 | Save everything under `output/option2_<timestamp>/` |

After the run, you should see:

```
output/option2_20250101_120000/
├── tvm_mlc.log          # Phase-level runtime logs
└── traces/
    ├── trace_001.json   # Kernel-level Perfetto trace (if kernel profiling)
    └── trace_002.json
```

---

## 4. Post-Process and Evaluate Results

Use the interactive Jupyter notebook for detailed analysis:

```bash
conda activate lm-meter-infer
jupyter lab test/quick_start.ipynb
```

The notebook:

- Parses `tvm_mlc.log` to extract **phase-level** latencies  
  (Embedding, Prefill, Decode, Softmax, CopyProbsToCPU, Sampling)
- Parses `trace_*.json` to extract **kernel-level** latencies
- Computes profiling accuracy **α (%)** and normalised error **ε★ (μs/ms)**
- Generates tables and plots matching those in the paper

---

## 5. Accuracy Metrics

LM-Meter reports two metrics per phase/kernel:

| Metric | Formula | Interpretation |
|--------|---------|----------------|
| **α (%)** | `100 × (1 − |T_profiled − T_gt| / T_gt)` | Higher is better (>95 % is excellent) |
| **ε★ (μs/ms)** | `\|T_profiled − T_gt\| / T_gt × 1000` | Lower is better |

where `T_profiled` is the LM-Meter measurement and `T_gt` is the ground-truth measurement.

---

## 6. Profiling Modes

### Phase-Level Profiling

Measures end-to-end latency of each high-level inference phase:

```bash
conda activate lm-meter-infer
bash scripts/data_relavant/option2_stream_logcats_and_pull_traces.sh
```

Produces `tvm_mlc.log` with entries like:

```
MLC_Profile: phase=Prefill  latency_ms=3433.86
MLC_Profile: phase=Decode   latency_ms=62.57
```

### Kernel-Level Profiling

Measures individual GPU kernel execution times (requires `lm-meter-kernel` build):

```bash
conda activate lm-meter-kernel
bash scripts/data_relavant/option2_stream_logcats_and_pull_traces.sh
```

Produces both `tvm_mlc.log` **and** `trace_*.json` files.

---

## 7. Expected Results

Refer to the paper [Section 4.2 & 4.3] for ground-truth measurements. The published phase-level results for **Llama-3.2-3B-Instruct** on a Google Pixel 8 Pro are:

| Phase | LM-Meter (ms) | GT (ms) | α (%) |
|-------|--------------|---------|-------|
| Embedding | 0.8038 | 0.7763 | 96.46 |
| Prefill | 3433.8628 | 3433.8142 | 99.99 |
| Decode | 62.5669 | 62.5303 | 99.94 |
| Softmax | 142.6166 | 142.6542 | 99.97 |
| End-to-end | 3640.4104 | 3640.3191 | 99.99 |

---

## 8. Troubleshooting

See [docs/common-errors.md](common-errors.md) for common build and runtime errors.
