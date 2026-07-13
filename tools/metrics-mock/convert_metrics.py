#!/usr/bin/env python3
"""
Convert raw data to aggregated metrics.

This script processes two types of input files:
1. Artifact sizes CSV: aggregates by file extension
2. Profile archives: aggregates compiler pass metrics

Input formats:
  - artifact-sizes-*.csv: individual file sizes
  - profiles-*.tar.gz: compiler profiling data

Output format (data/):
  timestamp,commit_hash,pr_number,kind,name,value
  2025-11-18T09:34:49Z,hash,5004,size_in_bytes,opt,336187168
  2025-11-18T09:34:49Z,hash,5004,time_in_seconds,parsing,1.234
  2025-11-18T09:34:49Z,hash,5004,alloc_in_bytes,parsing,12345678
  2025-11-18T09:34:49Z,hash,5004,counter,reload,311
"""

import argparse
import csv
import sys
import os
import tarfile
import tempfile
import re
from pathlib import Path
from collections import defaultdict
from enum import Enum
from typing import Optional, Dict, List, Tuple, NamedTuple


# Type aliases
Counters = Dict[str, int]  # counter name -> value


class PassData(NamedTuple):
    """Data for a single compiler pass."""
    time: float  # time in seconds
    alloc: int  # allocated memory in bytes
    top_heap: int  # top heap size in bytes
    absolute_top_heap: int  # absolute top heap size in bytes


PassMetrics = Dict[str, PassData]  # pass name -> pass data


class ProfileMetrics(NamedTuple):
    """Metrics extracted from a single profile CSV file."""
    pass_metrics: PassMetrics
    counters: Counters


# List of extensions we're interested in tracking
TARGET_EXTENSIONS = [
    'exe', 'opt', 'a', 'cmxa', 'cma', 'cmi', 'cmx',
    'cmo', 'cms', 'cmsi', 'cmt', 'cmti', 'o'
]

# Symbolic constant for top-level pass (representing totals across all passes)
TOP_LEVEL_PASS = '<all>'

# Key compiler passes to track
KEY_PASSES = [
    TOP_LEVEL_PASS,
    'parsing',
    'typing',
    'generate/flambda2',
    'generate/compile_phrases/cfg',
    'generate/assemble',
]


class AggregationStrategy(Enum):
    """Strategy for aggregating counter values across passes."""
    SUM = "sum"      # Sum all occurrences across passes
    LAST = "last"    # Take the last occurrence in the file


# Configuration for counter aggregation
COUNTER_CONFIG = {
    'reload': AggregationStrategy.LAST,
    'spill': AggregationStrategy.LAST,
    'block': AggregationStrategy.LAST,
    'instruction': AggregationStrategy.LAST,
    'move': AggregationStrategy.LAST,
    'stack_slot': AggregationStrategy.LAST,
}


def fatal(message: str) -> None:
    """Print an error message to stderr and exit with status 1."""
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def extract_extension(filename: str) -> Optional[str]:
    """Extract the file extension after the last dot."""
    _, ext = os.path.splitext(filename)
    return ext[1:] if ext else None  # Remove leading dot


def parse_time(time_str: str) -> Optional[float]:
    """Parse time string like '0.268s' to float seconds."""
    if not time_str:
        return None
    match = re.match(r'([\d.]+)s', time_str.strip())
    if match:
        return float(match.group(1))
    return None


def parse_alloc(alloc_str: str) -> Optional[int]:
    """Parse allocation string like '190MB' or '8.46MB' to bytes."""
    if not alloc_str or not alloc_str.strip():
        return None

    # Match number followed by optional unit (B, kB, MB, GB)
    match = re.match(r'([\d.]+)(B|kB|MB|GB)?', alloc_str.strip())
    if not match:
        return None

    value = float(match.group(1))
    unit = match.group(2) if match.group(2) else 'B'

    # Convert to bytes
    multipliers = {
        'B': 1,
        'kB': 1024,
        'MB': 1024 * 1024,
        'GB': 1024 * 1024 * 1024,
    }

    return int(value * multipliers[unit])


