#!/usr/bin/env python3
import os
import sys
import struct
import yfinance as yf
import matplotlib.pyplot as plt
from datetime import datetime

def generate_png_chart(filename, ticker_symbol):
    base_path, _ = os.path.splitext(filename)
    png_filename = base_path + ".png"
    
    timestamps = []
    prices = []
    with open(filename, "rb") as f:
        while True:
            chunk = f.read(16)
            if len(chunk) < 16: break
            ts, price = struct.unpack("Qd", chunk)
            timestamps.append(datetime.fromtimestamp(ts))
            prices.append(price)
    
    plt.figure(figsize=(12, 6))
    plt.plot(timestamps, prices, color='#007acc', linewidth=1.5)
    plt.title(f"{ticker_symbol} Historical Trend", fontsize=13, fontweight="bold")
    plt.grid(True, linestyle=":", alpha=0.6)
    plt.savefig(png_filename, dpi=300)
    plt.close()
    print(f"Chart saved to {png_filename}")

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <TICKER>")
        sys.exit(1)

    # Automatically add =X if it's a 6-letter currency pair missing it
    symbol = sys.argv[1].strip().upper()
    if len(symbol) == 6 and not "=" in symbol:
        symbol += "=X"
    
    base_name = symbol.replace("=X", "").replace("^", "")
    filename = f"{base_name}.ticker"
    
    print(f"Fetching data for {symbol}...")
    ticker = yf.Ticker(symbol)
    
    # Use "max" to get the full history of the Peso
    data = ticker.history(period="max", interval="1d")

    if data.empty:
        print(f"Error: No data found for {symbol}. Try a different ticker.")
        return

    data = data.dropna(subset=['Close'])

    print(f"Writing {len(data)} records to {filename}...")
    packed_data = bytearray()
    for timestamp, row in data.iterrows():
        epoch_ts = int(timestamp.timestamp())
        close_price = float(row['Close'])
        packed_data.extend(struct.pack("Qd", epoch_ts, close_price))

    with open(filename, "wb") as f:
        f.write(packed_data)

    generate_png_chart(filename, base_name)
    print(f"Done. Successfully generated {filename} with {len(data)} records.")

if __name__ == "__main__":
    main()