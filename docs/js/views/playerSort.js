// PlayerSortView — port of PlayerSortView.swift
import { escapeHtml } from "../format.js";
import { pill } from "../components.js";

export function mountPlayerSort(card, vm, ctx) {
  let orderedNames = [];

  const letzte = vm.letzterSpieltag;
  const pending = vm.pendingAttendees;
  const lastFiltered = letzte.filter((n) => pending.includes(n));
  const missing = pending.filter((n) => !lastFiltered.includes(n));
  orderedNames = [...lastFiltered, ...missing];

  function render() {
    card.innerHTML = `
      <div class="sheet-toolbar">
        <button class="sheet-link cancel" data-act="zurueck">Zurück</button>
        <h2>Spielerreihenfolge</h2>
        <button class="sheet-link" data-act="starten" style="font-weight:700;color:var(--kb-primary)">Spiel starten</button>
      </div>
      <div class="sheet-body">
        <div style="text-align:center;color:var(--kb-text-secondary);font-size:14px;padding:16px">
          Reihenfolge der Spieler festlegen
        </div>
        <div class="kb-screen" style="padding-top:0;max-width:500px">
          <div class="kb-group-body">
            ${orderedNames
              .map(
                (name, i) => `
              <div class="kb-row" data-name="${escapeHtml(name)}">
                <div class="leading" style="display:flex;align-items:center;gap:10px">
                  <span style="color:var(--kb-text-tertiary)">☰</span>
                  <span style="font-weight:600">${escapeHtml(name)}</span>
                  ${vm.pendingGäste.some((g) => g.name === name) ? pill("Gast", "guest") : ""}
                </div>
                <div class="trailing" style="display:flex;gap:6px">
                  <button data-up="${i}" ${i === 0 ? "disabled" : ""} style="border:none;background:var(--kb-fill-tertiary);width:32px;height:32px;border-radius:8px;font-size:16px">↑</button>
                  <button data-down="${i}" ${i === orderedNames.length - 1 ? "disabled" : ""} style="border:none;background:var(--kb-fill-tertiary);width:32px;height:32px;border-radius:8px;font-size:16px">↓</button>
                </div>
              </div>
              ${i < orderedNames.length - 1 ? `<div class="kb-row-divider"></div>` : ""}
            `
              )
              .join("")}
          </div>
        </div>
      </div>
    `;
    attach();
  }

  function attach() {
    card.querySelector("[data-act='zurueck']").addEventListener("click", () => {
      vm.rollbackStartgebuehren();
      ctx.close();
      ctx.openSheet("attendance");
    });
    card.querySelector("[data-act='starten']").addEventListener("click", () => {
      vm.spielStarten(orderedNames, vm.pendingGäste);
      ctx.close();
      ctx.rerenderApp();
    });
    card.querySelectorAll("[data-up]").forEach((btn) =>
      btn.addEventListener("click", () => {
        const i = Number(btn.dataset.up);
        [orderedNames[i - 1], orderedNames[i]] = [orderedNames[i], orderedNames[i - 1]];
        render();
      })
    );
    card.querySelectorAll("[data-down]").forEach((btn) =>
      btn.addEventListener("click", () => {
        const i = Number(btn.dataset.down);
        [orderedNames[i + 1], orderedNames[i]] = [orderedNames[i], orderedNames[i + 1]];
        render();
      })
    );
  }

  render();
}
