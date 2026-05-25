import argparse

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

parser = argparse.ArgumentParser(description='Plot performance metrics.')
parser.add_argument('-r', '--rate-file', default='Request_Rate_Preq_WRR.csv', type=str, help='Request Rate CSV file')
parser.add_argument('-a', '--active-file', default='Active_Requests_Preq_WRR.csv', type=str, help='Active Requests CSV file')
parser.add_argument('-l', '--latency-file', default='Request_Latency_Preq_WRR.csv', type=str, help='Request Latency CSV file')
args = parser.parse_args()

# Define your file names here
rate_file = str(args.rate_file)
active_file = str(args.active_file)
latency_file = str(args.latency_file)

df_rate = pd.read_csv(rate_file)
df_rate['Time'] = pd.to_datetime(df_rate['Time'])

# Find the tested algorithm dynamically (fallback to 'roundrobin' if not found)
tested_algo = 'roundrobin'
for c in df_rate.columns:
    if c not in ('Time', 'Elapsed_Min', 'prequal'):
        tested_algo = c
        break


# Helper function to convert strings like "6.19K req/s" or "825 req/s" to float
def parse_rate(val):
    if pd.isna(val):
        return np.nan
    val = str(val).replace(' req/s', '').strip()
    if 'K' in val:
        return float(val.replace('K', '')) * 1000
    return float(val)


for col in ['prequal', tested_algo]:
    if col in df_rate.columns:
        df_rate[col] = df_rate[col].apply(parse_rate)

# Load and clean Active Requests Data

df_active = pd.read_csv(active_file)
df_active['Time'] = pd.to_datetime(df_active['Time'])

for col in ['prequal', tested_algo]:
    if col in df_active.columns:
        df_active[col] = pd.to_numeric(df_active[col], errors='coerce')

# Load and clean Request Latency Data
df_latency = pd.read_csv(latency_file)
df_latency['Time'] = pd.to_datetime(df_latency['Time'])


# Helper function to remove "ms" and convert to float
def parse_latency(val):
    if pd.isna(val):
        return np.nan
    val = str(val).strip()
    multiplier = 1.0
    if val.endswith('ms'):
        val = val[:-2].strip()
    elif val.endswith('s'):
        val = val[:-1].strip()
        multiplier = 1000.0

    try:
        return float(val) * multiplier
    except ValueError:
        return np.nan


for col in df_latency.columns:
    if col != 'Time':
        df_latency[col] = df_latency[col].apply(parse_latency)

# relativization of instants
start_time = min(df_rate['Time'].min(), df_active['Time'].min(), df_latency['Time'].min())

df_rate['Elapsed_Min'] = (df_rate['Time'] - start_time).dt.total_seconds() / 60.0
df_active['Elapsed_Min'] = (df_active['Time'] - start_time).dt.total_seconds() / 60.0
df_latency['Elapsed_Min'] = (df_latency['Time'] - start_time).dt.total_seconds() / 60.0

# Plotting
# Create 3 subplots sharing the same X-axis

fig, axes = plt.subplots(3, 1, figsize=(10, 12), sharex=True)

# Graph 1: Request Rate
axes[0].plot(df_rate['Elapsed_Min'], df_rate['prequal'], label='prequal', color='#1f77b4')
axes[0].plot(df_rate['Elapsed_Min'], df_rate[tested_algo], label=tested_algo, color='#ff7f0e')
axes[0].set_title('Request Rate')
axes[0].set_ylabel('Requests / sec')
axes[0].legend()
axes[0].grid(True, linestyle='--', alpha=0.6)

# Graph 2: Active Requests
axes[1].plot(df_active['Elapsed_Min'], df_active['prequal'], label='prequal', color='#1f77b4')
axes[1].plot(df_active['Elapsed_Min'], df_active[tested_algo], label=tested_algo, color='#ff7f0e')
axes[1].set_title('Active Requests (RIF)')
axes[1].set_ylabel('Active Requests')
axes[1].legend()
axes[1].grid(True, linestyle='--', alpha=0.6)

# Graph 3: Latency
cols_to_plot = ['prequal p50', f'{tested_algo} p50', 'prequal p90', f'{tested_algo} p90', 'prequal p99',
                f'{tested_algo} p99']
linestyles = {'prequal p50': '-', f'{tested_algo} p50': '-', 'prequal p90': '--', f'{tested_algo} p90': '--',
              'prequal p99': ':', f'{tested_algo} p99': ':'}
colors = {'prequal p50': '#1f77b4', f'{tested_algo} p50': '#ff7f0e', 'prequal p90': '#1f77b4',
          f'{tested_algo} p90': '#ff7f0e', 'prequal p99': '#1f77b4', f'{tested_algo} p99': '#ff7f0e'}

for col in cols_to_plot:
    if col in df_latency.columns:
        axes[2].plot(df_latency['Elapsed_Min'], df_latency[col], label=col, linestyle=linestyles.get(col, '-'),
                     color=colors.get(col))

axes[2].set_title('Request Latency (p50, p90, p99)')
axes[2].set_ylabel('Latency (ms)')

# Aggiorniamo l'etichetta dell'asse X
axes[2].set_xlabel('Minutes passed')

axes[2].legend(fontsize='small')
axes[2].grid(True, linestyle='--', alpha=0.6)

# RIMOSSO: axes[2].xaxis.set_major_formatter(...) -> Non serve più!
# RIMOSSO: axes[2].tick_params(rotation=45) -> I numeri semplici si leggono bene dritti

plt.tight_layout()

# Save and show
plt.savefig('performance_metrics.png', dpi=300)
plt.show()
