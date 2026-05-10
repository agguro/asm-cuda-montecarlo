import struct
import numpy as np

def verify_monte_carlo(filepath, target_price, iters=10000):
    prices = []
    
    # 1. Read Binary Data
    with open(filepath, "rb") as f:
        while True:
            chunk = f.read(16)
            if len(chunk) < 16: break
            _, price = struct.unpack("Qd", chunk)
            prices.append(price)
    
    prices = np.array(prices)
    returns = (prices[1:] / prices[:-1]) - 1
    
    # 2. Calculate Metrics
    drift = np.mean(returns)
    vol = np.std(returns)
    last_price = prices[-1]
    
    print(f"--- Python Verification ---")
    print(f"Drift: {drift:.6f} | Volatility: {vol:.6f}")
    print(f"Last Price: {last_price:.4f}")

    # 3. Geometric Brownian Motion Simulation
    # S_t = S_0 * exp((drift - 0.5 * vol^2) + vol * Z)
    Z = np.random.standard_normal(iters)
    simulated_prices = last_price * np.exp((drift - 0.5 * vol**2) + vol * Z)
    
    # 4. Calculate Probabilities
    hits = np.sum(simulated_prices > target_price)
    prob = (hits / iters) * 100
    avg_price = np.mean(simulated_prices)
    
    print(f"\nResults for Target > {target_price}:")
    print(f"Probability: {prob:.2f}%")
    print(f"Expected Average: {avg_price:.4f}")

if __name__ == "__main__":
    # Usage: python3 verify.py PSEC.ticker 2.5
    import sys
    file = sys.argv[1]
    target = float(sys.argv[2])
    verify_monte_carlo(file, target)