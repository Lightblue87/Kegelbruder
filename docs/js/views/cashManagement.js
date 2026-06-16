// CashManagementView — port of CashManagementView.swift
import { escapeHtml, money, parseDecimal } from "../format.js";
import { bindNumField } from "../numpad.js";

const MONATE = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"];

export function mountCashManagement(el, vm, ctx) {
  const local = {
    betrag: "",
    spende: "",
    beschreibung: "",
    gewählterSpieler: "",
    istEinzahlung: true,
    istKonto: false,
    errorMessage: null,
    transferBetrag: "",
    transferBarZuKonto: true,
    transferError: null,
    vonMonat: 0,
    vonJahr: 0,
    bisMonat: 0,
    bisJahr: 0,
  };

  function stammMitNamen() {
    return Object.entries(vm.mitglieder)
      .filter(([, d]) => d.typ === "Stamm" && d.offene_zahlung > 0)
      .map(([name, d]) => ({ name, schuld: d.offene_zahlung }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  function parseDatum(tx) {
    const s = tx.startsWith("[Konto] ") ? tx.slice(8) : tx;
    const parts = s.slice(0, 10).split(".");
    if (parts.length !== 3) return null;
    const d = parseInt(parts[0], 10),
      m = parseInt(parts[1], 10),
      y = parseInt(parts[2], 10);
    if (!d || !m || !y) return null;
    return { year: y, month: m };
  }

  function txJahre() {
    const set = new Set();
    for (const tx of vm.kasse.Transaktionen) {
      const d = parseDatum(tx);
      if (d) set.add(d.year);
    }
    return [...set].sort();
  }

  function gefilterteTx() {
    const list = [...vm.kasse.Transaktionen].slice(-200).reverse();
    return list.filter((tx) => {
      const d = parseDatum(tx);
      if (!d) return true;
      if (local.vonMonat > 0 && local.vonJahr > 0) {
        if (d.year < local.vonJahr || (d.year === local.vonJahr && d.month < local.vonMonat)) return false;
      }
      if (local.bisMonat > 0 && local.bisJahr > 0) {
        if (d.year > local.bisJahr || (d.year === local.bisJahr && d.month > local.bisMonat)) return false;
      }
      return true;
    });
  }

  function filterAktiv() {
    return (local.vonMonat > 0 && local.vonJahr > 0) || (local.bisMonat > 0 && local.bisJahr > 0);
  }

  function render() {
    const namen = stammMitNamen();
    const tx = gefilterteTx();
    el.innerHTML = `
      <div class="kb-screen">
        <div class="kb-screen-title">Kassenverwaltung</div>

        <div class="kb-group">
          <div class="kb-group-body" style="display:flex">
            ${balanceCell("Kasse (Bar)", vm.kasse.Kassenstand, "var(--kb-success)")}
            <div style="width:1px;background:var(--kb-row-divider);margin:12px 0"></div>
            ${balanceCell("Konto", vm.kasse.Kontostand, "var(--kb-primary)")}
          </div>
        </div>

        ${
          namen.length > 0
            ? `<div class="kb-group">
                <div class="kb-group-header">Offene Zahlungen</div>
                <div class="kb-group-body">
                  ${namen
                    .map(
                      (item, i) => `
                    <div class="kb-row"><span class="leading">${escapeHtml(item.name)}</span><span class="trailing u-mono" style="font-weight:600;color:var(--kb-danger)">${money(item.schuld)}</span></div>
                    ${i < namen.length - 1 ? `<div class="kb-row-divider"></div>` : ""}
                  `
                    )
                    .join("")}
                </div>
              </div>`
            : ""
        }

        <div class="kb-group">
          <div class="kb-group-header">Buchung</div>
          <div class="kb-group-body">
            <div style="display:flex;gap:8px;padding:12px 16px">
              <div class="kb-segmented" data-seg="art" style="flex:1">
                <button class="${local.istEinzahlung ? "active" : ""}" data-val="true">Einzahlung</button>
                <button class="${!local.istEinzahlung ? "active" : ""}" data-val="false">Auszahlung</button>
              </div>
              <div class="kb-segmented" data-seg="ziel" style="width:140px">
                <button class="${!local.istKonto ? "active" : ""}" data-val="false">Bar</button>
                <button class="${local.istKonto ? "active" : ""}" data-val="true">Konto</button>
              </div>
            </div>
            <div class="kb-row-divider"></div>
            <div class="kb-field-row">
              <span>Betrag (€)</span>
              ${numField("betrag", local.betrag, 110)}
            </div>
            <div class="kb-row-divider"></div>
            ${
              local.istEinzahlung
                ? `
              <div class="kb-field-row">
                <span class="u-muted">Spende (€)</span>
                ${numField("spende", local.spende, 110)}
              </div>
              <div class="kb-row-divider"></div>
              ${
                namen.length > 0
                  ? `<div class="kb-field-row">
                      <span>Spieler (optional)</span>
                      <select class="kb-select" id="spieler-select">
                        <option value="" ${local.gewählterSpieler === "" ? "selected" : ""}>Keiner</option>
                        ${namen.map((n) => `<option value="${escapeHtml(n.name)}" ${local.gewählterSpieler === n.name ? "selected" : ""}>${escapeHtml(n.name)}</option>`).join("")}
                      </select>
                    </div>
                    <div class="kb-row-divider"></div>`
                  : ""
              }`
                : ""
            }
            <div class="kb-field-row">
              <input class="kb-text-input" id="beschreibung-input" placeholder="Beschreibung" value="${escapeHtml(local.beschreibung)}" />
            </div>
            ${local.errorMessage ? `<div style="padding:0 16px 8px;color:var(--kb-danger);font-size:13px">${escapeHtml(local.errorMessage)}</div>` : ""}
            <div class="kb-row-divider"></div>
            <div style="padding:12px 16px">
              <button class="kb-btn prominent block ${local.istEinzahlung ? "tint-success" : "tint-danger"}" data-act="buchen">${local.istEinzahlung ? "+ Einzahlen" : "− Auszahlen"}</button>
            </div>
          </div>
        </div>

        <div class="kb-group">
          <div class="kb-group-header">Bar ↔ Konto</div>
          <div class="kb-group-body">
            <div style="padding:12px 16px">
              <div class="kb-segmented" data-seg="richtung">
                <button class="${local.transferBarZuKonto ? "active" : ""}" data-val="true">Bar → Konto</button>
                <button class="${!local.transferBarZuKonto ? "active" : ""}" data-val="false">Konto → Bar</button>
              </div>
            </div>
            <div class="kb-row-divider"></div>
            <div class="kb-field-row">
              <span>Betrag (€)</span>
              ${numField("transferBetrag", local.transferBetrag, 110)}
            </div>
            ${local.transferError ? `<div style="padding:4px 16px 0;color:var(--kb-danger);font-size:13px">${escapeHtml(local.transferError)}</div>` : ""}
            <div class="kb-row-divider"></div>
            <div style="padding:12px 16px">
              <button class="kb-btn prominent block" data-act="umbuchen">⇄ ${local.transferBarZuKonto ? "Bar → Konto umbuchen" : "Konto → Bar umbuchen"}</button>
            </div>
          </div>
        </div>

        <div class="kb-group">
          <div class="kb-group-header">Letzte Transaktionen</div>
          <div class="kb-group-body">
            <div style="display:flex;align-items:center;gap:8px;padding:10px 16px;flex-wrap:wrap">
              <span class="u-muted" style="font-size:13px">Von</span>
              ${datePicker("von")}
              <span class="u-muted" style="font-size:13px">Bis</span>
              ${datePicker("bis")}
              <span style="flex:1"></span>
              ${filterAktiv() ? `<button data-act="clear-filter" style="border:none;background:none;color:var(--kb-text-secondary);font-size:16px">✕</button>` : ""}
              <span class="u-mono" style="font-size:12px;color:var(--kb-text-tertiary)">${tx.length}/${vm.kasse.Transaktionen.length}</span>
            </div>
            <div class="kb-row-divider"></div>
            ${
              tx.length === 0
                ? `<div style="padding:16px;font-size:13px;color:var(--kb-text-tertiary)">${filterAktiv() ? "Keine Transaktionen im gewählten Zeitraum." : "Keine Transaktionen"}</div>`
                : tx
                    .map((t, i) => {
                      const isNeg = t.includes("| -");
                      const isKonto = t.startsWith("[Konto]");
                      const dot = isNeg ? "var(--kb-danger)" : isKonto ? "var(--kb-primary)" : "var(--kb-success)";
                      return `
                  <div style="display:flex;gap:10px;align-items:center;padding:10px 16px">
                    <span style="width:8px;height:8px;border-radius:50%;background:${dot};flex-shrink:0"></span>
                    <span style="font-size:13px">${escapeHtml(t)}</span>
                  </div>
                  ${i < tx.length - 1 ? `<div class="kb-row-divider"></div>` : ""}
                `;
                    })
                    .join("")
            }
          </div>
        </div>
      </div>
    `;
    attach();
  }

  function balanceCell(label, betrag, color) {
    return `
      <div style="flex:1;text-align:center;padding:16px 0">
        <div style="font-size:12px;color:var(--kb-text-secondary)">${label}</div>
        <div style="font-size:32px;font-weight:700;font-family:inherit" class="u-mono">${money(betrag)}</div>
      </div>
    `;
  }

  function numField(key, val, width) {
    return `<button class="kb-numfield align-right ${val ? "" : "placeholder"}" style="width:${width}px;height:32px" data-numfield="${key}">${escapeHtml(val) || "0,00"}</button>`;
  }

  function datePicker(prefix) {
    const monatKey = prefix + "Monat";
    const jahrKey = prefix + "Jahr";
    const jahre = txJahre();
    return `
      <select class="kb-select" data-datesel="${monatKey}" style="font-size:13px">
        <option value="0">–</option>
        ${MONATE.map((m, i) => `<option value="${i + 1}" ${local[monatKey] === i + 1 ? "selected" : ""}>${m}</option>`).join("")}
      </select>
      ${
        jahre.length > 0
          ? `<select class="kb-select" data-datesel="${jahrKey}" style="font-size:13px">
              <option value="0">–</option>
              ${jahre.map((y) => `<option value="${y}" ${local[jahrKey] === y ? "selected" : ""}>${y}</option>`).join("")}
            </select>`
          : ""
      }
    `;
  }

  function attach() {
    el.querySelectorAll("[data-seg]").forEach((seg) => {
      seg.querySelectorAll("button").forEach((b) => {
        b.addEventListener("click", () => {
          if (seg.dataset.seg === "art") local.istEinzahlung = b.dataset.val === "true";
          else if (seg.dataset.seg === "ziel") local.istKonto = b.dataset.val === "true";
          else if (seg.dataset.seg === "richtung") local.transferBarZuKonto = b.dataset.val === "true";
          render();
        });
      });
    });

    el.querySelectorAll("[data-numfield]").forEach((btn) => {
      const key = btn.dataset.numfield;
      bindNumField(btn, () => local[key], (val) => (local[key] = val), { allowsDecimal: true, placeholder: "0,00" });
    });

    const spielerSelect = el.querySelector("#spieler-select");
    if (spielerSelect) spielerSelect.addEventListener("change", () => (local.gewählterSpieler = spielerSelect.value));

    const beschreibungInput = el.querySelector("#beschreibung-input");
    if (beschreibungInput) beschreibungInput.addEventListener("input", () => (local.beschreibung = beschreibungInput.value));

    el.querySelectorAll("[data-datesel]").forEach((sel) => {
      sel.addEventListener("change", () => {
        local[sel.dataset.datesel] = Number(sel.value);
        render();
      });
    });

    const clearFilter = el.querySelector("[data-act='clear-filter']");
    if (clearFilter)
      clearFilter.addEventListener("click", () => {
        local.vonMonat = 0;
        local.vonJahr = 0;
        local.bisMonat = 0;
        local.bisJahr = 0;
        render();
      });

    el.querySelector("[data-act='buchen']").addEventListener("click", buchen);
    el.querySelector("[data-act='umbuchen']").addEventListener("click", umbuchen);
  }

  function buchen() {
    local.errorMessage = null;
    const b = parseDecimal(local.betrag);
    const sp = parseDecimal(local.spende);

    if (!(b > 0) && !(sp > 0)) {
      local.errorMessage = "Bitte einen gültigen Betrag eingeben.";
      render();
      return;
    }

    const bez = local.beschreibung.trim() === "" ? (local.istEinzahlung ? "Einzahlung" : "Auszahlung") : local.beschreibung;

    if (local.istEinzahlung) {
      if (b > 0) vm.einzahlen(b, bez, local.gewählterSpieler === "" ? null : local.gewählterSpieler, local.istKonto);
      if (sp > 0) {
        const spendeBesch = local.gewählterSpieler === "" ? "Spende" : `Spende von ${local.gewählterSpieler}`;
        vm.einzahlen(sp, spendeBesch, null, local.istKonto);
      }
    } else {
      if (!(b > 0)) {
        local.errorMessage = "Bitte einen gültigen Betrag eingeben.";
        render();
        return;
      }
      const balance = local.istKonto ? vm.kasse.Kontostand : vm.kasse.Kassenstand;
      if (b > balance) {
        local.errorMessage = `Betrag übersteigt den ${local.istKonto ? "Kontostand" : "Kassenstand"}.`;
        render();
        return;
      }
      vm.auszahlen(b, bez, local.istKonto);
    }

    local.betrag = "";
    local.spende = "";
    local.beschreibung = "";
    local.gewählterSpieler = "";
    ctx.refreshSidebar();
    render();
  }

  function umbuchen() {
    local.transferError = null;
    const b = parseDecimal(local.transferBetrag);
    if (!(b > 0)) {
      local.transferError = "Bitte einen gültigen Betrag eingeben.";
      render();
      return;
    }
    const source = local.transferBarZuKonto ? vm.kasse.Kassenstand : vm.kasse.Kontostand;
    if (b > source) {
      local.transferError = `Betrag übersteigt den ${local.transferBarZuKonto ? "Kassenstand" : "Kontostand"}.`;
      render();
      return;
    }
    if (local.transferBarZuKonto) vm.umbuchenBarZuKonto(b);
    else vm.umbuchenKontoZuBar(b);
    local.transferBetrag = "";
    render();
  }

  render();
}