def parse_counters(counter_str: str) -> Counters:
    """Parse counter string like '[reload = 310; spill = 253]' to dict."""
    counters: Counters = {}
    if not counter_str or counter_str.strip() == '':
        return counters

    # Remove brackets and split by semicolon
    content = counter_str.strip().strip('[]')
    if not content:
        return counters

    for pair in content.split(';'):
        pair = pair.strip()
        if '=' in pair:
            name, value = pair.split('=', 1)
            counters[name.strip()] = int(value.strip())

    return counters


def extract_pass_name(full_name: str) -> Optional[str]:
    """
    Extract pass name from format 'file=/path/to/file.ext//pass-name'.
    For top-level passes (format 'file=/path/'), returns TOP_LEVEL_PASS.
    Returns None if the format doesn't match.
    """
    if '//' in full_name:
        pass_name = full_name.split('//', 1)[1]
        return pass_name
    elif full_name.endswith('/'):
        # Top-level pass without '//' separator (e.g., 'file=objects.ml/')
        return TOP_LEVEL_PASS
    return None


def process_profile_csv(profile_path: Path) -> ProfileMetrics:
    """
    Process a single profile CSV file.

    Returns ProfileMetrics containing:
    - pass_metrics: Dict mapping pass names to PassData (time, alloc, top_heap, absolute_top_heap)
    - counters: Dict mapping counter names to their aggregated values across all passes

    Example:
        ProfileMetrics(
            pass_metrics={'parsing': PassData(time=1.234, alloc=12345678, top_heap=5000000, absolute_top_heap=6000000)},
            counters={'reload': 41, 'spill': 28}
        )
    """
    # Use temporary dicts for aggregation
    pass_time_values: Dict[str, float] = defaultdict(float)
    pass_alloc_values: Dict[str, int] = defaultdict(int)
    pass_top_heap_values: Dict[str, int] = defaultdict(int)
    pass_absolute_top_heap_values: Dict[str, int] = defaultdict(int)
    counters: Counters = defaultdict(int)

    with open(profile_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            full_pass_name = row['pass name']
            pass_name = extract_pass_name(full_pass_name)

            if not pass_name:
                continue

            # Extract time and alloc only for key passes
            for key_pass in KEY_PASSES:
                if key_pass == pass_name:
                    # Extract time
                    time_str = row.get('time', '')
                    time_val = parse_time(time_str)
                    if time_val is not None:
                        pass_time_values[key_pass] += time_val

                    # Extract alloc
                    alloc_str = row.get('alloc', '')
                    alloc_val = parse_alloc(alloc_str)
                    if alloc_val is not None:
                        pass_alloc_values[key_pass] += alloc_val

                    # Extract top-heap
                    top_heap_str = row.get('top-heap', '')
                    top_heap_val = parse_alloc(top_heap_str)
                    if top_heap_val is not None:
                        pass_top_heap_values[key_pass] += top_heap_val

                    # Extract absolute-top-heap
                    absolute_top_heap_str = row.get('absolute-top-heap', '')
                    absolute_top_heap_val = parse_alloc(absolute_top_heap_str)
                    if absolute_top_heap_val is not None:
                        pass_absolute_top_heap_values[key_pass] += absolute_top_heap_val

            # Extract counters from all passes
            counter_str = row.get('counters', '')
            row_counters = parse_counters(counter_str)
            for counter_name, counter_value in row_counters.items():
                if counter_name in COUNTER_CONFIG:
                    # For LAST strategy, just overwrite
                    # For SUM strategy, add
                    if COUNTER_CONFIG[counter_name] == AggregationStrategy.LAST:
                        counters[counter_name] = counter_value
                    else:
                        counters[counter_name] += counter_value

    # Convert to PassData objects
    pass_metrics: PassMetrics = {}
    for key_pass in KEY_PASSES:
        pass_metrics[key_pass] = PassData(
            time=pass_time_values[key_pass],
            alloc=pass_alloc_values[key_pass],
            top_heap=pass_top_heap_values[key_pass],
            absolute_top_heap=pass_absolute_top_heap_values[key_pass]
        )

    return ProfileMetrics(
        pass_metrics=pass_metrics,
        counters=dict(counters)
    )


def convert_artifact_sizes(input_path: Path) -> Tuple[Dict[str, str], List[List]]:
    """
    Convert raw artifact sizes to aggregated metrics by extension.

    Args:
        input_path: Path to the input CSV file

    Returns:
        Tuple of (metadata dict, list of metric rows)
    """

    # Read the input CSV
    with open(input_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        fatal(f"No data found in {input_path}")

    # Extract metadata from the first row
    metadata = {
        'timestamp': rows[0]['timestamp'],
        'commit_hash': rows[0]['commit_hash'],
        'pr_number': rows[0]['pr_number'],
    }

    kind = rows[0]['kind']

    # Aggregate sizes by extension
    extension_sizes = defaultdict(int)

    for row in rows:
        filename = row['name']
        size = int(row['value'])

        ext = extract_extension(filename)
        if ext in TARGET_EXTENSIONS:
            extension_sizes[ext] += size

    # Ensure all target extensions are present (with 0 if missing)
    for ext in TARGET_EXTENSIONS:
        if ext not in extension_sizes:
            extension_sizes[ext] = 0

    # Generate metric rows
    metric_rows = []
    for ext in TARGET_EXTENSIONS:
        metric_rows.append([
            metadata['timestamp'],
            metadata['commit_hash'],
            metadata['pr_number'],
            kind,
            ext,
            extension_sizes[ext]
        ])

    return metadata, metric_rows


def convert_profiles(input_path: Path, metadata: Dict[str, str]) -> List[List]:
    """
    Convert profile archive to aggregated metrics.

    Args:
        input_path: Path to the profiles-*.tar.gz file
        metadata: Metadata dict with timestamp, commit_hash, pr_number

    Returns:
        List of metric rows
    """
    # Aggregate metrics across all profiles
    all_pass_time_values: Dict[str, float] = defaultdict(float)
    all_pass_alloc_values: Dict[str, int] = defaultdict(int)
    all_pass_top_heap_values: Dict[str, int] = defaultdict(int)
    all_pass_absolute_top_heap_values: Dict[str, int] = defaultdict(int)
    all_counters: Counters = defaultdict(int)

    # Extract and process all profile CSV files
    with tempfile.TemporaryDirectory() as tmpdir:
        tmppath = Path(tmpdir)

        # Extract tar.gz
        with tarfile.open(input_path, 'r:gz') as tar:
            tar.extractall(tmppath)

        # Find all profile.*.csv files
        profile_files = list(tmppath.glob('**/profile.*.csv'))

        if not profile_files:
            fatal(f"No profile CSV files found in {input_path}")

        # Process each profile and aggregate
        for profile_file in profile_files:
            profile_metrics = process_profile_csv(profile_file)

            # Aggregate time and alloc (always sum)
            for key_pass, pass_data in profile_metrics.pass_metrics.items():
                all_pass_time_values[key_pass] += pass_data.time
                all_pass_alloc_values[key_pass] += pass_data.alloc
                all_pass_top_heap_values[key_pass] += pass_data.top_heap
                all_pass_absolute_top_heap_values[key_pass] += pass_data.absolute_top_heap

            # Aggregate counters (always sum across profiles)
            for counter_name, counter_value in profile_metrics.counters.items():
                all_counters[counter_name] += counter_value

    # Convert aggregated values to PassData objects
    all_pass_metrics: PassMetrics = {}
    for key_pass in KEY_PASSES:
        all_pass_metrics[key_pass] = PassData(
            time=all_pass_time_values[key_pass],
            alloc=all_pass_alloc_values[key_pass],
            top_heap=all_pass_top_heap_values[key_pass],
            absolute_top_heap=all_pass_absolute_top_heap_values[key_pass]
        )

    # Generate metric rows
    metric_rows = []

    # Write time metrics for each key pass
    for key_pass in KEY_PASSES:
        pass_data = all_pass_metrics[key_pass]
        metric_rows.append([
            metadata['timestamp'],
            metadata['commit_hash'],
            metadata['pr_number'],
            'time_in_seconds',
            key_pass,
            f'{pass_data.time:.3f}'
        ])

    # Write alloc metrics for each key pass
    for key_pass in KEY_PASSES:
        pass_data = all_pass_metrics[key_pass]
        metric_rows.append([
            metadata['timestamp'],
            metadata['commit_hash'],
            metadata['pr_number'],
            'alloc_in_bytes',
            key_pass,
            pass_data.alloc
        ])

    # Write top-heap metrics for each key pass
    for key_pass in KEY_PASSES:
        pass_data = all_pass_metrics[key_pass]
        metric_rows.append([
            metadata['timestamp'],
            metadata['commit_hash'],
            metadata['pr_number'],
            'top_heap_in_bytes',
            key_pass,
            pass_data.top_heap
        ])

    # Write absolute-top-heap metrics for each key pass
    for key_pass in KEY_PASSES:
        pass_data = all_pass_metrics[key_pass]
        metric_rows.append([
            metadata['timestamp'],
            metadata['commit_hash'],
            metadata['pr_number'],
            'absolute_top_heap_in_bytes',
            key_pass,
            pass_data.absolute_top_heap
        ])

    # Write counter metrics (aggregated across all profiles)
    for counter_name in sorted(COUNTER_CONFIG.keys()):
        metric_rows.append([
            metadata['timestamp'],
            metadata['commit_hash'],
            metadata['pr_number'],
            'counter',
            counter_name,
            all_counters[counter_name]
        ])

    return metric_rows


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Convert raw data to aggregated metrics.'
    )
    parser.add_argument(
        '--artifact-sizes',
        type=Path,
        required=True,
        help='Path to the artifact-sizes-*.csv file'
    )
    parser.add_argument(
        '--profiles',
        type=Path,
        required=True,
        help='Path to the profiles-*.tar.gz file'
    )
    parser.add_argument(
        '--output-dir',
        type=Path,
        required=True,
        help='Directory where the output CSV file will be written'
    )

    args = parser.parse_args()

    # Validate inputs
    if not args.artifact_sizes.exists():
        fatal(f"Artifact sizes file '{args.artifact_sizes}' not found")
    if not args.profiles.exists():
        fatal(f"Profiles file '{args.profiles}' not found")

    if not args.artifact_sizes.name.startswith('artifact-sizes-') or args.artifact_sizes.suffix != '.csv':
        fatal(f"Invalid artifact sizes filename format: {args.artifact_sizes.name}")
    if not args.profiles.name.startswith('profiles-') or args.profiles.suffix != '.gz':
        fatal(f"Invalid profiles filename format: {args.profiles.name}")

    # Process artifact sizes (this provides metadata)
    metadata, artifact_rows = convert_artifact_sizes(args.artifact_sizes)

    # Process profiles using the same metadata
    profile_rows = convert_profiles(args.profiles, metadata)

    # Combine all metric rows
    all_rows = artifact_rows + profile_rows

    # Generate output filename from artifact-sizes filename
    output_filename = args.artifact_sizes.name.replace('artifact-sizes-', 'metrics-')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    output_path = args.output_dir / output_filename

    # Write combined output
    with open(output_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'commit_hash', 'pr_number', 'kind', 'name', 'value'])
        writer.writerows(all_rows)

    print(f"Successfully converted to {output_path}")
    print(f"  Artifact size metrics: {len(artifact_rows)} rows")
    print(f"  Profile metrics: {len(profile_rows)} rows")
    print(f"  Total: {len(all_rows)} rows")


if __name__ == '__main__':
    main()
