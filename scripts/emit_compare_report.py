#!/usr/bin/env python3
"""Print timing + binary-size summary for compare_load.sh / compare_all.sh.

Each run argument is: Label:seconds:path
  - seconds: float wall seconds, or empty if skipped
  - path:    filesystem path to the server binary (or tool), or empty

Rows whose label contains "Fortran" are **payload tooling** (e.g. gen_bulk_payloads), not HTTP
bulk_insert; they appear in the summary table but are excluded from fastest/slowest analysis.

Optional:
  --write-md PATH   Also write a Markdown report (for git / uploads)
  --note TEXT       Extra line(s) in the Markdown preamble (e.g. COUNT=… PORT=…)
"""

from __future__ import annotations

import argparse
import datetime as _dt
import os
import socket
import sys

_UTC = _dt.timezone.utc


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


def parse_runs(args: list[str]) -> list[tuple[str, float | None, str | None]]:
    out: list[tuple[str, float | None, str | None]] = []
    for arg in args:
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


def is_http_bulk_row(label: str) -> bool:
    """False for Fortran payload-generator rows (not comparable to bulk_insert on a server)."""
    return "Fortran" not in label


def fmt_sec(sec: float | None) -> str:
    if sec is None:
        return "—"
    if sec >= 10:
        return f"{sec:.1f}"
    if sec >= 1:
        return f"{sec:.2f}"
    return f"{sec:.3f}"


def emit_plain(rows: list[tuple[str, float | None, int | None]]) -> None:
    print("")
    print("=== Comparison summary ===")
    print("")
    print(f"{'Variant':<28} {'wall time (s)':>14} {'binary size':>16}")
    print("-" * 60)
    for label, sec, sz in rows:
        ts = fmt_sec(sec)
        bs = human_bytes(sz)
        print(f"{label:<28} {ts:>14} {bs:>16}")

    fortran_rows = [(l, t, s) for l, t, s in rows if not is_http_bulk_row(l)]
    if fortran_rows:
        print("")
        print(
            "--- Note (Fortran) ---",
            "Wall time is NDJSON payload generation (gen_bulk_payloads), not POST load to an API.",
            sep="\n",
        )

    valid_times = [(l, t) for l, t, _ in rows if t is not None and is_http_bulk_row(l)]
    if len(valid_times) >= 1:
        print("")
        print("--- Timing analysis (HTTP servers, bulk_insert only) ---")
        ft = min(t for _, t in valid_times)
        names_fast = [l for l, t in valid_times if t == ft]
        ft_s = f"{ft:.3f}" if ft < 10 else f"{ft:.2f}"
        print(f"Fastest bulk_insert wall time: {ft_s} s ({', '.join(names_fast)}).")
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

    valid_sizes = [(l, s) for l, _, s in rows if s is not None and is_http_bulk_row(l)]
    if len(valid_sizes) >= 1:
        print("")
        print("--- Binary size analysis (HTTP server binaries only) ---")
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

    if fortran_rows:
        print("")
        print("--- Fortran binary (payload tool) ---")
        for label, t, s in fortran_rows:
            ts = fmt_sec(t)
            bs = human_bytes(s)
            print(f"  • {label}: {ts} s, {bs}")

    print("")


