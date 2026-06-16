// ArchiveView — port of ArchiveView.swift / ArchiveDetailView
import { escapeHtml, money } from "../format.js";
import { emptyState } from "../components.js";
import { DB } from "../db.js";

export function mountArchive(el, vm, ctx) {
  let entries = [...DB.ladeHistorie()].reverse();
  let selected = null;

  function render() {
    el.innerHTML = `
      <div style="display:flex;height:100%">
        <div style="width:320px;flex-shrink:0;border-right:1px solid var(--kb-row-divider);overflow-y:auto">
          <div style="display:flex;align-items:center;justify-content:space-between;padding:16px 16px 8px">
            <div style="font-size:22px;font-weight:700">Archiv</div>
            <button data-act="reload" style="border:none;background:none;font-size:18px">⟲</button>
          </div>
          ${
            entries.length === 0
              ? `<div style="padding:24px">${emptyState("🕘", "Noch keine Spiele archiviert", "Spiele werden nach der Abrechnung hier gespeichert.")}</div>`
              : entries
                  .map(
                    (entry) => `
              <button class="sidebar-item" data-entry="${entry.spielId}" style="display:block;width:100%;text-align:left;height:auto;${selected?.spielId === entry.spielId ? "background:var(--kb-primary);color:#fff" : ""}">
                <div style="font-weight:700">${escapeHtml(entry.datum)}</div>
                <div style="font-size:12px;${selected?.spielId === entry.spielId ? "color:rgba(255,255,255,0.85)" : "color:var(--kb-text-secondary)"};display:flex;justify-content:space-between;margin-top:2px">
                  <span>👥 ${Object.keys(entry.players).length} Spieler</span>
                  <span>📋 ${entry.transaktionen.length} Buchungen</span>
                </div>
              </button>
            `
                  )
                  .join("")
          }
        </div>
        <div style="flex:1;overflow-y:auto" id="archive-detail">
          ${selected ? detailHtml(selected) : emptyState("🕘", "Spieltag auswählen")}
        </div>
      </div>
    `;
    attach();
  }

  function detailHtml(entry) {
    const order = entry.spieler_reihenfolge || Object.keys(entry.players).sort();
    const players = order.filter((n) => entry.players[n]).map((n) => ({ name: n, data: entry.players[n] }));
    const ranked = [...players]
      .sort((a, b) => b.data.punkte.reduce((x, y) => x + y, 0) - a.data.punkte.reduce((x, y) => x + y, 0))
      .map((p, i) => ({ platz: i + 1, ...p }));

    return `
      <div style="padding:20px">
        <div style="font-size:28px;font-weight:700;margin-bottom:16px">${escapeHtml(entry.datum)}</div>
        <div class="kb-group-body" style="margin-bottom:20px">
          <div style="display:flex;font-size:12px;font-weight:700;padding:8px 16px;background:var(--kb-card-bg)">
            <span style="width:30px">Pl.</span><span style="flex:1">Spieler</span>
            ${[1, 2, 3, 4].map((r) => `<span style="width:40px;text-align:center">Rd${r}</span>`).join("")}
            <span style="width:44px;text-align:center">Σ</span><span style="width:50px;text-align:center">Pump</span>
          </div>
          <div class="kb-row-divider"></div>
          ${ranked
            .map((p, i) => {
              const sum = p.data.punkte.reduce((a, b) => a + b, 0);
              const isWinner = p.platz === 1;
              return `
              <div style="display:flex;align-items:center;padding:8px 16px;${isWinner ? "background:color-mix(in srgb, var(--kb-brass-400) 7%, transparent)" : ""}">
                <span style="width:30px;font-weight:700;color:${isWinner ? "var(--kb-brass-500)" : "var(--kb-text-secondary)"}">${p.platz}.</span>
                <span style="flex:1;font-weight:${isWinner ? "600" : "400"};color:${isWinner ? "var(--kb-brass-500)" : "inherit"}">${escapeHtml(p.name)}</span>
                ${[0, 1, 2, 3].map((idx) => `<span style="width:40px;text-align:center;font-size:14px;color:var(--kb-text-secondary)" class="u-mono">${p.data.punkte[idx] ?? 0}</span>`).join("")}
                <span style="width:44px;text-align:center;font-weight:700;color:${isWinner ? "var(--kb-brass-500)" : "inherit"}" class="u-mono">${sum}</span>
                <span style="width:50px;text-align:center;font-size:14px;color:var(--kb-pumpe)" class="u-mono">${p.data.pumpen ?? 0}</span>
              </div>
              ${i < ranked.length - 1 ? `<div class="kb-row-divider"></div>` : ""}
            `;
            })
            .join("")}
        </div>

        <div style="font-weight:700;margin-bottom:8px">Transaktionen</div>
        <div class="kb-group-body">
          ${entry.transaktionen
            .map(
              (t, i) => `
            <div style="display:flex;gap:10px;align-items:center;padding:8px 16px">
              <span style="width:8px;height:8px;border-radius:50%;background:${t.includes("| -") ? "var(--kb-danger)" : "var(--kb-success)"};flex-shrink:0"></span>
              <span style="font-size:13px">${escapeHtml(t)}</span>
            </div>
            ${i < entry.transaktionen.length - 1 ? `<div class="kb-row-divider"></div>` : ""}
          `
            )
            .join("")}
        </div>
      </div>
    `;
  }

  function attach() {
    el.querySelector("[data-act='reload']").addEventListener("click", () => {
      entries = [...DB.ladeHistorie()].reverse();
      render();
    });
    el.querySelectorAll("[data-entry]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const id = Number(btn.dataset.entry);
        selected = entries.find((e) => e.spielId === id) || null;
        render();
      });
    });
  }

  render();
}
