// Regelbuch — view, edit, add and delete club rules stored in the `regeln` table.
import { escapeHtml } from "../format.js";
import { DB } from "../db.js";
import { alertHostRender } from "../components.js";

export function mountRulebook(el) {
  let regeln = DB.ladeRegeln();
  let editingId = null;
  let editText = "";
  let editBetrag = "";
  // adding: null | { paragraph, paragrafTitel, isNewParagraph }
  let adding = null;
  let addTitel = "";
  let addText = "";
  let addBetrag = "";
  let addParagrafTitel = "";

  function grouped() {
    const sections = new Map();
    for (const r of regeln) {
      const key = r.paragraph;
      if (!sections.has(key)) sections.set(key, { titel: r.paragraf_titel, regeln: [] });
      sections.get(key).regeln.push(r);
    }
    return sections;
  }

  function addFormHtml() {
    return `
      <div class="kb-regel-row editing" data-add-form>
        ${adding.isNewParagraph ? `
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px">
          <label style="font-size:13px;color:var(--kb-text-secondary);white-space:nowrap">§${adding.paragraph} Titel:</label>
          <input type="text" class="kb-text-input" data-field="add-paragraf-titel" value="${escapeHtml(addParagrafTitel)}" style="flex:1" placeholder="z.B. §${adding.paragraph} Sonderregeln" />
        </div>` : ""}
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px">
          <label style="font-size:13px;color:var(--kb-text-secondary);white-space:nowrap">Titel:</label>
          <input type="text" class="kb-text-input" data-field="add-titel" value="${escapeHtml(addTitel)}" style="flex:1" placeholder="Kurztitel der Regel" />
        </div>
        <textarea class="kb-notiz-textarea" data-field="add-text" style="min-height:80px;margin-bottom:8px" placeholder="Regeltext">${escapeHtml(addText)}</textarea>
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px">
          <label style="font-size:13px;color:var(--kb-text-secondary);white-space:nowrap">Strafe / Betrag:</label>
          <input type="text" class="kb-text-input" data-field="add-betrag" value="${escapeHtml(addBetrag)}" style="flex:1;max-width:180px" placeholder="z.B. Runde, 5 €, —" />
        </div>
        <div style="display:flex;gap:6px;justify-content:flex-end">
          <button class="kb-btn" data-act="cancel-add">Abbrechen</button>
          <button class="kb-btn prominent" data-act="save-add">Hinzufügen</button>
        </div>
      </div>`;
  }

  function render() {
    const sections = grouped();
    let html = `<div class="kb-screen wide"><div class="kb-screen-title">Regelbuch</div>`;

    for (const [para, sec] of sections) {
      html += `<div class="kb-group">
        <div class="kb-group-header" style="display:flex;align-items:center;justify-content:space-between">
          <span>${escapeHtml(sec.titel)}</span>
          <button class="kb-btn" data-act="add-rule" data-paragraph="${para}" data-titel="${escapeHtml(sec.titel)}" title="Regel zu diesem Paragraphen hinzufügen">＋</button>
        </div>
        <div class="kb-group-body">`;

      sec.regeln.forEach((r, idx) => {
        const isEditing = editingId === r.id;
        const isLast = idx === sec.regeln.length - 1 && !(adding && !adding.isNewParagraph && adding.paragraph === para);

        if (isEditing) {
          html += `
          <div class="kb-regel-row editing" data-id="${r.id}">
            <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px">
              <div style="font-size:13px;font-weight:700;color:var(--kb-primary)">§${para}.${r.absatz} ${escapeHtml(r.absatz_titel)}</div>
              <div style="display:flex;gap:6px">
                <button class="kb-btn tint-danger" data-act="delete" data-id="${r.id}">Löschen</button>
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

      if (adding && !adding.isNewParagraph && adding.paragraph === para) {
        html += addFormHtml();
      }

      html += `</div></div>`;
    }

    if (adding && adding.isNewParagraph) {
      html += `<div class="kb-group">
        <div class="kb-group-header">Neuer Paragraph</div>
        <div class="kb-group-body">${addFormHtml()}</div>
      </div>`;
    } else if (!adding) {
      html += `<div style="display:flex;justify-content:center;margin-top:12px">
        <button class="kb-btn" data-act="add-paragraph">＋ Neuer Paragraph</button>
      </div>`;
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

  function startAdd(paragraph, paragrafTitel, isNewParagraph) {
    adding = { paragraph, paragrafTitel, isNewParagraph };
    addTitel = "";
    addText = "";
    addBetrag = "";
    addParagrafTitel = "";
    editingId = null;
    render();
    const first = el.querySelector(isNewParagraph ? "input[data-field='add-paragraf-titel']" : "input[data-field='add-titel']");
    if (first) first.focus();
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
        adding = null;
        render();
        // Focus textarea after render
        const ta = el.querySelector("textarea[data-field='text']");
        if (ta) ta.focus();
      });
    });

    el.querySelectorAll("[data-act='add-rule']").forEach((btn) => {
      btn.addEventListener("click", () => {
        startAdd(Number(btn.dataset.paragraph), btn.dataset.titel, false);
      });
    });

    el.querySelector("[data-act='add-paragraph']")?.addEventListener("click", () => {
      startAdd(DB.naechsterParagraph(), "", true);
    });

    el.querySelector("[data-act='cancel-add']")?.addEventListener("click", () => {
      adding = null;
      render();
    });

    el.querySelector("[data-act='save-add']")?.addEventListener("click", () => {
      const titel = addTitel.trim();
      const paragrafTitel = adding.isNewParagraph
        ? (addParagrafTitel.trim() || `§${adding.paragraph}`)
        : adding.paragrafTitel;
      if (!titel && !addText.trim()) return; // nothing entered
      DB.neueRegel({
        paragraph: adding.paragraph,
        paragrafTitel,
        absatzTitel: titel,
        regelText: addText.trim(),
        betragStrafe: addBetrag.trim(),
      });
      regeln = DB.ladeRegeln();
      adding = null;
      render();
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

    el.querySelector("[data-act='delete']")?.addEventListener("click", (e) => {
      const id = Number(e.currentTarget.dataset.id);
      const r = regeln.find((x) => x.id === id);
      if (!r) return;
      alertHostRender({
        title: "Regel löschen?",
        message: `§${r.paragraph}.${r.absatz} „${r.absatz_titel}" wird endgültig gelöscht.`,
        buttons: [
          { label: "Abbrechen", role: "cancel" },
          {
            label: "Löschen",
            role: "destructive",
            onClick: () => {
              DB.loescheRegel(id);
              regeln = DB.ladeRegeln();
              editingId = null;
              render();
            },
          },
        ],
      });
    });

    // Live sync editing fields into local state so re-render doesn't lose input
    el.querySelector("textarea[data-field='text']")?.addEventListener("input", (e) => {
      editText = e.target.value;
    });
    el.querySelector("input[data-field='betrag']")?.addEventListener("input", (e) => {
      editBetrag = e.target.value;
    });
    el.querySelector("input[data-field='add-titel']")?.addEventListener("input", (e) => {
      addTitel = e.target.value;
    });
    el.querySelector("textarea[data-field='add-text']")?.addEventListener("input", (e) => {
      addText = e.target.value;
    });
    el.querySelector("input[data-field='add-betrag']")?.addEventListener("input", (e) => {
      addBetrag = e.target.value;
    });
    el.querySelector("input[data-field='add-paragraf-titel']")?.addEventListener("input", (e) => {
      addParagrafTitel = e.target.value;
    });
  }

  render();
}
