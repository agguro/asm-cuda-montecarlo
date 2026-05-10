# High-Performance Bare-Metal GPU Monte Carlo Engine

A low-level, zero-footprint statistical engine designed for high-speed financial simulations. This project bypasses heavy abstractions like the CUDA Runtime (CUDART) to interact directly with the GPU driver using Linux SysV ABI assembly (x86_64) and pure PTX assembly (NVIDIA Driver API).

## Technical Philosophy

* **Zero-Footprint:** Orchestration is written directly in GNU `as` (x86_64). Heavy-lifting parallel math runs in PTX (NVIDIA Assembly). No bloated high-level libraries.
* **ABI-Proof & Stack Safe:** Built with strict manual 16-byte stack alignment and adherence to the System V AMD64 ABI for drop-in compatibility.
* **Direct Driver Access:** Manually loads `.cubin` modules via the CUDA Driver API (`libcuda`), avoiding standard C startup routines and hidden overhead.

## Mathematics & GPU Pipeline

The engine executes **Geometric Brownian Motion (GBM)** trajectories in parallel.

1. **Entropy:** A thread-safe 64-bit XorShift variant generates uniform random bits entirely in-register.
2. **Box-Muller:** Converts bits to Gaussian samples $Z \sim N(0,1)$ using hardware-accelerated `sqrt`, `log2`, and `cos`.
3. **Trajectory:** Evaluates $S_t = S_0 \exp((\mu - 0.5\sigma^2)t + \sigma Z\sqrt{t})$.
4. **Reduction:** Performs an inner loop of iterations per GPU thread before a single write-back to VRAM, minimizing PCIe bus contention.

## Build & Run

### Requirements
* NVIDIA Driver & `ptxas`
* GNU Assembler (`as`) & `gcc` (for linking)

### Execution
```bash
./monte_carlo <data.ticker> <target_price> <iterations> <horizon_days>

Example Output
Plaintext

------------------------------------------------------------
SIMULATION SUMMARY (EURUSD.ticker)
Historical Drift    : 0.000022
Historical Vol      : 0.006955
Forecast Horizon    : 30 Days
Simulated Paths     : 100000

Current Price       : 1.1790
Target Price        : 1.1000
Expected Average    : 1.1797

PROBABILITY ANALYSIS:
>> Probability of hitting target: 0.00%
>> Likelihood of missing target : 100.00%

------------------------------------------------------------

SIMULATION SUMMARY (EURUSD.ticker)
Historical Drift    : 0.000022
Historical Vol      : 0.006955
Forecast Horizon    : 1 Days
Simulated Paths     : 100000

Current Price       : 1.1790
Target Price        : 1.1900
Expected Average    : 1.1790

PROBABILITY ANALYSIS:
>> Probability of hitting target: 0.00%
>> Likelihood of missing target : 100.00%
```

## Technical Philosophy (Updated)

**Zero-Footprint**: Orchestration is written directly in GNU as (x86_64). Heavy-lifting parallel math runs in PTX (NVIDIA Assembly). No bloated high-level libraries.

**ABI-Proof & Stack Safe**: Built with strict manual 16-byte stack alignment and adherence to the System V AMD64 ABI for drop-in compatibility.

**Direct Driver Access**: Currently loads .cubin modules via the CUDA Driver API (libcuda).

**Future Roadmap (The "True" Bare-Metal Path)**: This project is moving toward a Zero-Dependency Architecture. Future iterations will bypass libc and libcuda entirely, utilizing pure Linux Syscalls for host logic and direct IOCTL calls to the NVIDIA kernel-mode driver for GPU orchestration, memory mapping, and kernel launching.
