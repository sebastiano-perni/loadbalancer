import math
from pathlib import Path

import pandas as pd

TIME_COLUMN = "Time"
PREQUAL = "prequal"


def preprocess(directory, trim_readings=3, interval_seconds=3):
    directory = Path(directory)
    latency_file = _find_csv(directory, "lat-")
    active_file = _find_csv(directory, "act-")
    rate_file = _find_csv(directory, "rate-")

    latency = pd.read_csv(latency_file)
    active = pd.read_csv(active_file)
    rate = pd.read_csv(rate_file)

    dataframes = [latency, active, rate]
    other_algo = _other_algorithm(dataframes)
    keep_times = _keep_times(dataframes, other_algo, trim_readings)

    return tuple(_compact_timeline(dataframe, keep_times, interval_seconds) for dataframe in dataframes)


def _find_csv(directory, prefix):
    matches = sorted(path for path in directory.glob(f"{prefix}*.csv") if not path.stem.endswith("_prep"))
    if not matches:
        raise FileNotFoundError(f"No CSV starting with '{prefix}' found in {directory}")
    if len(matches) > 1:
        names = ", ".join(path.name for path in matches)
        raise FileExistsError(f"More than one CSV starting with '{prefix}' found in {directory}: {names}")
    return matches[0]


def _other_algorithm(dataframes):
    algorithms = {_algorithm_name(column) for dataframe in dataframes for column in dataframe.columns if
                  column != TIME_COLUMN}
    others = sorted(algorithms - {PREQUAL})
    if len(others) != 1:
        raise ValueError(f"Expected exactly one algorithm besides '{PREQUAL}', found: {others}")
    return others[0]


def _algorithm_name(column):
    if column == PREQUAL or column.startswith(f"{PREQUAL} "):
        return PREQUAL
    return column.split()[0]


def _keep_times(dataframes, other_algo, trim_readings):
    labels = _phase_labels(dataframes, other_algo)
    labels = labels[labels.index >= _first_other_algo_time(labels, other_algo)]

    runs = []
    current_label = None
    current_times = []

    for timestamp, label in labels.items():
        if label == "empty":
            continue
        if label == "mixed":
            raise ValueError(f"Both algorithms have data at {timestamp}; cannot infer a phase")

        if label != current_label:
            if current_times:
                runs.append(current_times)
            current_label = label
            current_times = [timestamp]
        else:
            current_times.append(timestamp)

    if current_times:
        runs.append(current_times)

    keep_times = []
    for index, times in enumerate(runs):
        start = trim_readings if index > 0 else 0
        end = len(times) - (trim_readings if index < len(runs) - 1 else 0)
        keep_times.extend(times[start:max(start, end)])

    if not keep_times:
        raise ValueError("All readings were removed by preprocessing")
    return keep_times


def _phase_labels(dataframes, other_algo):
    values_by_time = {}

    for dataframe in dataframes:
        local = dataframe.copy()
        local[TIME_COLUMN] = pd.to_datetime(local[TIME_COLUMN])
        for _, row in local.iterrows():
            values = values_by_time.setdefault(row[TIME_COLUMN], {PREQUAL: [], other_algo: []})
            for column, value in row.items():
                if column == TIME_COLUMN:
                    continue
                algorithm = _algorithm_name(column)
                if algorithm in values:
                    values[algorithm].append(value)

    labels = {}
    for timestamp, values in values_by_time.items():
        prequal_active = any(_has_data(value) for value in values[PREQUAL])
        other_active = any(_has_data(value) for value in values[other_algo])

        if prequal_active and other_active:
            labels[timestamp] = "mixed"
        elif prequal_active:
            labels[timestamp] = PREQUAL
        elif other_active:
            labels[timestamp] = other_algo
        else:
            labels[timestamp] = "empty"

    return pd.Series(labels).sort_index()


def _first_other_algo_time(labels, other_algo):
    other_times = labels[labels == other_algo]
    if other_times.empty:
        raise ValueError(f"No '{other_algo}' phase found")
    return other_times.index[0]


def _has_data(value):
    number = _number(value)
    return not math.isnan(number) and number != 0


def _number(value):
    if pd.isna(value):
        return math.nan

    text = str(value).strip()
    if not text or text.lower() == "nan":
        return math.nan

    multiplier = 1
    for suffix, factor in ((" req/s", 1), ("ms", 1), ("s", 1000), ("K", 1000), ("M", 1_000_000)):
        if text.endswith(suffix):
            text = text[:-len(suffix)].strip()
            multiplier *= factor

    try:
        return float(text) * multiplier
    except ValueError:
        return math.nan


def _compact_timeline(dataframe, keep_times, interval_seconds):
    result = dataframe.copy()
    result[TIME_COLUMN] = pd.to_datetime(result[TIME_COLUMN])
    order = {timestamp: index for index, timestamp in enumerate(keep_times)}

    result = result[result[TIME_COLUMN].isin(order)].copy()
    result["_order"] = result[TIME_COLUMN].map(order)
    result = result.sort_values("_order").drop(columns="_order")
    result[TIME_COLUMN] = range(0, len(result) * interval_seconds, interval_seconds)
    return result.reset_index(drop=True)
