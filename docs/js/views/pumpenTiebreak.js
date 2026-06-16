// PumpenTiebreakView — port of PumpenTiebreakView.swift
import { escapeHtml, parseIntSafe } from "../format.js";
import { playerInputCardHtml, bindPlayerInputCards } from "./tiebreakShared.js";

export function mountPumpenTiebreak(card, vm, ctx) {
  let runde = 1;
  let inputs = vm.getPumpTiedPlayers().map((name) => ({ name, punkte: "", pumpen: 0, neuner: 0, kranz: 0 }));
  let aufgelöst = false;
  let sieger = null;
  const pumpExtras = {};

  function render() {
    card.innerHTML = `
      <div class="sheet-toolbar">
        <button class="sheet-link cancel" data-act="abbrechen">Abbrechen</button>
        <h2>Pumpenstechen – Runde ${runde}</h2>
        <span style="width:70px"></span>
      </div>
      <div class="sheet-body" style="display:flex;flex-direction:column">
        <div style="text-align:center;padding:12px 16px">
          <div style="font-size:14px;color:var(--kb-text-secondary)">Gleichstand bei Pumpen! Pumpenstechen erforderlich.</div>
          <div style="font-size:12px;color:var(--kb-text-tertiary)">Spieler: ${escapeHtml(inputs.map((i) => i.name).join(", "))}</div>
        </div>
        <div class="kb-row-divider"></div>
        ${aufgelöst ? weiterHtml() : eingabeHtml()}
      </div>
    `;
    attach();
  }

  function eingabeHtml() {
    return `
      <div class="kb-screen" style="max-width:520px">
        ${inputs.map((inp, i) => playerInputCardHtml(inp, i)).join("")}
        <button class="kb-btn prominent block" data-act="auswerten">✓ Runde auswerten</button>
      </div>
    `;
  }

  function weiterHtml() {
    return `
      <div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:20px;padding:24px">
        <div style="font-size:60px">🏆</div>
        ${
          sieger
            ? `<div style="font-size:32px;font-weight:700;color:var(--kb-brass-500)">${escapeHtml(sieger)}</div>
               <div style="font-size:18px;color:var(--kb-text-secondary)">hat das Pumpenstechen gewonnen!</div>`
            : `<div style="font-size:28px;font-weight:700">Pumpenstechen aufgelöst</div>`
        }
        <button class="kb-btn prominent" data-act="weiter">→ Weiter</button>
      </div>
    `;
  }

  function attach() {
    card.querySelector("[data-act='abbrechen']").addEventListener("click", () => ctx.close());

    const ausw = card.querySelector("[data-act='auswerten']");
    if (ausw) ausw.addEventListener("click", auswerten);

    const weiterBtn = card.querySelector("[data-act='weiter']");
    if (weiterBtn)
      weiterBtn.addEventListener("click", () => {
        ctx.close();
        ctx.openSheet(vm.hasTrueTie() ? "tiebreak" : "billing");
      });

    bindPlayerInputCards(card, inputs, render);
  }

  function auswerten() {
    for (const inp of inputs) {
      pumpExtras[inp.name] = (pumpExtras[inp.name] || 0) + parseIntSafe(inp.punkte);
    }
    const values = Object.values(pumpExtras);
    const maxPts = Math.max(...values);
    const minPts = Math.min(...values);

    if (maxPts !== minPts) {
      const ordered = Object.entries(pumpExtras)
        .sort((a, b) => b[1] - a[1])
        .map(([name]) => name);
      vm.setPumpRank(ordered);
      sieger = ordered[0];
      aufgelöst = true;
      render();
    } else {
      runde += 1;
      inputs = inputs.map((inp) => ({ name: inp.name, punkte: "", pumpen: 0, neuner: 0, kranz: 0 }));
      render();
    }
  }

  render();
}
