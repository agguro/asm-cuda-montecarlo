# ASM CUDA Monte Carlo Engine

Bare-metal Monte Carlo simulation engine implemented with:

- x86_64 Assembly (System V ABI)
- NVIDIA PTX
- CUDA Driver API

The project performs GPU-accelerated Monte Carlo forecasting using a Geometric Brownian Motion (GBM) model.

The host runtime is written entirely in x86_64 assembly and directly manages:

- file loading
- statistical preprocessing
- GPU orchestration
- result aggregation
- terminal presentation

No high-level runtime or language framework is required.

---

# Overview

The engine estimates future asset price behavior through large-scale stochastic simulation.

Historical ticker data is loaded from a binary file, analyzed on the CPU to derive drift and volatility parameters, then used as input for a GPU Monte Carlo kernel.

Each GPU thread independently simulates many possible future price trajectories.

The simulation outputs:

- expected future average price
- probability of touching a target barrier
- probability of missing the barrier

---

# Architecture

```text
Historical Binary Data
        │
        ▼
x86_64 Assembly Host
        │
        ├── mmap file loading
        ├── drift calculation
        ├── volatility calculation
        ├── CUDA Driver API orchestration
        │
        ▼
NVIDIA PTX Monte Carlo Kernel
        │
        ├── Xorshift64 RNG
        ├── Box-Muller transform
        ├── GBM simulation
        ├── barrier detection
        │
        ▼
GPU Reduction Buffers
        │
        ▼
Assembly Presentation Layer
```

---

# Mathematical Model

The simulation follows Geometric Brownian Motion:

```math
dS = \mu Sdt + \sigma SdW
```

Integrated form:

```math
S(t) =
S_0
\exp
\left(
(\mu - \frac{1}{2}\sigma^2)t
+
\sigma Z \sqrt{t}
\right)
```

where:

```math
Z \sim N(0,1)
```

---

# Features

- Pure x86_64 Assembly host runtime
- PTX-native GPU kernel
- CUDA Driver API integration
- Monte Carlo barrier probability estimation
- Geometric Brownian Motion forecasting
- Zero-copy file loading via `mmap`
- SIMD/SIMT parallel execution
- Register-local GPU computation
- Hardware-accelerated transcendental approximations
- No CUDA C++ runtime dependency

---

# Project Structure

```text
.
├── kernels/
│   └── monte_carlo_kernel.ptx
│
├── src/
│   └── x86_64/
│       └── engine/
│           └── monte_carlo.s
│
├── data/
│   └── ticker binaries
│
├── meson.build
└── README.md
```

---

# Binary Input Format

The historical ticker file consists of fixed 16-byte records:

```text
Offset  Size  Description
0       8     Timestamp
8       8     Price (f64)
```

Total records:

```math
records = filesize / 16
```

The file is mapped directly into process memory using:

```text
mmap()
```

No buffered file parsing occurs.

---

# CPU Analytics Phase

Before GPU execution, the assembly host computes:

---

## Drift

Approximation:

```math
\mu =
\frac{1}{N}
\sum
\left(
\frac{P_{i+1}}{P_i} - 1
\right)
```

---

## Volatility

Variance estimate:

```math
\sigma^2 =
E[X^2] - (E[X])^2
```

Standard deviation:

```math
\sigma = \sqrt{\sigma^2}
```

These values become simulation parameters for the GPU kernel.

---

# GPU Simulation

Each CUDA thread:

1. Initializes RNG state
2. Simulates multiple price trajectories
3. Tracks target barrier hits
4. Accumulates ending prices
5. Writes local results to VRAM

No synchronization occurs between threads.

---

# Random Number Generation

The GPU kernel uses:

```text
Xorshift64
```

for entropy generation.

Normal distribution sampling uses:

```text
Box-Muller transform
```

Transcendental operations use hardware approximations:

```text
lg2.approx
ex2.approx
cos.approx
```

for throughput optimization.

---

# Barrier Logic

The engine supports directional target barriers.

---

## Downward Barrier

If:

```math
target < startPrice
```

a hit occurs when:

```math
S_t \le target
```

---

## Upward Barrier

If:

```math
target > startPrice
```

a hit occurs when:

```math
S_t \ge target
```

---

# Command Line Usage

```bash
./monte_carlo <data.bin> <target> <iters> <horizon>
```

Arguments:

```text
data.bin   Historical ticker binary
target     Barrier target price
iters      Simulations per GPU thread
horizon    Forecast length in days
```

---

# Example

```bash
./monte_carlo btc.bin 125000 1000000 30
```

---

# Output

Example output:

```text
------------------------------------------------------------
SIMULATION SUMMARY (btc.bin)

Historical Drift    : 0.001245
Historical Vol      : 0.042191

Forecast Horizon    : 30 Days
Simulated Paths     : 1000000

Current Price       : 103421.12
Target Price        : 125000.00
Expected Average    : 108772.44

PROBABILITY ANALYSIS:
>> Probability of hitting target: 34.82%
>> Likelihood of missing target : 65.18%
```

---

# ABI Compliance

The host strictly follows the x86_64 System V ABI.

Requirements include:

- 16-byte stack alignment
- correct XMM argument passing
- preserved nonvolatile registers
- proper syscall conventions

The implementation interoperates directly with:

- `printf`
- `strtod`
- `atoll`

through the PLT.

---

# System Calls

The assembly host directly invokes Linux syscalls:

```text
open
fstat
mmap
exit
```

No libc wrappers are used for file handling.

---

# CUDA Integration

The host is designed for CUDA Driver API orchestration.

Responsibilities include:

- module loading
- kernel launch configuration
- VRAM allocation
- kernel execution
- reduction retrieval

The PTX kernel remains fully separable from the host runtime.

---

# Performance Characteristics

Primary optimization goals:

- minimal CPU overhead
- maximal GPU occupancy
- register-local execution
- reduced memory bandwidth usage
- high simulation throughput
- zero-copy historical data loading

The implementation favors throughput over strict numerical precision.

---

# Precision Characteristics

The system mixes:

- IEEE-754 `f64`
- hardware-accelerated `f32` transcendental approximations

This improves GPU execution density while retaining double-precision accumulation.

---

# Historical Regime Analysis

The engine can operate on ticker datasets originating from arbitrary historical periods.

Because drift and volatility are derived directly from the supplied ticker file, the statistical behavior of the simulation becomes conditional on the selected historical regime.

Examples:

- 2008 financial crisis data
- COVID-era volatility
- low-volatility bull markets
- post-halving crypto periods
- recessionary intervals

This allows the engine to perform:

- historical scenario replay
- regime-dependent forecasting
- stress testing
- counterfactual probability analysis
- comparative volatility studies

The simulation therefore reflects the statistical characteristics embedded in the selected historical dataset rather than assuming stationary long-term market behavior.

---

# Build Requirements

Required components:

- Linux x86_64
- NVIDIA GPU (sm_61+)
- CUDA Toolkit
- GNU assembler
- Meson
- Ninja

---

# Build

Release build:

```bash
meson setup build --buildtype=release
ninja -C build
```

Debug build:

```bash
meson setup build --buildtype=debug
ninja -C build
```

---

# Design Goals

Primary objectives:

- direct hardware control
- minimal abstraction layers
- GPU-first statistical simulation
- deterministic runtime structure
- PTX-level execution visibility
- assembly-level host orchestration

---

# Limitations

The implementation does not explicitly guard against:

- invalid market assumptions
- non-stationary volatility
- RNG correlation artifacts
- overflow
- NaN propagation
- market discontinuities

Monte Carlo estimates remain probabilistic rather than deterministic.

---

# License

MIT License.

---
