import argparse
import glob
import os
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

#argomenti da riga di comando
parser = argparse.ArgumentParser(description='Plot performance metrics da una cartella specifica.')
parser.add_argument('-d', '--dir', type=str, required=True, 
                    help='Percorso della cartella contenente i file CSV (es. RR_2500, WRR_exp_load)')
args = parser.parse_args()

# Funzione helper per trovare il file corretto in base al prefisso
def get_file_by_prefix(directory, prefix):
    search_pattern = os.path.join(directory, f"{prefix}*")
    matched_files = glob.glob(search_pattern)
    if not matched_files:
        raise FileNotFoundError(f"Errore: Nessun file che inizia con '{prefix}' trovato nella cartella '{directory}'")
    return matched_files[0]

# Identificazione dinamica dei file nella cartella selezionata
try:
    rate_file = get_file_by_prefix(args.dir, 'rate-')
    active_file = get_file_by_prefix(args.dir, 'act-')
    latency_file = get_file_by_prefix(args.dir, 'lat-')
    
    print(f"Caricamento dati dalla cartella: {args.dir}")
    print(f"  -> Rate file: {os.path.basename(rate_file)}")
    print(f"  -> Active file: {os.path.basename(active_file)}")
    print(f"  -> Latency file: {os.path.basename(latency_file)}\n")
except FileNotFoundError as e:
    print(e)
    exit(1)

# Caricamento e pulizia dei dati (Invariato)
df_rate = pd.read_csv(rate_file)
df_rate['Time'] = pd.to_datetime(df_rate['Time'])

# Trova l'algoritmo testato dinamicamente
tested_algo = 'roundrobin'
for c in df_rate.columns:
    if c not in ('Time', 'Elapsed_Min', 'prequal'):
        tested_algo = c
        break

# Helper function per convertire le stringhe del rate
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

# Load e clean Active Requests Data
df_active = pd.read_csv(active_file)
df_active['Time'] = pd.to_datetime(df_active['Time'])

for col in ['prequal', tested_algo]:
    if col in df_active.columns:
        df_active[col] = pd.to_numeric(df_active[col], errors='coerce')

# Load e clean Request Latency Data
df_latency = pd.read_csv(latency_file)
df_latency['Time'] = pd.to_datetime(df_latency['Time'])

# Helper function per rimuovere "ms" e convertire
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

# Relativizzazione degli istanti di tempo
start_time = min(df_rate['Time'].min(), df_active['Time'].min(), df_latency['Time'].min())

df_rate['Elapsed_Min'] = (df_rate['Time'] - start_time).dt.total_seconds() / 60.0
df_active['Elapsed_Min'] = (df_active['Time'] - start_time).dt.total_seconds() / 60.0
df_latency['Elapsed_Min'] = (df_latency['Time'] - start_time).dt.total_seconds() / 60.0

# Plotting
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
                f'{tested_algo} p99', 'prequal p99.9', f'{tested_algo} p99.9']
linestyles = {'prequal p50': '-', f'{tested_algo} p50': '-', 'prequal p90': '--', f'{tested_algo} p90': '--',
              'prequal p99': ':', f'{tested_algo} p99': ':', 'prequal p99.9': '-.', f'{tested_algo} p99.9': '-.'}
colors = {'prequal p50': '#1f77b4', f'{tested_algo} p50': '#ff7f0e', 'prequal p90': '#1f77b4',
          f'{tested_algo} p90': '#ff7f0e', 'prequal p99': '#1f77b4', f'{tested_algo} p99': '#ff7f0e', 'prequal p99.9': '#1f77b4', f'{tested_algo} p99.9': '#ff7f0e'}

for col in cols_to_plot:
    if col in df_latency.columns:
        axes[2].plot(df_latency['Elapsed_Min'], df_latency[col], label=col, linestyle=linestyles.get(col, '-'),
                     color=colors.get(col))

axes[2].set_title('Request Latency (p50, p90, p99, p99.9)')
axes[2].set_ylabel('Latency (ms)')
axes[2].set_yscale('log')
axes[2].set_xlabel('Minutes passed')
axes[2].legend(fontsize='small')
axes[2].grid(True, linestyle='--', alpha=0.6)

# Salva il plot direttamente all'interno della cartella selezionata
output_plot_path = os.path.join(args.dir, 'performance_metrics.png')
plt.savefig(output_plot_path, dpi=300)
print(f"Grafico salvato in: {output_plot_path}")
plt.show()