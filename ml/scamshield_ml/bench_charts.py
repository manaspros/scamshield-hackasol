"""Slide-ready charts (16:9 PNG + SVG) of base vs fine-tuned models, from ml/reports/bench/*.json.

    uv run --group viz python -m scamshield_ml.bench_charts      # -> docs/benchmark/*.png|svg

Each chart is a dumbbell per model: light dot = base model with the prompt the app ships today (few-shot, raw),
dark dot = the same model after LoRA fine-tuning with the short prompt. Palette: one hue, two validated steps
(blue 250 / blue 550, dataviz ordinal check passes on the light surface).
"""

from __future__ import annotations

import argparse
from pathlib import Path

from scamshield_ml.bench import load_config
from scamshield_ml.bench_report import load_reports

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "benchmark"
SURFACE, INK, INK2, MUTED, GRID, AXIS = "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7"
BASE, TUNED = "#86b6ef", "#1c5cab"
FOOT = "Held-out synthetic test set ({n} rows, EN/HI/Hinglish, templates never seen in training)."


def pairs(reports: list[dict], cfg: dict) -> list[dict]:
    """[{name, base, tuned}] for every model that has both a base few-shot and a fine-tuned short-prompt run."""
    by = {r["system"]: r for r in reports}
    out = []
    for key, model in cfg["models"].items():
        base, tuned = by.get(f"{key}/fewshot/raw"), by.get(f"{key}+ft/short/raw")
        if base and tuned:
            out.append({"key": key, "name": model.get("name", key), "base": base, "tuned": tuned})
    return out


def _style(ax, plt):
    ax.set_facecolor(SURFACE)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.spines["bottom"].set_color(AXIS)
    ax.tick_params(colors=MUTED, length=0, labelsize=10)
    ax.grid(axis="x", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def dumbbell(rows: list[dict], metric, title: str, subtitle: str, unit: str, path: Path, n: int,
             lower_better: bool = False, xmax: float | None = None) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    plt.rcParams.update({"font.family": "DejaVu Sans", "svg.fonttype": "none"})
    fig, ax = plt.subplots(figsize=(10, 5.625), dpi=200)
    fig.patch.set_facecolor(SURFACE)
    _style(ax, plt)
    ys = list(range(len(rows)))[::-1]
    vals = [(metric(r["base"]), metric(r["tuned"])) for r in rows]
    top = xmax or max(max(v) for v in vals) * 1.18
    fmt = (lambda v: f"{v:.0f}%") if unit == "%" else (lambda v: f"{v:,.0f}")
    for y, (b, t) in zip(ys, vals):
        ax.plot([b, t], [y, y], color=AXIS, linewidth=2, zorder=1, solid_capstyle="round")
        for v, c in ((b, BASE), (t, TUNED)):
            ax.scatter([v], [y], s=150, color=c, edgecolors=SURFACE, linewidths=2, zorder=3)
        # Labels sit outside the segment: the smaller value to the left, the larger to the right.
        # The fine-tuned value is the headline (bold, primary ink); the base value is secondary.
        for v, other, tuned in ((b, t, False), (t, b, True)):
            left = v < other
            ax.text(v + (-1 if left else 1) * top * 0.02, y, fmt(v), va="center", ha="right" if left else "left",
                    fontsize=12 if tuned else 11, color=INK if tuned else INK2, weight="bold" if tuned else "normal")
    ax.set_yticks(ys, [r["name"] for r in rows], fontsize=12, color=INK)
    ax.set_xlim(-top * 0.08, top)
    ax.set_ylim(-0.7, len(rows) - 0.3)
    if unit == "%":
        ax.xaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v:.0f}%"))
    fig.text(0.03, 0.94, title, fontsize=17, weight="bold", color=INK)
    fig.text(0.03, 0.885, subtitle + ("  (lower is better)" if lower_better else "  (higher is better)"),
             fontsize=11, color=INK2)
    handles = [plt.Line2D([], [], marker="o", linestyle="", markersize=10, markerfacecolor=c, markeredgecolor=SURFACE,
                          label=l) for c, l in ((BASE, "Base model, app's current prompt"),
                                                (TUNED, "Fine-tuned (LoRA), short prompt"))]
    fig.legend(handles=handles, loc="upper left", bbox_to_anchor=(0.025, 0.86), ncol=2, frameon=False, fontsize=10,
               labelcolor=INK2, handletextpad=0.3, columnspacing=1.5)
    fig.text(0.03, 0.025, FOOT.format(n=n), fontsize=9, color=MUTED)
    fig.subplots_adjust(left=0.2, right=0.96, top=0.74, bottom=0.12)
    for ext in ("png", "svg"):
        fig.savefig(path.with_suffix(f".{ext}"), facecolor=SURFACE)
    plt.close(fig)


