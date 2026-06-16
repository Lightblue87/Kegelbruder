// TiebreakView (Punktestechen) — port of TiebreakView.swift
import { escapeHtml, parseIntSafe } from "../format.js";
import { playerInputCardHtml, bindPlayerInputCards } from "./tiebreakShared.js";
import { alertHostRender } from "../components.js";

export function mountTiebreak(card, vm, ctx) {
  let runde = 1;
  const namen = vm.getTiedPlayers();
  let inputs = namen.map((name) => ({ name, punkte: "", pumpen: 0, neuner: 0, kranz: 0 }));
  for (const name of namen) delete vm.tiebreakExtras[name];
  let ergebnis = null;

  function render() {
    card.innerHTML = `
      <div class="sheet-toolbar">
        <button class="sheet-link cancel" data-act="abbrechen">Abbrechen</button>
        <h2>Stechen – Runde ${runde}</h2>
        <span style="width:70px"></span>
      </div>
      <div class="sheet-body" style="display:flex;flex-direction:column">
        <div style="text-align:center;padding:12px 16px">
          <div style="font-size:14px;color:var(--kb-text-secondary)">Gleichstand! Stechen erforderlich.</div>
          <div style="font-size:12px;color:var(--kb-text-tertiary)">Spieler: ${escapeHtml(namen.join(", "))}</div>
        </div>
        <div class="kb-row-divider"></div>
        ${ergebnis ? ergebnisHtml() : eingabeHtml()}
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

  function ergebnisHtml() {
    return `
      <div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:20px;padding:24px">
        <div style="font-size:60px">🏆</div>
        <div style="font-size:32px;font-weight:700;color:var(--kb-brass-500)">${escapeHtml(ergebnis)}</div>
        <div style="font-size:18px;color:var(--kb-text-secondary)">hat das Stechen gewonnen!</div>
        <button class="kb-btn prominent" data-act="zur-abrechnung">€ Zur Abrechnung</button>
      </div>
    `;
  }

  function attach() {
    card.querySelector("[data-act='abbrechen']").addEventListener("click", () => ctx.close());

    const ausw = card.querySelector("[data-act='auswerten']");
    if (ausw) ausw.addEventListener("click", auswerten);

    const zur = card.querySelector("[data-act='zur-abrechnung']");
    if (zur)
      zur.addEventListener("click", () => {
        ctx.close();
        ctx.openSheet("billing");
      });

    bindPlayerInputCards(card, inputs, render);
  }

  function auswerten() {
    for (const inp of inputs) {
      vm.addTiebreakStats(inp.name, inp.pumpen, inp.neuner, inp.kranz, parseIntSafe(inp.punkte));
    }
    const kumuliert = inputs.map((inp) => {
      const extra = vm.tiebreakExtras[inp.name] || { punkte: 0, pumpen: 0 };
      return { name: inp.name, punkte: extra.punkte, pumpen: extra.pumpen };
    });
    const maxPunkte = Math.max(0, ...kumuliert.map((k) => k.punkte));
    const vorne = kumuliert.filter((k) => k.punkte === maxPunkte);

    if (vorne.length === 1) {
      ergebnis = vorne[0].name;
      render();
    } else {
      const minPumpen = Math.min(...vorne.map((k) => k.pumpen));
      const mitMinPumpen = vorne.filter((k) => k.pumpen === minPumpen);
      if (mitMinPumpen.length === 1) {
        ergebnis = mitMinPumpen[0].name;
        render();
      } else {
        vm.alert = {
          title: `Gleichstand – Runde ${runde}`,
          message: "Alle Spieler haben die gleichen Punkte. Eine weitere Stechen-Runde ist erforderlich.",
          buttons: [
            {
              label: "Nächste Runde",
              onClick: () => {
                runde += 1;
                inputs = inputs.map((inp) => ({ name: inp.name, punkte: "", pumpen: 0, neuner: 0, kranz: 0 }));
                render();
              },
            },
          ],
        };
        alertHostRender(vm.alert);
      }
    }
  }

  render();
}
