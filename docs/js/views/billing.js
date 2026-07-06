// BillingView — port of BillingView.swift
import { escapeHtml, money, parseDecimal } from "../format.js";
import { pill } from "../components.js";
import { bindNumField } from "../numpad.js";
import { alertHostRender } from "../components.js";

export function mountBilling(card, vm, ctx) {
  let rows = vm.berechneBillingRows();
  let gezahltStr = {};
  let abrechnenInFlight = false;

  if (vm.billingRows.length > 0) {
    const saved = {};
    for (const r of vm.billingRows) if (!saved[r.player.name]) saved[r.player.name] = r;
    rows = rows.map((r) => {
      const s = saved[r.player.name];
      if (s) return { ...r, gezahlt: s.gezahlt, perKarte: s.perKarte };
      return r;
    });
    gezahltStr = { ...vm.billingGezahlt };
  }

  function render() {
    const barZahlungen = rows.filter((r) => !r.perKarte).reduce((a, r) => a + r.gezahlt, 0);
    const kartenZahlungen = rows.filter((r) => r.perKarte).reduce((a, r) => a + r.gezahlt, 0);

    card.innerHTML = `
      <div class="sheet-toolbar">
        <button class="sheet-link destructive" data-act="abbrechen">Abbrechen</button>
        <h2>Abrechnung</h2>
        <button class="sheet-link" data-act="abrechnen" style="font-weight:700;color:var(--kb-primary)">Abrechnen</button>
      </div>
      <div class="sheet-body">
        <div class="kb-screen" style="max-width:680px">
          <div class="kb-group">
            <div class="kb-group-header">Platzierung &amp; Beträge</div>
            <div class="kb-group-body" style="padding:6px 0">
              ${rows.map((r, i) => billingRowHtml(r, i)).join(`<div class="kb-row-divider"></div>`)}
            </div>
          </div>
          <div class="kb-group">
            <div class="kb-group-header">Kassenstand</div>
            <div class="kb-group-body">
              <div class="kb-row"><span class="leading">Aktuell</span><span class="trailing u-mono">${money(vm.kasse.Kassenstand)}</span></div>
              <div class="kb-row-divider"></div>
              <div class="kb-row"><span class="leading">Bahngebühr</span><span class="trailing u-mono u-danger">−${money(vm.kasse.Bahngebuehr)}</span></div>
              <div class="kb-row-divider"></div>
              <div class="kb-row"><span class="leading">Einnahmen Bar (Kasse)</span><span class="trailing u-mono u-success">+${money(barZahlungen)}</span></div>
              ${
                kartenZahlungen > 0
                  ? `<div class="kb-row-divider"></div><div class="kb-row"><span class="leading">Einnahmen Karte (Konto)</span><span class="trailing u-mono u-success">+${money(kartenZahlungen)}</span></div>`
                  : ""
              }
            </div>
          </div>
        </div>
      </div>
    `;
    attach();
  }

  function billingRowHtml(row, i) {
    const isWinner = row.platz === 1;
    const spende = Math.max(0, row.gezahlt - row.zuZahlen);
    return `
      <div style="padding:10px 16px;${isWinner ? "background:color-mix(in srgb, var(--kb-brass-400) 6%, transparent)" : ""}">
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px">
          <span style="width:24px;font-weight:700;color:${isWinner ? "var(--kb-brass-500)" : "var(--kb-text-secondary)"}">${row.platz}.</span>
          <span style="font-weight:600;${isWinner ? "color:var(--kb-brass-500)" : ""}">${escapeHtml(row.player.name)}</span>
          ${isWinner ? "👑" : ""}
          <span style="flex:1"></span>
          <span class="u-muted u-mono" style="font-size:14px">${row.player.punkte.reduce((a, b) => a + b, 0)} Pkt.</span>
        </div>
        <div style="display:flex;gap:20px;align-items:flex-end;flex-wrap:wrap">
          <div>
            <div style="font-size:12px;color:var(--kb-text-secondary)">Zu zahlen</div>
            <div style="font-weight:700;color:var(--kb-danger)" class="u-mono">${money(row.zuZahlen)}</div>
          </div>
          <div>
            <div style="font-size:12px;color:var(--kb-text-secondary)">Gezahlt</div>
            <button class="kb-numfield align-right ${gezahltStr[row.player.name] ? "" : "placeholder"}" style="width:80px" data-gezahlt="${i}">${escapeHtml(gezahltStr[row.player.name]) || "0,00"}</button>
          </div>
          <div>
            <div style="font-size:12px;color:var(--kb-text-secondary)">Zahlungsart</div>
            <div class="kb-segmented" style="width:130px" data-perkarte="${i}">
              <button class="${!row.perKarte ? "active" : ""}" data-val="false">Bar</button>
              <button class="${row.perKarte ? "active" : ""}" data-val="true">Karte</button>
            </div>
          </div>
          <div style="flex:1"></div>
          <div style="text-align:right">
            <div style="font-size:12px;color:var(--kb-text-secondary)">Spende</div>
            <div style="font-weight:700;color:var(--kb-success)" class="u-mono">${money(spende)}</div>
          </div>
        </div>
        ${
          row.pumpenAnzahl > 0 || row.fremdeNeuner > 0 || row.fremdeKraenze > 0
            ? `<div style="display:flex;gap:8px;margin-top:8px;flex-wrap:wrap">
                ${row.pumpenAnzahl > 0 ? pill(`${row.pumpenAnzahl} Pump · ${money(row.pumpenBetrag)}`, "danger") : ""}
                ${row.fremdeNeuner > 0 ? pill(`${row.fremdeNeuner}× 9er anderer · ${money(row.fremdeNeunerBetrag)}`, "primary") : ""}
                ${row.fremdeKraenze > 0 ? pill(`${row.fremdeKraenze}× Kranz anderer · ${money(row.fremdeKraenzeBetrag)}`, "success") : ""}
              </div>`
            : ""
        }
      </div>
    `;
  }

  function attach() {
    card.querySelector("[data-act='abbrechen']").addEventListener("click", () => {
      vm.alert = {
        title: "Abrechnung abbrechen?",
        message: "Alle eingegebenen Beträge und Zahlungsarten werden verworfen.",
        buttons: [
          { label: "Weiter bearbeiten", role: "cancel" },
          {
            label: "Ja, abbrechen",
            role: "destructive",
            onClick: () => {
              vm.billingRows = [];
              vm.billingGezahlt = {};
              ctx.close();
            },
          },
        ],
      };
      alertHostRender(vm.alert);
    });

    card.querySelector("[data-act='abrechnen']").addEventListener("click", () => {
      vm.alert = {
        title: "Spiel abrechnen?",
        message: "Das Spiel wird abgerechnet und ins Archiv übertragen. Dieser Schritt kann nicht rückgängig gemacht werden.",
        buttons: [
          { label: "Abbrechen", role: "cancel" },
          {
            label: "Abrechnen",
            role: "destructive",
            onClick: () => {
              if (abrechnenInFlight) return;
              abrechnenInFlight = true;
              vm.abrechnungSpeichern(rows);
              ctx.close();
              ctx.rerenderApp();
            },
          },
        ],
      };
      alertHostRender(vm.alert);
    });

    card.querySelectorAll("[data-gezahlt]").forEach((btn) => {
      const i = Number(btn.dataset.gezahlt);
      bindNumField(
        btn,
        () => gezahltStr[rows[i].player.name] || "",
        (val) => {
          gezahltStr[rows[i].player.name] = val;
          rows[i].gezahlt = parseDecimal(val);
          // Update spende display without full re-render flash
          render();
        },
        { allowsDecimal: true, placeholder: "0,00" }
      );
    });

    card.querySelectorAll("[data-perkarte]").forEach((seg) => {
      const i = Number(seg.dataset.perkarte);
      seg.querySelectorAll("button").forEach((b) => {
        b.addEventListener("click", () => {
          rows[i].perKarte = b.dataset.val === "true";
          render();
        });
      });
    });
  }

  render();
}
