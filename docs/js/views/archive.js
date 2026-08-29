// ArchiveView — port of ArchiveView.swift / ArchiveDetailView
import { escapeHtml, money } from "../format.js";
import { emptyState } from "../components.js";
import { DB } from "../db.js";

export function mountArchive(el, vm, ctx) {
  let entries = [...DB.ladeHistorie()].reverse();
  let selected = null;
  let searchQuery = "";
  // Notiz edit state per spielId (unsaved edits survive re-render)
  const notizDraft = {};

  function filteredEntries() {
    if (!searchQuery.trim()) return entries;
    const q = searchQuery.trim().toLowerCase();
    return entries.filter((e) => {
      if (e.datum.toLowerCase().includes(q)) return true;
      if (Object.keys(e.players).some((n) => n.toLowerCase().includes(q))) return true;
      if (e.notiz && e.notiz.toLowerCase().includes(q)) return true;
      return false;
    });
  }

  function render() {
    const visible = filteredEntries();
    el.innerHTML = `
      <div style="display:flex;height:100%">
        <div style="width:320px;flex-shrink:0;border-right:1px solid var(--kb-row-divider);overflow-y:auto;display:flex;flex-direction:column">
          <div style="display:flex;align-items:center;justify-content:space-between;padding:16px 16px 8px">
            <div style="font-size:22px;font-weight:700">Archiv</div>
            <button data-act="reload" style="border:none;background:none;font-size:18px">⟲</button>
          </div>
          <div style="padding:0 12px 8px">
            <input
              id="archive-search"
              class="kb-text-input"
              type="search"
              placeholder="Suchen … Datum, Spieler, Notiz"
              value="${escapeHtml(searchQuery)}"
              style="width:100%;box-sizing:border-box"
            />
          </div>
          <div style="flex:1;overflow-y:auto">
          ${
            entries.length === 0
              ? `<div style="padding:24px">${emptyState("🕘", "Noch keine Spiele archiviert", "Spiele werden nach der Abrechnung hier gespeichert.")}</div>`
              : visible.length === 0
              ? `<div style="padding:24px;font-size:13px;color:var(--kb-text-secondary)">Keine Treffer.</div>`
              : visible
                  .map(
                    (entry) => `
              <button class="sidebar-item" data-entry="${entry.spielId}" style="display:block;width:100%;text-align:left;height:auto;${selected?.spielId === entry.spielId ? "background:var(--kb-primary);color:#fff" : ""}">
                <div style="font-weight:700">${entry.transaktionen.some((t) => t.includes("Spielausfall")) ? "🚫 " : ""}${escapeHtml(entry.datum)}</div>
                <div style="font-size:12px;${selected?.spielId === entry.spielId ? "color:rgba(255,255,255,0.85)" : "color:var(--kb-text-secondary)"};display:flex;justify-content:space-between;margin-top:2px">
                  <span>👥 ${Object.keys(entry.players).length} Spieler</span>
                  ${entry.notiz ? `<span>📝</span>` : `<span>📋 ${entry.transaktionen.length} Buchungen</span>`}
                </div>
              </button>
            `
                  )
                  .join("")
          }
          </div>
        </div>
        <div style="flex:1;overflow-y:auto" id="archive-detail">
          ${selected ? detailHtml(selected) : emptyState("🕘", "Spieltag auswählen")}
        </div>
      </div>
    `;
    attach();
  }

  function renderNotizText(text, players) {
    if (!text.trim()) return "";
    // Replace @Name with pill badges for known players
    const escaped = escapeHtml(text);
    return escaped.replace(/@(\S+)/g, (match, name) => {
      const found = Object.keys(players).find((n) => n.toLowerCase() === name.toLowerCase());
      if (found) return `<span class="kb-pill neutral" style="vertical-align:middle">@${escapeHtml(found)}</span>`;
      return match;
    });
  }

  function detailHtml(entry) {
    const order = entry.spieler_reihenfolge || Object.keys(entry.players).sort();
    const players = order.filter((n) => entry.players[n]).map((n) => ({ name: n, data: entry.players[n] }));
    const isSpielausfall = entry.transaktionen.some((t) => t.includes("Spielausfall"));

    const notiz = notizDraft[entry.spielId] ?? entry.notiz ?? "";
    const notizRendered = renderNotizText(entry.notiz || "", entry.players);

    const spielerTableHtml = isSpielausfall
      ? (() => {
          return `
          <div class="kb-group-body" style="margin-bottom:20px">
            <div style="padding:10px 16px;font-size:13px;font-weight:700;color:var(--kb-text-secondary);background:var(--kb-card-bg)">
              🚫 Spielausfall – Stammmitglieder
            </div>
            <div class="kb-row-divider"></div>
            ${players
              .map((p, i) => `
              <div style="display:flex;align-items:center;padding:8px 16px">
                <span style="flex:1">${escapeHtml(p.name)}</span>
                <span class="u-mono" style="font-size:14px;color:var(--kb-danger)">${money(p.data.offene_zahlung)} offen</span>
              </div>
              ${i < players.length - 1 ? `<div class="kb-row-divider"></div>` : ""}
            `).join("")}
          </div>`;
        })()
      : (() => {
          const ranked = [...players]
            .sort((a, b) => b.data.punkte.reduce((x, y) => x + y, 0) - a.data.punkte.reduce((x, y) => x + y, 0))
            .map((p, i) => ({ platz: i + 1, ...p }));
          return `
          <div class="kb-group-body" style="margin-bottom:20px">
            <div style="display:flex;font-size:12px;font-weight:700;padding:8px 16px;background:var(--kb-card-bg)">
              <span style="width:30px">Pl.</span><span style="flex:1">Spieler</span>
              ${[1, 2, 3, 4].map((r) => `<span style="width:40px;text-align:center">Rd${r}</span>`).join("")}
              <span style="width:44px;text-align:center">Σ</span><span style="width:50px;text-align:center">Pump</span>
            </div>
            <div class="kb-row-divider"></div>
            ${ranked.map((p, i) => {
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
              ${i < ranked.length - 1 ? `<div class="kb-row-divider"></div>` : ""}`;
            }).join("")}
          </div>`;
        })();

    return `
      <div style="padding:20px">
        <div style="font-size:28px;font-weight:700;margin-bottom:16px">${escapeHtml(entry.datum)}</div>

        ${spielerTableHtml}

        ${entry.transaktionen.length > 0 ? `
        <div style="font-weight:700;margin-bottom:8px">Transaktionen</div>
        <div class="kb-group-body" style="margin-bottom:20px">
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
        </div>` : ""}

        <div style="font-weight:700;margin-bottom:8px">📝 Notizen</div>
        <div class="kb-group-body" style="margin-bottom:8px">
          ${notizRendered
            ? `<div class="kb-notiz-display" id="notiz-display-${entry.spielId}">${notizRendered}</div>`
            : `<div style="padding:12px 16px;font-size:13px;color:var(--kb-text-tertiary)">Noch keine Notiz für diesen Spieltag.</div>`}
        </div>
        <div style="position:relative">
          <textarea
            id="notiz-input-${entry.spielId}"
            class="kb-notiz-textarea"
            placeholder="Notiz eingeben … @Name für Spielererwähnung"
            data-spielid="${entry.spielId}"
          >${escapeHtml(notiz)}</textarea>
          <div id="mention-dropdown" class="mention-dropdown" style="display:none"></div>
        </div>
        <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin-top:8px">
          <button class="kb-btn tint-danger" data-act="delete-entry" data-spielid="${entry.spielId}">Eintrag löschen</button>
          <div style="display:flex;gap:8px">
            ${notiz !== (entry.notiz || "") ? `<button class="kb-btn" data-act="discard-notiz" data-spielid="${entry.spielId}">Verwerfen</button>` : ""}
            <button class="kb-btn prominent" data-act="save-notiz" data-spielid="${entry.spielId}">Notiz speichern</button>
          </div>
        </div>
      </div>
    `;
  }

  function attach() {
    el.querySelector("[data-act='reload']").addEventListener("click", () => {
      entries = [...DB.ladeHistorie()].reverse();
      render();
    });

    const searchInput = el.querySelector("#archive-search");
    if (searchInput) {
      searchInput.addEventListener("input", () => {
        searchQuery = searchInput.value;
        // Keep scroll position in sidebar by only re-rendering the list portion
        render();
        // Restore focus after re-render
        const next = el.querySelector("#archive-search");
        if (next) { next.focus(); next.setSelectionRange(next.value.length, next.value.length); }
      });
    }

    el.querySelectorAll("[data-entry]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const id = Number(btn.dataset.entry);
        selected = entries.find((e) => e.spielId === id) || null;
        render();
      });
    });

    if (!selected) return;

    // Notiz save
    el.querySelector("[data-act='save-notiz']")?.addEventListener("click", (e) => {
      const spielId = Number(e.currentTarget.dataset.spielid);
      const ta = el.querySelector(`#notiz-input-${spielId}`);
      const text = ta?.value ?? "";
      DB.speichereHistorieNotiz(spielId, text);
      const entry = entries.find((x) => x.spielId === spielId);
      if (entry) entry.notiz = text;
      delete notizDraft[spielId];
      render();
    });

    el.querySelector("[data-act='discard-notiz']")?.addEventListener("click", (e) => {
      const spielId = Number(e.currentTarget.dataset.spielid);
      delete notizDraft[spielId];
      const ta = el.querySelector(`#notiz-input-${spielId}`);
      if (ta) {
        const entry = entries.find((x) => x.spielId === spielId);
        ta.value = entry?.notiz ?? "";
      }
      render();
    });

    // Delete entry
    el.querySelector("[data-act='delete-entry']")?.addEventListener("click", (e) => {
      const spielId = Number(e.currentTarget.dataset.spielid);
      const entry = entries.find((x) => x.spielId === spielId);
      vm.alert = {
        title: "Archiveintrag löschen?",
        message: `„${entry?.datum || spielId}" wird unwiderruflich aus dem Archiv entfernt. Kassenbuchungen bleiben erhalten.`,
        buttons: [
          { label: "Abbrechen", role: "cancel" },
          {
            label: "Löschen",
            role: "destructive",
            onClick: () => {
              DB.löscheHistorieEintrag(spielId);
              entries = entries.filter((x) => x.spielId !== spielId);
              delete notizDraft[spielId];
              if (selected?.spielId === spielId) selected = null;
              render();
            },
          },
        ],
      };
      ctx.showAlert(vm.alert);
    });

    // @mention logic
    const ta = el.querySelector("textarea[data-spielid]");
    const dropdown = el.querySelector("#mention-dropdown");
    if (!ta || !dropdown) return;

    const spielId = Number(ta.dataset.spielid);
    const entry = entries.find((x) => x.spielId === spielId);
    const playerNames = entry ? Object.keys(entry.players) : [];

    ta.addEventListener("input", () => {
      notizDraft[spielId] = ta.value;
      const partial = getMentionPartial(ta);
      if (partial !== null && playerNames.length) {
        const matches = playerNames.filter((n) => n.toLowerCase().startsWith(partial.toLowerCase()));
        if (matches.length) {
          showDropdown(dropdown, ta, matches, partial, (chosen) => {
            insertMention(ta, partial, chosen);
            notizDraft[spielId] = ta.value;
            hideDropdown(dropdown);
          });
          return;
        }
      }
      hideDropdown(dropdown);
    });

    ta.addEventListener("keydown", (e) => {
      if (dropdown.style.display === "none") return;
      const items = dropdown.querySelectorAll(".mention-item");
      const active = dropdown.querySelector(".mention-item.active");
      const idx = active ? [...items].indexOf(active) : -1;
      if (e.key === "ArrowDown") {
        e.preventDefault();
        items[Math.min(idx + 1, items.length - 1)]?.classList.add("active");
        active?.classList.remove("active");
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        active?.classList.remove("active");
        items[Math.max(idx - 1, 0)]?.classList.add("active");
      } else if (e.key === "Enter" || e.key === "Tab") {
        const act = dropdown.querySelector(".mention-item.active") || items[0];
        if (act) {
          e.preventDefault();
          act.click();
        }
      } else if (e.key === "Escape") {
        hideDropdown(dropdown);
      }
    });

    ta.addEventListener("blur", () => setTimeout(() => hideDropdown(dropdown), 150));
  }

  // ---- @mention helpers ----

  function getMentionPartial(ta) {
    const pos = ta.selectionStart;
    const before = ta.value.slice(0, pos);
    const match = before.match(/@(\w*)$/);
    return match ? match[1] : null;
  }

  function insertMention(ta, partial, name) {
    const pos = ta.selectionStart;
    const before = ta.value.slice(0, pos);
    const after = ta.value.slice(pos);
    const replaced = before.replace(/@\w*$/, `@${name} `);
    ta.value = replaced + after;
    const newPos = replaced.length;
    ta.setSelectionRange(newPos, newPos);
    ta.focus();
  }

  function showDropdown(dropdown, ta, matches, partial, onSelect) {
    dropdown.style.display = "block";
    dropdown.innerHTML = matches
      .map(
        (n) =>
          `<button class="mention-item" type="button"><span class="mention-match">@${escapeHtml(n.slice(0, partial.length))}</span>${escapeHtml(n.slice(partial.length))}</button>`
      )
      .join("");
    dropdown.querySelectorAll(".mention-item").forEach((btn, i) => {
      if (i === 0) btn.classList.add("active");
      btn.addEventListener("mousedown", (e) => {
        e.preventDefault();
        onSelect(btn.textContent.trim().replace(/^@/, ""));
      });
    });
  }

  function hideDropdown(dropdown) {
    dropdown.style.display = "none";
    dropdown.innerHTML = "";
  }

  render();
}
