# Theory of the Engine: How we Predict the "Unpredictable"

To understand this engine, you have to imagine the stock market not as a series of random guesses, but as a **drunk person walking up a hill.**

### 1. The Components of a Price
Every price movement in our engine is made of two parts:
*   **The Drift (The Hill):** This is the general direction. If the Euro usually goes up by 0.002% a day, that is the "Hill" it's climbing.
*   **The Volatility (The Drunk):** This is the random swaying back and forth. Even if the hill goes up, the "drunk" might take five steps left and three steps right.

### 2. Geometric Brownian Motion (GBM)
We use a formula called GBM. It assumes that while we don't know the exact price tomorrow, we *do* know the "character" of the asset.
The formula we use is:
$$S_t = S_0 e^{(\mu - \frac{\sigma^2}{2})t + \sigma W_t}$$

*   **$S_0$**: Today's price (The Launchpad).
*   **$\mu$ (Mu)**: The Drift (The Hill).
*   **$\sigma$ (Sigma)**: The Volatility (The Sway).
*   **$W_t$**: The Randomness (The "Chaos" we generate on the GPU).

### 3. Why the GPU?
If you want to know if a price will hit 1.10 in 30 days, you could guess. Or, you could flip a coin. 
But our engine doesn't guess—it **simulates**. It creates 1,000,000 different "universes." In some universes, the drunk person stays on the path. In others, they fall off. 

By counting how many universes hit the target price, we get a **Probability**. 
*   **10 simulations** is a guess.
*   **1,000,000 simulations** is Statistics.
Doing this on a CPU would take seconds. Doing it on a GPU in Assembly takes **milliseconds**.

### 4. The Magic of Box-Muller
Computers are bad at being random. They like order. To create the "Chaos" ($W_t$), we use the **Box-Muller Transform**. It takes simple, flat random numbers and shapes them into a "Bell Curve" (Normal Distribution). This mimics how human beings actually trade—mostly normal behavior, with the occasional wild panic.