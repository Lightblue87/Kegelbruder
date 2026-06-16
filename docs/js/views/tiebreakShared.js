// Shared PlayerInputCard — port of PlayerInputCard/TiebreakCounter in TiebreakView.swift
import { escapeHtml } from "../format.js";
import { bindNumField } from "../numpad.js";

export function playerInputCardHtml(inp, idx) {
  return `
    <div class="kb-card" data-input="${idx}" style="margin-bottom:16px">
      <div style="font-weight:700;margin-bottom:10px">${escapeHtml(inp.name)}</div>
      <div style="display:flex;gap:16px;flex-wrap:wrap">
        <div style="text-align:center">
          <div style="font-size:12px;color:var(--kb-text-secondary);margin-bottom:4px">Punkte</div>
          <button class="kb-numfield" style="width:70px;height:44px;font-size:18px;font-weight:700" data-punkte="${idx}">${inp.punkte || ""}</button>
        </div>
        ${counter("Pump", idx, "pumpen", inp.pumpen, "var(--kb-pumpe)")}
        ${counter("9er", idx, "neuner", inp.neuner, "var(--kb-neuner)")}
        ${counter("Kranz", idx, "kranz", inp.kranz, "var(--kb-kranz)")}
      </div>
    </div>
  `;
}

function counter(label, idx, field, value, color) {
  return `
    <div style="text-align:center">
      <div style="font-size:12px;color:${color};margin-bottom:4px">${label}</div>
      <div class="counter-cell">
        <button data-tb-counter="${idx}" data-field="${field}" data-delta="-1" style="color:${value > 0 ? color : "var(--kb-text-tertiary)"}">−</button>
        <span class="val" style="color:${value > 0 ? color : "var(--kb-text-tertiary)"}">${value}</span>
        <button data-tb-counter="${idx}" data-field="${field}" data-delta="1" style="color:${color}">+</button>
      </div>
    </div>
  `;
}

export function bindPlayerInputCards(root, inputs, onChange) {
  root.querySelectorAll("[data-punkte]").forEach((btn) => {
    const idx = Number(btn.dataset.punkte);
    bindNumField(
      btn,
      () => inputs[idx].punkte || "",
      (val) => {
        inputs[idx].punkte = val;
        onChange();
      },
      { allowsDecimal: false, placeholder: "" }
    );
  });
  root.querySelectorAll("[data-tb-counter]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const idx = Number(btn.dataset.tbCounter);
      const field = btn.dataset.field;
      const delta = Number(btn.dataset.delta);
      if (field === "pumpen" && inputs[idx].pumpen === 0 && delta < 0) return;
      if (field === "neuner" && inputs[idx].neuner === 0 && delta < 0) return;
      if (field === "kranz" && inputs[idx].kranz === 0 && delta < 0) return;
      inputs[idx][field] = Math.max(0, inputs[idx][field] + delta);
      onChange();
    });
  });
}
