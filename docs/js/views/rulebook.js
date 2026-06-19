// Regelbuch — view and edit club rules stored in the `regeln` table.
import { escapeHtml } from "../format.js";
import { DB } from "../db.js";

export function mountRulebook(el) {
  let regeln = DB.ladeRegeln();
  let editingId = null;
  let editText = "";
  let editBetrag = "";

  function grouped() {
    const sections = new Map();
    for (const r of regeln) {
      const key = r.paragraph;
      if (!sections.has(key)) sections.set(key, { titel: r.paragraf_titel, regeln: [] });
      sections.get(key).regeln.push(r);
    }
    return sections;
  }

  function render() {
    const sections = grouped();
    let html = `<div class="kb-screen wide"><div class="kb-screen-title">Regelbuch</div>`;

    for (const [para, sec] of sections) {
      html += `<div class="kb-group">
        <div class="kb-group-header">${escapeHtml(sec.titel)}</div>
        <div class="kb-group-body">`;

      sec.regeln.forEach((r, idx) => {
        const isEditing = editingId === r.id;
        const isLast = idx === sec.regeln.length - 1;

        if (isEditing) {
          html += `
          <div class="kb-regel-row editing" data-id="${r.id}">
            <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px">
              <div style="font-size:13px;font-weight:700;color:var(--kb-primary)">§${para}.${r.absatz} ${escapeHtml(r.absatz_titel)}</div>
              <div style="display:flex;gap:6px">
                <button class="kb-btn" data-act="cancel-edit">Abbrechen</button>
                <button class="kb-btn prominent" data-act="save-edit" data-id="${r.id}">Speichern</button>
              </div>
            </div>
            <textarea class="kb-notiz-textarea" data-field="text" style="min-height:80px;margin-bottom:8px">${escapeHtml(editText)}</textarea>
            <div style="display:flex;align-items:center;gap:8px">
              <label style="font-size:13px;color:var(--kb-text-secondary);white-space:nowrap">Strafe / Betrag:</label>
              <input type="text" class="kb-text-input" data-field="betrag" value="${escapeHtml(editBetrag)}" style="flex:1;max-width:180px" placeholder="z.B. Runde, 5 €, —" />
            </div>
          </div>`;
        } else {
          const hasBetrag = r.betrag_strafe && r.betrag_strafe.trim();
          html += `
          <div class="kb-regel-row" data-id="${r.id}">
            <div style="display:flex;align-items:flex-start;gap:8px">
              <div style="flex:1;min-width:0">
                <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px">
                  <span style="font-size:13px;font-weight:700;color:var(--kb-text-secondary);white-space:nowrap">§${para}.${r.absatz}</span>
                  <span style="font-weight:600">${escapeHtml(r.absatz_titel)}</span>
                  ${hasBetrag ? `<span class="kb-pill ${betragPillClass(r.betrag_strafe)}" style="margin-left:auto;white-space:nowrap">${escapeHtml(r.betrag_strafe)}</span>` : ""}
                </div>
                ${r.regel_text ? `<div style="font-size:14px;color:var(--kb-text-secondary);line-height:1.45">${escapeHtml(r.regel_text)}</div>` : ""}
              </div>
              <button class="kb-btn" data-act="edit" data-id="${r.id}" style="flex-shrink:0;margin-top:2px">✎</button>
            </div>
          </div>`;
        }

        if (!isLast) html += `<div class="kb-row-divider"></div>`;
      });

      html += `</div></div>`;
    }

    html += `</div>`;
    el.innerHTML = html;
    attach();
  }

  function betragPillClass(betrag) {
    if (!betrag) return "neutral";
    const b = betrag.toLowerCase();
    if (b === "runde") return "danger";
    if (b === "befreiung") return "success";
    if (b.includes("€")) return "gold";
    return "neutral";
  }

  function attach() {
    el.querySelectorAll("[data-act='edit']").forEach((btn) => {
      btn.addEventListener("click", () => {
        const id = Number(btn.dataset.id);
        const r = regeln.find((x) => x.id === id);
        if (!r) return;
        editingId = id;
        editText = r.regel_text;
        editBetrag = r.betrag_strafe;
        render();
        // Focus textarea after render
        const ta = el.querySelector("textarea[data-field='text']");
        if (ta) ta.focus();
      });
    });

    el.querySelector("[data-act='cancel-edit']")?.addEventListener("click", () => {
      editingId = null;
      render();
    });

    el.querySelector("[data-act='save-edit']")?.addEventListener("click", (e) => {
      const id = Number(e.currentTarget.dataset.id);
      const text = el.querySelector("textarea[data-field='text']")?.value ?? "";
      const betrag = el.querySelector("input[data-field='betrag']")?.value ?? "";
      DB.speichereRegel(id, text, betrag);
      regeln = DB.ladeRegeln();
      editingId = null;
      render();
    });

    // Live sync editing fields into local state so re-render doesn't lose input
    el.querySelector("textarea[data-field='text']")?.addEventListener("input", (e) => {
      editText = e.target.value;
    });
    el.querySelector("input[data-field='betrag']")?.addEventListener("input", (e) => {
      editBetrag = e.target.value;
    });
  }

  render();
}
