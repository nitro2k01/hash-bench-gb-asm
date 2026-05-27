#!/usr/bin/env python3
"""Parse a custom benchmarking log file and report test timing statistics."""

import sys
from collections import defaultdict

# --- Configure your test list here ---
test_list = {
    # Addresses for the dmang-dev's original hash-bench-gb.
    (0x0D7B, "CRC8"),
    (0x0DBC, "CRC16"),
    (0x0E16, "CRC32"),
    (0x0EE9, "ADL32"),
    (0x0FB6, "FLT16"),
    (0x103F, "FLT32"),
    (0x170A, "PRSN8"),
    (0x11DD, "KNUTH"),
    (0x1244, "OAT"),
    (0x13F0, "PJW"),
    (0x14F6, "SDBM"),
    (0x15DE, "DJB2"),
    (0x169D, "FNV1A"),
    (0x1841, "MMUR3"),
    (0x1C1A, "XXH32"),
    (0x515E, "MD4"),
    (0x5A39, "MD5"),
    (0x6335, "SHA1"),
}

# Clock frequency: times are in counts of 1/2097152 seconds
CLOCK_HZ = 2097152


def build_name_map(tests):
    return {tid: name for tid, name in tests}


def parse_log(filepath):
    """Read the log file and return a dict mapping test ID -> list of raw counts."""
    results = defaultdict(list)

    with open(filepath, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    if len(lines) % 2 != 0:
        print(
            f"Warning: odd number of non-empty lines ({len(lines)}). "
            "The last entry will be ignored.",
            file=sys.stderr,
        )

    for i in range(0, len(lines) - 1, 2):
        try:
            test_id = int(lines[i], 16)
            count = int(lines[i + 1], 16)
        except ValueError as e:
            print(f"Warning: could not parse entry at lines {i+1}-{i+2}: {e}", file=sys.stderr)
            continue
        results[test_id].append(count)

    return results


def format_time(seconds):
    return f"{seconds:.3f} s"


def test_name(test_id, name_map):
    if test_id in name_map:
        return name_map[test_id]
    return f"Unknown (0x{test_id:04X})"


def report(results, name_map, short=False):
    output_parts = []

    # Preserve encounter order (Python 3.7+ dicts are insertion-ordered,
    # and defaultdict inherits that).
    for test_id, counts in results.items():
        name = test_name(test_id, name_map)
        times_s = [c / CLOCK_HZ for c in counts]
        n = len(times_s)
        avg_t = sum(times_s) / n

        lines = [f"{name} ran {n} time{'s' if n != 1 else ''}:"]

        if not short:
            times_str = ", ".join(format_time(t) for t in times_s)
            lines.append(f"Times: {times_str}")
            lines.append(f"Minimum time: {format_time(min(times_s))}")

        lines.append(f"Average time: {format_time(avg_t)}")
        output_parts.append("\n".join(lines))

    return "\n\n".join(output_parts)


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Parse a custom benchmarking log file.")
    parser.add_argument("log_file", help="Path to the log file")
    parser.add_argument(
        "-s", "--short",
        action="store_true",
        help="Short report: omit the individual times list and minimum time",
    )
    args = parser.parse_args()

    filepath = args.log_file
    name_map = build_name_map(test_list)

    try:
        results = parse_log(filepath)
    except FileNotFoundError:
        print(f"Error: file not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    if not results:
        print("No valid entries found in the log file.", file=sys.stderr)
        sys.exit(1)

    print(report(results, name_map, short=args.short))


if __name__ == "__main__":
    main()