// Formatting helpers — mirrors Swift's formatDatum()/round2()/"%.2f €" usage.

export function round2(val) {
  return Math.round((val + Number.EPSILON) * 100) / 100;
}

export function money(val) {
  const v = round2(val || 0);
  const sign = v < 0 ? "-" : "";
  const abs = Math.abs(v).toFixed(2).replace(".", ",");
  return `${sign}${abs} €`;
}

export function moneySigned(val, withPlus = true) {
  const v = round2(val || 0);
  if (v < 0) return money(v);
  return withPlus ? `+${money(v)}` : money(v);
}

export function parseDecimal(str) {
  if (!str) return 0;
  const cleaned = String(str).replace(",", ".").trim();
  const n = parseFloat(cleaned);
  return Number.isFinite(n) ? n : 0;
}

export function parseIntSafe(str) {
  const n = parseInt(str, 10);
  return Number.isFinite(n) ? n : 0;
}

export function formatDatum(date = new Date()) {
  const d = String(date.getDate()).padStart(2, "0");
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const y = date.getFullYear();
  return `${d}.${m}.${y}`;
}

export function uid() {
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}

export function escapeHtml(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
