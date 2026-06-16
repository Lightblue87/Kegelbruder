// PlayerManagementView — port of PlayerManagementView.swift / PlayerEditSheet
import { escapeHtml, money, parseDecimal } from "../format.js";
import { pill, alertHostRender } from "../components.js";
import { bindNumField } from "../numpad.js";

export function mountPlayerManagement(el, vm, ctx) {
  function sortedPlayers() {
    return Object.entries(vm.mitglieder).sort((a, b) => a[0].localeCompare(b[0]));
  }

  function render() {
    const players = sortedPlayers();
    el.innerHTML = `
      <div class="kb-screen">
        <div style="display:flex;align-items:center;justify-content:space-between">
          <div class="kb-screen-title" style="margin-bottom:0">Spieler verwalten</div>
          <button class="kb-btn prominent" data-act="add">+ Hinzufügen</button>
        </div>
        <div class="kb-group" style="margin-top:18px">
          <div class="kb-group-body">
            ${
              players.length === 0
                ? `<div style="padding:24px;text-align:center;color:var(--kb-text-secondary)">Noch keine Spieler angelegt.</div>`
                : players
                    .map(
                      ([name, data], i) => `
              <div class="kb-row">
                <div class="leading">
                  <div style="display:flex;align-items:center;gap:8px">
                    <span style="font-weight:600">${escapeHtml(name)}</span>
                    ${pill(data.typ, data.typ === "Stamm" ? "primary" : "guest")}
                  </div>
                  ${data.offene_zahlung > 0 ? `<div class="u-danger" style="font-size:12px">Offen: ${money(data.offene_zahlung)}</div>` : ""}
                </div>
                <div class="trailing" style="display:flex;gap:14px">
                  <button data-edit="${escapeHtml(name)}" style="border:none;background:none;color:var(--kb-primary);font-size:16px">✎</button>
                  <button data-delete="${escapeHtml(name)}" style="border:none;background:none;color:var(--kb-danger);font-size:16px">🗑</button>
                </div>
              </div>
              ${i < players.length - 1 ? `<div class="kb-row-divider"></div>` : ""}
            `
                    )
                    .join("")
            }
          </div>
        </div>
      </div>
    `;
    attach();
  }

  function attach() {
    el.querySelector("[data-act='add']").addEventListener("click", () => {
      openEditModal({ titel: "Spieler hinzufügen", initialName: "", initialTyp: "Stamm", initialSchulden: 0 }, (name, typ, schulden) => {
        vm.spielerHinzufügen(name, typ, schulden);
        render();
      });
    });
    el.querySelectorAll("[data-edit]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const name = btn.dataset.edit;
        const data = vm.mitglieder[name];
        openEditModal({ titel: "Spieler bearbeiten", initialName: name, initialTyp: data.typ, initialSchulden: data.offene_zahlung }, (neuerName, typ, schulden) => {
          vm.spielerBearbeiten(name, neuerName, typ, schulden);
          render();
        });
      });
    });
    el.querySelectorAll("[data-delete]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const name = btn.dataset.delete;
        vm.alert = {
          title: `${name} löschen?`,
          message: "Dieser Spieler wird endgültig entfernt.",
          buttons: [
            { label: "Abbrechen", role: "cancel" },
            { label: "Löschen", role: "destructive", onClick: () => { vm.spielerLöschen(name); render(); } },
          ],
        };
        alertHostRender(vm.alert);
      });
    });
  }

  function openEditModal({ titel, initialName, initialTyp, initialSchulden }, onSave) {
    const host = document.createElement("div");
    host.className = "kb-inline-modal-host";
    host.style.position = "fixed";
    host.style.inset = "0";
    host.style.zIndex = "70";
    host.style.display = "flex";
    host.style.alignItems = "center";
    host.style.justifyContent = "center";
    host.style.background = "rgba(10,12,20,0.35)";
    document.body.appendChild(host);

    const state = { name: initialName, typ: initialTyp, schulden: initialSchulden > 0 ? initialSchulden.toFixed(2).replace(".", ",") : "", error: null };

    function renderModal() {
      host.innerHTML = `
        <div class="alert-card" style="max-width:340px;text-align:left">
          <h3 style="text-align:center">${escapeHtml(titel)}</h3>
          <div style="margin:14px 0">
            <input class="kb-text-input" id="pm-name" placeholder="Name" value="${escapeHtml(state.name)}" style="margin-bottom:10px" />
            <div class="kb-segmented" style="margin-bottom:10px">
              <button data-typ="Stamm" class="${state.typ === "Stamm" ? "active" : ""}">Stamm</button>
              <button data-typ="Gast" class="${state.typ === "Gast" ? "active" : ""}">Gast</button>
            </div>
            ${
              state.typ === "Stamm"
                ? `<div class="kb-field-row" style="padding:0">
                    <span>Offener Betrag (€)</span>
                    <button class="kb-numfield align-right ${state.schulden ? "" : "placeholder"}" style="width:90px" id="pm-schulden">${escapeHtml(state.schulden) || "0,00"}</button>
                  </div>`
                : ""
            }
            ${state.error ? `<div class="u-danger" style="font-size:13px;margin-top:8px">${escapeHtml(state.error)}</div>` : ""}
          </div>
          <div class="alert-actions">
            <button id="pm-save" style="color:var(--kb-primary);font-weight:700">Speichern</button>
            <button id="pm-cancel" class="cancel">Abbrechen</button>
          </div>
        </div>
      `;
      host.querySelector("#pm-name").addEventListener("input", (e) => (state.name = e.target.value));
      host.querySelectorAll("[data-typ]").forEach((b) =>
        b.addEventListener("click", () => {
          state.typ = b.dataset.typ;
          renderModal();
        })
      );
      const schuldenBtn = host.querySelector("#pm-schulden");
      if (schuldenBtn) {
        bindNumField(schuldenBtn, () => state.schulden, (val) => (state.schulden = val), { allowsDecimal: true, placeholder: "0,00" });
      }
      host.querySelector("#pm-cancel").addEventListener("click", () => host.remove());
      host.querySelector("#pm-save").addEventListener("click", () => {
        const n = state.name.trim();
        if (!n) {
          state.error = "Name darf nicht leer sein.";
          renderModal();
          return;
        }
        const s = parseDecimal(state.schulden);
        onSave(n, state.typ, state.typ === "Gast" ? 0 : s);
        host.remove();
      });
    }

    renderModal();
  }

  render();
}
