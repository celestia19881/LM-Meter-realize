> ⚡ **Note**: We will keep this section updated with common build errors and troubleshooting tips. Stay tuned for updates!

## Common Build & Runtime Errors

### 1. ADB device not detected

**Symptom:** `adb devices` returns an empty list or `unauthorized`.

**Fix (Linux):**
```bash
# Restart the ADB server with root (may be needed on some Linux distros)
sudo adb kill-server
sudo adb start-server
adb devices
```

If the device shows `unauthorized`, unlock the Android device and tap **Allow** on the
"Allow USB Debugging" dialog.

For wireless ADB (Android 11+):
```bash
# On device: Settings → Developer options → Wireless debugging → Enable
# Then pair and connect:
adb pair <DEVICE_IP>:<PAIR_PORT>
adb connect <DEVICE_IP>:5555
```

---

### 2. Rust cross-compilation fails (aarch64-linux-android target missing)

**Symptom:** `error[E0463]: can't find crate for 'std'` or `linker not found`.

**Fix:**
```bash
rustup target add --toolchain 1.75.0 aarch64-linux-android
rustup override set 1.75.0
```

Also verify that `TVM_NDK_CC` points to the correct clang for Linux:
```bash
echo $TVM_NDK_CC
# Should be: $HOME/android-sdk/ndk/27.0.11718014/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang
```

---

### 3. Java version mismatch (wrong JDK in PATH)

**Symptom:** `Unsupported class file major version` or Gradle build fails.

**Fix (Linux):**
```bash
sudo update-alternatives --config java
# Select the Java 17 entry, then:
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
java -version   # should report 17.x.x
```

---

### 4. Conda environment creation fails (solver timeout / channel errors)

**Symptom:** `conda env create` hangs or reports `PackagesNotFoundError`.

**Fix:**
```bash
conda config --add channels conda-forge
conda config --set channel_priority flexible
conda update -n base conda
# Retry with the libmamba solver (faster)
conda install -n base conda-libmamba-solver
conda config --set solver libmamba
conda env create -f environment/conda-linux-x86_64-infer.yaml
```

---

### 5. `mlc-llm` or `mlc-ai` pip install fails on Linux

**Symptom:** `ERROR: No matching distribution found for mlc-llm-nightly-cu122`.

**Fix:** Choose the wheel matching your CUDA version:
```bash
# Check your CUDA version
nvcc --version
# Or:
nvidia-smi

# For CUDA 11.8:
pip install mlc-llm-nightly-cu118 mlc-ai-nightly-cu118
# For CPU-only (no GPU):
pip install mlc-llm-nightly-cpu mlc-ai-nightly-cpu
```

---

### 6. Build script (`build_all_e2e_*.sh`) exits with "no device connected"

**Symptom:** Script errors out at the APK deployment step.

**Fix:** Ensure a device is connected **before** running the build script:
```bash
adb devices            # must list at least one device
conda activate lm-meter-infer
bash scripts/build_all_e2e_pure.sh
```

---

### 7. No trace files produced after running the app

**Symptom:** `option2_stream_logcats_and_pull_traces.sh` reports "No trace files found".

**Possible causes & fixes:**
- Kernel-level profiling is disabled in the app → Enable it in the app settings.
- Trace files are saved to a different path → Use `-t /sdcard/` or check the app log for the actual path.
- Insufficient storage on device → Free up space with `adb shell df -h`.

---

### 8. Jupyter notebook fails to load `tvm_mlc.log` or `trace_*.json`

**Symptom:** `FileNotFoundError` in `test/quick_start.ipynb`.

**Fix:** Update the path variables at the top of the notebook to point to your
actual experiment directory, e.g.:
```python
LOG_FILE   = "output/option2_20250101_120000/tvm_mlc.log"
TRACES_DIR = "output/option2_20250101_120000/traces"
```
