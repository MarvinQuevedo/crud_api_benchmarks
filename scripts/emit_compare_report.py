#!/usr/bin/env python3
"""Print timing + binary-size summary for compare_load.sh / compare_all.sh.

Each argv is: Label:seconds:path
  - seconds: integer wall seconds, or empty if skipped
  - path:    filesystem path to the server binary, or empty if unknown / skipped
"""

from __future__ import annotations

import os
import sys


def human_bytes(n: int | None) -> str:
    if n is None:
        return "—"
    units = ("B", "KiB", "MiB", "GiB")
    x = float(n)
    i = 0
    while x >= 1024 and i < len(units) - 1:
        x /= 1024
        i += 1
    if i == 0:
        return f"{int(n)} B"
    return f"{x:.2f} {units[i]}"


def file_size(path: str | None) -> int | None:
    if not path or not os.path.isfile(path):
        return None
    return os.path.getsize(path)


def parse_runs(argv: list[str]) -> list[tuple[str, int | None, str | None]]:
    out: list[tuple[str, int | None, str | None]] = []
    for arg in argv:
        parts = arg.split(":", 2)
        if len(parts) != 3:
            print(f"Bad argument (want Label:seconds:path): {arg!r}", file=sys.stderr)
            sys.exit(2)
        label, sec_s, path = parts[0].strip(), parts[1].strip(), parts[2].strip()
        path = path or None
        try:
            sec = float(sec_s) if sec_s else None
        except ValueError:
            sec = None
        out.append((label, sec, path))
    return out


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: emit_compare_report.py Label:seconds:path ...", file=sys.stderr)
        sys.exit(2)

    runs = parse_runs(sys.argv[1:])

    print("")
    print("=== Comparison summary ===")
    print("")
    print(f"{'Variant':<26} {'bulk_insert (s)':>16} {'binary size':>16}")
    print("-" * 60)

    rows: list[tuple[str, float | None, int | None]] = []
    for label, sec, path in runs:
        sz = file_size(path)
        rows.append((label, sec, sz))
        if sec is None:
            ts = "—"
        elif sec >= 10:
            ts = f"{sec:.1f}"
        elif sec >= 1:
            ts = f"{sec:.2f}"
        else:
            ts = f"{sec:.3f}"
        bs = human_bytes(sz)
        print(f"{label:<26} {ts:>16} {bs:>16}")

    valid_times = [(l, t) for l, t, _ in rows if t is not None]
    if len(valid_times) >= 1:
        print("")
        print("--- Timing analysis ---")
        ft = min(t for _, t in valid_times)
        names_fast = [l for l, t in valid_times if t == ft]
        ft_s = f"{ft:.3f}" if ft < 10 else f"{ft:.2f}"
        print(
            f"Fastest bulk_insert wall time: {ft_s} s ({', '.join(names_fast)})."
        )
        eps = 1e-9
        for label, t in valid_times:
            if abs(t - ft) < eps:
                note = "fastest" if len(names_fast) == 1 else "tied fastest"
            elif ft < eps:
                note = "slower (baseline near 0 s — compare % ratios with care)"
            else:
                pct = 100.0 * (t - ft) / ft
                note = f"{pct:+.1f}% slower than fastest ({ft_s} s)"
            t_s = f"{t:.3f}" if t < 10 else f"{t:.2f}"
            print(f"  • {label}: {t_s} s — {note}")

    valid_sizes = [(l, s) for l, _, s in rows if s is not None]
    if len(valid_sizes) >= 1:
        print("")
        print("--- Binary size analysis ---")
        sm = min(s for _, s in valid_sizes)
        lg = max(s for _, s in valid_sizes)
        names_sm = [l for l, s in valid_sizes if s == sm]
        names_lg = [l for l, s in valid_sizes if s == lg]
        print(f"Smallest: {human_bytes(sm)} ({', '.join(names_sm)}).")
        print(f"Largest:  {human_bytes(lg)} ({', '.join(names_lg)}).")
        for label, s in valid_sizes:
            ratio = s / sm if sm else 0.0
            if s == sm:
                note = "smallest" if len(names_sm) == 1 else "tied smallest"
            else:
                note = f"{ratio:.2f}× the smallest binary ({human_bytes(sm)})"
            print(f"  • {label}: {human_bytes(s)} — {note}")

    print("")


if __name__ == "__main__":
    main()