def latency_bars(reports: list[dict], path: Path, n: int) -> bool:
    """Measured LiteRT-LM time per message on the host CPU, quantized phone files, base vs fine-tuned."""
    by = {r["system"]: r for r in reports}
    items = [(label, by[s]) for label, s in (
        ("Qwen3.5-0.8B base\n(official int4/int8 file)", "qwen3.5-0.8b/fewshot/litertlm-mixed48"),
        ("Qwen3.5-0.8B fine-tuned\n(our int8 file, short prompt)", "qwen3.5-0.8b+ft/short/litertlm-int8"),
    ) if s in by and by[s]["cost"].get("host_cpu_total_ms_median")]
    if len(items) < 2:
        return False
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(10, 5.625), dpi=200)
    fig.patch.set_facecolor(SURFACE)
    _style(ax, plt)
    ys = list(range(len(items)))[::-1]
    for y, (label, r), c in zip(ys, items, (BASE, TUNED)):
        ms, ttft = r["cost"]["host_cpu_total_ms_median"], r["cost"]["host_cpu_ttft_ms_median"]
        ax.barh([y], [ms], height=0.32, color=c, edgecolor=SURFACE, linewidth=2)
        ax.text(ms + 20, y + 0.05, f"{ms:,.0f} ms", va="bottom", fontsize=13, color=INK, weight="bold")
        ax.text(ms + 20, y - 0.05, f"first token {ttft:,.0f} ms", va="top", fontsize=10, color=INK2)
    ax.set_yticks(ys, [l for l, _ in items], fontsize=11, color=INK)
    ax.set_xlim(0, max(r["cost"]["host_cpu_total_ms_median"] for _, r in items) * 1.45)
    ax.xaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v:,.0f} ms"))
    fig.text(0.03, 0.94, "Time to classify one message", fontsize=17, weight="bold", color=INK)
    fig.text(0.03, 0.885, "Median, LiteRT-LM runtime, 4 CPU threads, quantized on-device files  (lower is better)",
             fontsize=11, color=INK2)
    fig.text(0.03, 0.05, FOOT.format(n=n), fontsize=9, color=MUTED)
    fig.text(0.03, 0.02, "Measured on a desktop x86 CPU: compare the bars; absolute phone times will differ.",
             fontsize=9, color=MUTED)
    fig.subplots_adjust(left=0.3, right=0.96, top=0.8, bottom=0.15)
    for ext in ("png", "svg"):
        fig.savefig(path.with_suffix(f".{ext}"), facecolor=SURFACE)
    plt.close(fig)
    return True


def main() -> list[str]:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, default=OUT)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    reports, cfg = load_reports(), load_config()
    rows = pairs(reports, cfg)
    if not rows:
        raise SystemExit("no base + fine-tuned pairs in ml/reports/bench yet")
    n = rows[0]["tuned"]["rows"]
    made = []
    dumbbell(rows, lambda r: 100 * r["labels"]["accuracy"], "Fine-tuning makes small models accurate",
             "Accuracy over SAFE / SUSPICIOUS / SCAM", "%", a.out / "accuracy", n, xmax=105)
    dumbbell(rows, lambda r: 100 * r["binary"]["overall"]["fpr"], "Far fewer false alarms",
             "Share of genuine messages wrongly flagged as scam or suspicious", "%", a.out / "false_alarms", n,
             lower_better=True)
    dumbbell(rows, lambda r: 100 * r["binary"]["overall"]["macro_f1"], "Better at naming the scam type",
             "Scam-type macro-F1 on scam messages (x100)", "", a.out / "scam_type", n)
    dumbbell(rows, lambda r: r["cost"]["prompt_tokens_mean"], "8x less text to read per message",
             "Prompt tokens the phone processes before answering", "", a.out / "prompt_tokens", n,
             lower_better=True)
    made += ["accuracy", "false_alarms", "scam_type", "prompt_tokens"]
    if latency_bars(reports, a.out / "latency", n):
        made.append("latency")
    print("\n".join(str(a.out / f"{m}.png") for m in made))
    return made


if __name__ == "__main__":
    main()
