# THEORY

## Overview

The kernel implements a Monte Carlo simulation of Geometric Brownian Motion (GBM) on an NVIDIA GPU using PTX assembly.

Each CUDA thread independently simulates multiple stochastic price trajectories.

The kernel estimates:

- cumulative ending prices
- cumulative target barrier hits

using parallel statistical sampling.

---

# Mathematical Model

The simulated process follows the stochastic differential equation:

```math
dS = \mu Sdt + \sigma SdW
```

where:

```math
S
```

is asset price,

```math
\mu
```

is drift,

```math
\sigma
```

is volatility,

and:

```math
dW
```

is a Wiener process increment.

---

# Integrated Solution

The kernel uses the closed-form GBM solution:

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

is a standard normal random variable.

---

# Simulation Model

Each thread performs:

```text
for simulation in iterations:
    S = S0
    for day in horizon:
        generate random Z
        update S
        evaluate barrier condition
    accumulate final S
    accumulate hit result
```

No communication occurs between threads.

---

# Thread Indexing

The global thread index is:

```math
idx =
blockIdx.x \cdot blockDim.x + threadIdx.x
```

The index determines:

- RNG seed offset
- output location
- thread-local accumulation region

---

# Input Parameters

The kernel receives:

```text
drift          μ
volatility     σ
target_price   Barrier target
start_price    Initial asset price
seed           Global RNG seed
iters          Simulations per thread
horizon        Days per trajectory
```

---

# Drift Term

The deterministic drift component is precomputed:

```math
driftTerm =
\mu - \frac{1}{2}\sigma^2
```

This avoids recomputing invariant terms inside loops.

---

# Random Number Generator

The kernel uses a Xorshift64 generator.

State transition:

```text
x ^= x << 13
x ^= x >> 7
x ^= x << 17
```

The RNG state is thread-local.

Initial state:

```math
state = seed + threadId
```

The state is forced nonzero:

```text
state |= 1
```

to avoid degenerate cycles.

---

# Uniform Distribution Generation

The kernel generates uniform samples through IEEE-754 bit construction.

Procedure:

1. Extract mantissa bits from RNG state.
2. Insert exponent bits corresponding to `1.x`.
3. Reinterpret bits as floating-point.
4. Subtract `1.0`.

Result:

```math
U \in [0,1)
```

This avoids integer division.

---

# Stability Guard

The kernel enforces:

```math
U_1 \ge 10^{-15}
```

because:

```math
\ln(0)
```

is undefined in the Box-Muller transform.

---

# Normal Distribution Generation

The kernel uses the Box-Muller transform:

```math
Z =
\sqrt{-2\ln(U_1)}
\cos(2\pi U_2)
```

where:

```math
U_1,U_2 \sim Uniform(0,1)
```

The result:

```math
Z \sim N(0,1)
```

---

# Hardware Approximation Strategy

The implementation uses hardware approximation instructions.

---

## Logarithm

Natural logarithm is approximated through:

```math
\ln(x) =
\log_2(x)\ln(2)
```

using:

```text
lg2.approx.f32
```

---

## Exponential

Exponential is approximated through:

```math
e^x =
2^{x\log_2(e)}
```

using:

```text
ex2.approx.f32
```

---

## Trigonometric Function

Cosine is computed using:

```text
cos.approx.f32
```

---

# Precision Model

The kernel mixes:

```text
f64
```

and:

```text
f32
```

operations.

State accumulation and price variables use double precision.

Transcendental approximations use single precision hardware intrinsics for throughput.

This reduces instruction latency and register pressure.

---

# Price Evolution

At each timestep:

```math
S_{t+1} =
S_t
\exp
(
driftTerm + \sigma Z
)
```

The kernel computes:

```math
\sigma Z + driftTerm
```

then exponentiates the result.

---

# Barrier Detection

The kernel tracks whether the trajectory touches a target barrier.

Two cases exist.

---

## Short Barrier

If:

```math
target < S_0
```

a hit occurs when:

```math
S_t \le target
```

---

## Long Barrier

If:

```math
target > S_0
```

a hit occurs when:

```math
S_t \ge target
```

---

# Hit Accumulation

Each path maintains a binary hit flag:

```text
0 = untouched
1 = touched
```

After the trajectory completes:

```math
totalHits += hitFlag
```

A path contributes at most one hit.

---

# Price Accumulation

After each trajectory:

```math
sumAcc += S_T
```

where:

```math
S_T
```

is the final simulated price.

---

# Memory Layout

Each thread writes exactly:

```text
1 x f64 final price sum
1 x u32 hit count
```

to global memory.

Output arrays are indexed by thread ID.

---

# Register Utilization

Registers store:

- RNG state
- simulation counters
- day counters
- current asset price
- temporary Box-Muller variables
- accumulators

The kernel minimizes global memory traffic.

Most computation remains register-resident.

---

# Control Flow

The kernel contains two nested loops:

---

## Outer Loop

Simulation iteration loop:

```text
for sim in iters
```

---

## Inner Loop

Trajectory timestep loop:

```text
for day in horizon
```

---

# Occupancy Characteristics

Performance depends on:

- register pressure
- warp occupancy
- transcendental instruction throughput
- instruction latency hiding

The kernel avoids:

- shared memory
- synchronization
- atomics
- inter-thread communication

---

# Numerical Characteristics

The simulation is stochastic.

Results converge statistically as sample count increases.

Approximation instructions introduce additional numerical error relative to IEEE-correct transcendental implementations.

The implementation prioritizes throughput over strict numerical precision.

---

# Complexity

Per thread:

```math
O(iters \times horizon)
```

Total complexity scales linearly with:

- number of threads
- simulation count
- horizon length

---

# PTX Characteristics

Target architecture:

```text
sm_61
```

PTX version:

```text
7.0
```

The implementation uses explicit PTX instructions rather than CUDA runtime abstractions.

Primary instruction classes:

```text
mul
add
fma
xor
shl
shr
sqrt
setp
bra
lg2.approx
ex2.approx
cos.approx
```

---

# Determinism

The RNG stream is deterministic for fixed:

- seed
- launch geometry
- iteration counts

Floating-point rounding behavior may vary across GPU architectures due to hardware approximation instructions.

---

# Failure Conditions

The kernel does not explicitly guard against:

- overflow
- underflow
- NaN propagation
- infinite prices
- RNG correlation artifacts
- volatility instability

Behavior follows IEEE floating-point semantics where applicable.

---

# Design Goals

Primary objectives:

- high simulation throughput
- low synchronization overhead
- register-local execution
- minimal memory bandwidth usage
- scalable Monte Carlo sampling
- direct PTX-level control

The implementation prioritizes execution density and GPU occupancy over strict mathematical accuracy.

---
