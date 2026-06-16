// GameSessionView + ReadyScreen — port of GameSessionView.swift / ContentView's ReadyScreen.
import { escapeHtml } from "../format.js";
import { emptyState } from "../components.js";
import { bindNumField } from "../numpad.js";

export function renderReadyScreen() {
  return `
    <div class="kb-ready">
      <div class="icon-tile">🎳</div>
      <h1>Bereit zum Kegeln!</h1>
      <p>Starte ein neues Spiel, um die Punkteingabe zu öffnen.</p>
      <button class="kb-btn prominent" data-act="start">▶ Neues Spiel starten</button>
    </div>
  `;
}

export function bindReadyScreen(el, actions) {
  el.querySelector("[data-act='start']")?.addEventListener("click", () => actions.starteNeuesSpiel());
}

function summe(p) {
  return p.punkte.reduce((a, b) => a + b, 0);
}

export function renderGameSession(vm) {
  if (vm.players.length === 0) {
    return emptyState("🎳", "Keine aktiven Spieler", "Starte ein neues Spiel über die Seitenleiste.");
  }
  const winnerName = [...vm.players].sort((a, b) => summe(b) - summe(a))[0]?.name;

  const rows = vm.players
    .map((p) => {
      const isWinner = p.name === winnerName;
      return `
      <div class="game-row ${isWinner ? "winner" : ""}" data-player="${escapeHtml(p.name)}">
        <div class="col-name">
          <div class="pname" style="${isWinner ? "color:var(--kb-brass-500)" : ""}">
            ${escapeHtml(p.name)} ${isWinner ? "👑" : ""}
          </div>
          ${
            p.typ === "Gast"
              ? `<span class="kb-pill guest">Gast</span>`
              : p.offene_zahlung > 0
              ? `<span class="u-danger" style="font-size:12px">Offen ${p.offene_zahlung.toFixed(2).replace(".", ",")} €</span>`
              : ""
          }
        </div>
        <div class="col-cat">${counterCell(p.name, "pumpen", p.pumpen, "var(--kb-pumpe)")}</div>
        <div class="col-cat">${counterCell(p.name, "neuner", p.neuner, "var(--kb-neuner)")}</div>
        <div class="col-cat">${counterCell(p.name, "kranz", p.kranz, "var(--kb-kranz)")}</div>
        ${[0, 1, 2, 3]
          .map(
            (i) => `<div class="col-rd"><button class="score-cell" data-score="${escapeHtml(p.name)}" data-runde="${i}">${p.punkte[i] > 0 ? p.punkte[i] : ""}</button></div>`
          )
          .join("")}
        <div class="col-sum" style="${isWinner ? "color:var(--kb-brass-500)" : ""}">${summe(p)}</div>
      </div>
    `;
    })
    .join("");

  return `
    <div class="game-header-bar">
      <div>
        <h1>Spielstand</h1>
        <div class="meta">Runde ${vm.runde} · ${vm.players.length} Spieler</div>
      </div>
      <button class="kb-btn prominent" data-act="abrechnung">€ Abrechnung</button>
    </div>
    <div class="game-table-wrap">
      <div class="game-table">
        <div class="game-row header">
          <div class="col-name" style="padding-left:4px">Spieler</div>
          <div class="col-cat" style="color:var(--kb-pumpe)">Pump</div>
          <div class="col-cat" style="color:var(--kb-neuner)">9er</div>
          <div class="col-cat" style="color:var(--kb-kranz)">Kranz</div>
          <div class="col-rd">Rd 1</div>
          <div class="col-rd">Rd 2</div>
          <div class="col-rd">Rd 3</div>
          <div class="col-rd">Rd 4</div>
          <div class="col-sum">Summe</div>
        </div>
        ${rows}
      </div>
    </div>
  `;
}

function counterCell(name, field, value, color) {
  return `
    <div class="counter-cell">
      <button data-counter="${escapeHtml(name)}" data-field="${field}" data-delta="-1" style="color:${value > 0 ? color : "var(--kb-text-tertiary)"}">−</button>
      <span class="val" style="color:${value > 0 ? color : "var(--kb-text-tertiary)"}">${value}</span>
      <button data-counter="${escapeHtml(name)}" data-field="${field}" data-delta="1" style="color:${color}">+</button>
    </div>
  `;
}

export function bindGameSession(el, vm, actions) {
  el.querySelectorAll("[data-act='abrechnung']").forEach((b) => b.addEventListener("click", () => actions.abrechnungStarten()));

  el.querySelectorAll("[data-counter]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const name = btn.dataset.counter;
      const field = btn.dataset.field;
      const delta = Number(btn.dataset.delta);
      if (field === "pumpen") vm.updatePumpen(name, delta);
      else if (field === "neuner") vm.updateNeuner(name, delta);
      else if (field === "kranz") vm.updateKranz(name, delta);
      actions.rerender();
    });
  });

  el.querySelectorAll("[data-score]").forEach((btn) => {
    bindNumField(
      btn,
      () => {
        const name = btn.dataset.score;
        const runde = Number(btn.dataset.runde);
        const p = vm.players.find((p) => p.name === name);
        const v = p?.punkte[runde] || 0;
        return v > 0 ? String(v) : "";
      },
      (val) => {
        const name = btn.dataset.score;
        const runde = Number(btn.dataset.runde);
        vm.updatePunkte(name, runde, parseInt(val, 10) || 0);
        actions.rerender();
      },
      { allowsDecimal: false, placeholder: "" }
    );
  });
}