def emit_markdown(
    rows: list[tuple[str, float | None, int | None]],
    *,
    title: str,
    note: str | None,
) -> str:
    now = _dt.datetime.now(_UTC).strftime("%Y-%m-%d %H:%M:%S UTC")
    host = socket.gethostname()
    lines = [
        f"# {title}",
        "",
        "| Field | Value |",
        "|-------|-------|",
        f"| Generated | `{now}` |",
        f"| Host | `{host}` |",
    ]
    if note:
        for part in note.strip().split("\n"):
            if part.strip():
                lines.append(f"| Note | {part.strip()} |")
    lines.extend(
        [
            "",
            "## Summary",
            "",
            "| Variant | wall time (s) | binary size |",
            "|---------|---------------|-------------|",
        ]
    )
    for label, sec, sz in rows:
        esc = label.replace("|", "\\|")
        lines.append(f"| {esc} | {fmt_sec(sec)} | {human_bytes(sz)} |")

    fortran_rows = [(l, t, s) for l, t, s in rows if not is_http_bulk_row(l)]
    if fortran_rows:
        lines.extend(
            [
                "",
                "**Fortran row:** time is `gen_bulk_payloads` (NDJSON for `bulk_insert`), not HTTP server load.",
            ]
        )

    valid_times = [(l, t) for l, t, _ in rows if t is not None and is_http_bulk_row(l)]
    if len(valid_times) >= 1:
        ft = min(t for _, t in valid_times)
        names_fast = [l for l, t in valid_times if t == ft]
        ft_s = f"{ft:.3f}" if ft < 10 else f"{ft:.2f}"
        lines.extend(
            [
                "",
                "## Timing analysis (HTTP servers, bulk_insert only)",
                "",
                f"**Fastest bulk_insert:** {ft_s} s ({', '.join(names_fast)}).",
                "",
            ]
        )
        eps = 1e-9
        for label, t in valid_times:
            if abs(t - ft) < eps:
                note = "fastest" if len(names_fast) == 1 else "tied fastest"
            elif ft < eps:
                note = "slower (baseline near 0 s)"
            else:
                pct = 100.0 * (t - ft) / ft
                note = f"{pct:+.1f}% slower than fastest ({ft_s} s)"
            t_s = f"{t:.3f}" if t < 10 else f"{t:.2f}"
            lines.append(f"- **{label}:** {t_s} s — {note}")

    valid_sizes = [(l, s) for l, _, s in rows if s is not None and is_http_bulk_row(l)]
    if len(valid_sizes) >= 1:
        sm = min(s for _, s in valid_sizes)
        lg = max(s for _, s in valid_sizes)
        names_sm = [l for l, s in valid_sizes if s == sm]
        names_lg = [l for l, s in valid_sizes if s == lg]
        lines.extend(
            [
                "",
                "## Binary size analysis (HTTP server binaries only)",
                "",
                f"**Smallest:** {human_bytes(sm)} ({', '.join(names_sm)}).  ",
                f"**Largest:** {human_bytes(lg)} ({', '.join(names_lg)}).",
                "",
            ]
        )
        for label, s in valid_sizes:
            ratio = s / sm if sm else 0.0
            if s == sm:
                note = "smallest" if len(names_sm) == 1 else "tied smallest"
            else:
                note = f"{ratio:.2f}× the smallest ({human_bytes(sm)})"
            lines.append(f"- **{label}:** {human_bytes(s)} — {note}")

    if fortran_rows:
        lines.extend(["", "## Fortran payload tool", ""])
        for label, t, s in fortran_rows:
            esc = label.replace("|", "\\|")
            lines.append(f"- **{esc}:** {fmt_sec(t)} s, {human_bytes(s)}")

    lines.append("")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description="Compare report for bulk_insert runs.")
    ap.add_argument(
        "--write-md",
        metavar="PATH",
        help="Write Markdown report to PATH (directories are created).",
    )
    ap.add_argument(
        "--title",
        default="API stack comparison (bulk_insert)",
        help="Markdown document title",
    )
    ap.add_argument(
        "--note",
        default=None,
        help="Freeform note for Markdown (use \\n for multiple lines in shell)",
    )
    ap.add_argument(
        "runs",
        nargs="+",
        metavar="Label:seconds:path",
        help="One or more Label:seconds:path",
    )
    ns = ap.parse_args()

    parsed = parse_runs(ns.runs)
    rows: list[tuple[str, float | None, int | None]] = []
    for label, sec, path in parsed:
        rows.append((label, sec, file_size(path)))

    emit_plain(rows)

    if ns.write_md:
        md = emit_markdown(rows, title=ns.title, note=ns.note)
        out = os.path.abspath(ns.write_md)
        _dir = os.path.dirname(out)
        if _dir:
            os.makedirs(_dir, exist_ok=True)
        with open(out, "w", encoding="utf-8") as f:
            f.write(md)
        print(f"Markdown report written: {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
