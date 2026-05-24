# KataGo Apple Silicon Roadmap

## Baseline First

KataGo now has a Metal backend in the main repository. The first optimization
step is therefore not a new backend; it is building, benchmarking, and profiling
the existing Metal path on Apple Silicon.

Baseline command shape:

```sh
cmake -S cpp -B build-metal -G Ninja -DUSE_BACKEND=METAL -DCMAKE_BUILD_TYPE=Release
cmake --build build-metal --target katago
./build-metal/katago benchmark -model path/to/model.bin.gz -config path/to/gtp.cfg
```

## Likely Optimization Areas

1. Metal backend dispatch overhead and command-buffer scheduling.
2. Tensor layout conversions between KataGo model format and Metal kernels.
3. Batch sizing for interactive analysis versus throughput benchmarks.
4. FP16 use and memory bandwidth pressure on Apple GPUs.
5. Search thread scheduling across performance and efficiency cores.
6. Reuse of loaded model state and warmed buffers across games.
7. Startup/tuning cache behavior for app-bundled use.

## Fork Strategy

- Keep a clean branch tracking upstream `lightvector/KataGo`.
- Maintain each performance patch as a small topic branch.
- Add benchmarks before large rewrites.
- Separate app integration patches from engine performance patches.
- Prefer patches that can be proposed upstream.

## iOS Reality Check

iOS is the harder target because the app cannot rely on spawning an arbitrary
engine executable the way a macOS GUI can. The iOS path should be designed after
the macOS engine API is proven:

- compile the needed engine subset as a library;
- expose a narrow C/C++ bridge;
- use app sandbox-safe model storage;
- profile thermal behavior and memory pressure on real devices;
- provide smaller default model profiles for phones.

## Benchmark Matrix

Track at least:

- device model and chip;
- macOS/iOS version;
- Xcode and Swift version;
- KataGo commit;
- model name and size;
- backend;
- config;
- visits/playouts per second;
- startup time;
- peak memory;
- thermal behavior for 5, 15, and 30 minute sessions.
