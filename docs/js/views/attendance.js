// AttendanceView — port of AttendanceView.swift
import { escapeHtml, money, parseDecimal } from "../format.js";
import { pill, alertHostRender } from "../components.js";
import { bindNumField } from "../numpad.js";
import { namesEqual } from "../state.js";

export function mountAttendance(card, vm, ctx) {
  const local = {
    anwesend: {}, // name -> bool (Stamm)
    zahlungen: {}, // name -> string
    zahlungsarten: {}, // name -> bool (true = Karte)
    gastAnwesend: {}, // name -> bool (known Gäste)
    gastZahlungen: {},
    gastZahlungsarten: {}, // name -> bool (true = Karte)
    neueGäste: [], // {id, name, selected, zahlung, perKarte}
    neuerGastName: "",
  };

  const stammMitglieder = () =>
    Object.entries(vm.mitglieder)
      .filter(([, d]) => d.typ === "Stamm")
      .sort((a, b) => a[0].localeCompare(b[0]));
  const gastMitglieder = () =>
    Object.entries(vm.mitglieder)
      .filter(([, d]) => d.typ === "Gast")
      .sort((a, b) => a[0].localeCompare(b[0]));

  for (const [name] of stammMitglieder()) {
    local.anwesend[name] = false;
    local.zahlungen[name] = "";
  }

  function anzahlAnwesend() {
    return (
      Object.values(local.anwesend).filter(Boolean).length +
      Object.values(local.gastAnwesend).filter(Boolean).length +
      local.neueGäste.filter((g) => g.selected).length
    );
  }
  function anzahlAbwesend() {
    return stammMitglieder().length - Object.values(local.anwesend).filter(Boolean).length;
  }
  function anwesendeNamen() {
    const stamm = stammMitglieder()
      .filter(([n]) => local.anwesend[n])
      .map(([n]) => n);
    const gastDB = gastMitglieder()
      .filter(([n]) => local.gastAnwesend[n])
      .map(([n]) => n);
    const gastNeu = local.neueGäste.filter((g) => g.selected).map((g) => g.name);
    return [...stamm, ...gastDB, ...gastNeu].sort();
  }

  function schuldenLabel(basis, istAnwesend) {
    if (istAnwesend) {
      const gesamt = basis + vm.kasse.Startgeld;
      return `<span class="u-danger" style="font-size:12px">Offen inkl. Startgeld: ${gesamt.toFixed(2).replace(".", ",")} €</span>`;
    } else if (basis > 0) {
      return `<span class="u-danger" style="font-size:12px">Offen: ${basis.toFixed(2).replace(".", ",")} €</span>`;
    }
    return "";
  }

  function render() {
    const disabled = anzahlAnwesend() === 0;
    card.innerHTML = `
      <div class="sheet-toolbar">
        <button class="sheet-link cancel" data-act="cancel">Abbrechen</button>
        <h2>Anwesenheit</h2>
        <button class="sheet-link" data-act="weiter" ${disabled ? "disabled" : ""} style="font-weight:700">Weiter →</button>
      </div>
      <div class="sheet-body" style="display:flex;height:100%">
        <div style="flex:1;overflow-y:auto;padding:16px">
          <div class="kb-group">
            ${`<div class="kb-group-header">STAMM-MITGLIEDER</div>`}
            <div class="kb-group-body">
              ${stammMitglieder()
                .map(([name, data], i, arr) => attendeeRow(name, data, local.anwesend[name], local.zahlungen[name], local.zahlungsarten[name], "stamm", i === arr.length - 1))
                .join("")}
            </div>
          </div>
          <div class="kb-group">
            ${`<div class="kb-group-header">GÄSTE</div>`}
            <div class="kb-group-body">
              ${gastMitglieder()
                .map(([name, data]) => attendeeRow(name, data, local.gastAnwesend[name], local.gastZahlungen[name], local.gastZahlungsarten[name], "gast", false))
                .join("")}
              ${local.neueGäste
                .map(
                  (g) => `
                <div class="kb-row">
                  <div class="leading" style="display:flex;align-items:center;gap:8px">
                    <span style="font-weight:600">${escapeHtml(g.name)}</span>
                    ${pill("Neu", "guest")}
                  </div>
                  <div class="trailing">${toggleHtml(`neugast-${g.id}`, g.selected)}</div>
                </div>
                ${
                  g.selected
                    ? `<div class="kb-field-row"><span class="u-muted">Zahlung heute:</span>${numFieldHtml(`neugast-zahlung-${g.id}`, g.zahlung)}<span class="u-muted">€</span>${zahlungsartHtml(`neugast-art-${g.id}`, !!g.perKarte)}</div>`
                    : ""
                }
                <div class="kb-row-divider"></div>
              `
                )
                .join("")}
              <div class="kb-field-row">
                <input class="kb-text-input" id="new-guest-name" placeholder="Neuer Gast" value="${escapeHtml(local.neuerGastName)}" />
                <button class="kb-btn" id="add-guest-btn" ${local.neuerGastName.trim() === "" ? "disabled" : ""}>Hinzufügen</button>
              </div>
            </div>
          </div>
        </div>
        <div style="width:280px;flex-shrink:0;overflow-y:auto;border-left:1px solid var(--kb-row-divider);background:var(--kb-card-bg)">
          ${renderOverview()}
        </div>
      </div>
    `;
    attach();
  }

  function attendeeRow(name, data, isOn, zahlungVal, perKarte, kind, isLastNoBorder) {
    return `
      <div class="kb-row">
        <div class="leading">
          <div style="font-weight:600">${escapeHtml(name)}</div>
          ${schuldenLabel(data.offene_zahlung, !!isOn)}
        </div>
        <div class="trailing">${toggleHtml(`${kind}-${escapeHtml(name)}`, !!isOn)}</div>
      </div>
      ${isOn ? `<div class="kb-field-row"><span class="u-muted">Zahlung heute:</span>${numFieldHtml(`${kind}-zahlung-${escapeHtml(name)}`, zahlungVal || "")}<span class="u-muted">€</span>${zahlungsartHtml(`${kind}-art-${escapeHtml(name)}`, !!perKarte)}</div>` : ""}
      <div class="kb-row-divider"></div>
    `;
  }

  function zahlungsartHtml(id, perKarte) {
    return `<div class="kb-segmented" style="width:110px;margin-left:8px" data-zahlungsart="${id}">
      <button class="${!perKarte ? "active" : ""}" data-val="false">Bar</button>
      <button class="${perKarte ? "active" : ""}" data-val="true">Karte</button>
    </div>`;
  }

  function toggleHtml(id, on) {
    return `<button class="kb-toggle ${on ? "on" : ""}" data-toggle="${id}"><span class="knob"></span></button>`;
  }
  function numFieldHtml(id, val) {
    return `<button class="kb-numfield align-right ${val ? "" : "placeholder"}" style="width:80px" data-numfield="${id}">${escapeHtml(val) || "0,00"}</button>`;
  }

  function renderOverview() {
    if (anzahlAnwesend() === 0) {
      return `
        <div style="padding:20px 16px 12px;font-weight:600">Übersicht</div>
        <div class="kb-card" style="margin:0 16px">
          ${statRow("✅", "var(--kb-success)", "Anwesend", String(anzahlAnwesend()))}
          ${statRow("❌", "var(--kb-danger)", "Abwesend", String(anzahlAbwesend()))}
          ${statRow("€", "var(--kb-primary)", "Startgeld/Spieler", money(vm.kasse.Startgeld))}
          ${statRow("⚠", "var(--kb-warning)", "Strafe Abwesend", money(anzahlAbwesend() * vm.kasse.Strafe_Stamm))}
        </div>
      `;
    }
    const total = anzahlAnwesend() * vm.kasse.Startgeld;
    const stammAnwesend = Object.values(local.anwesend).filter(Boolean).length;
    const stammGesamt = stammMitglieder().length;
    const gästeAnwesend = Object.values(local.gastAnwesend).filter(Boolean).length + local.neueGäste.filter((g) => g.selected).length;
    return `
      <div style="padding:20px 16px 12px;font-weight:600">Übersicht</div>
      <div class="kb-card" style="margin:0 16px">
        ${statRow("✅", "var(--kb-success)", "Anwesend", String(anzahlAnwesend()))}
        ${statRow("❌", "var(--kb-danger)", "Abwesend", String(anzahlAbwesend()))}
        ${statRow("€", "var(--kb-primary)", "Startgeld/Spieler", money(vm.kasse.Startgeld))}
        ${statRow("⚠", "var(--kb-warning)", "Strafe Abwesend", money(anzahlAbwesend() * vm.kasse.Strafe_Stamm))}
      </div>
      <div style="display:flex;justify-content:space-between;padding:16px 16px 0;font-size:14px">
        <span class="u-muted">Startgelder gesamt</span>
        <span style="font-weight:700;color:var(--kb-primary)">${money(total)}</span>
      </div>
      <div style="display:flex;justify-content:space-between;padding:20px 16px 8px;font-size:12px;font-weight:600">
        <span class="u-muted">Spieler heute</span>
        <span style="color:${stammGesamt > 0 && stammAnwesend * 2 >= stammGesamt ? "var(--kb-success)" : "var(--kb-warning)"}">
          👥 ${stammAnwesend}/${stammGesamt} ${gästeAnwesend > 0 ? `&nbsp;&nbsp;➕ ${gästeAnwesend}` : ""}
        </span>
      </div>
      <div class="kb-card" style="margin:0 16px 16px">
        ${anwesendeNamen()
          .map((n) => `<div style="display:flex;gap:10px;align-items:center;padding:8px 0">✅<span>${escapeHtml(n)}</span></div>`)
          .join("")}
      </div>
    `;
  }

  function statRow(ico, color, label, value) {
    return `
      <div style="display:flex;align-items:center;gap:12px;padding:10px 0">
        <span style="width:28px;text-align:center;color:${color}">${ico}</span>
        <span style="flex:1;font-size:14px">${label}</span>
        <span style="font-weight:700;color:${color}">${value}</span>
      </div>
    `;
  }

  function attach() {
    card.querySelector("[data-act='cancel']").addEventListener("click", () => ctx.close());
    const weiterBtn = card.querySelector("[data-act='weiter']");
    if (weiterBtn) weiterBtn.addEventListener("click", weiter);

    card.querySelectorAll("[data-toggle]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const id = btn.dataset.toggle;
        if (id.startsWith("stamm-")) {
          const name = id.slice(6);
          local.anwesend[name] = !local.anwesend[name];
          if (local.anwesend[name] && !local.zahlungen[name]) {
            const data = vm.mitglieder[name];
            local.zahlungen[name] = (data.offene_zahlung + vm.kasse.Startgeld).toFixed(2).replace(".", ",");
          }
        } else if (id.startsWith("gast-zahlung-")) {
          // handled below by numfield
        } else if (id.startsWith("gast-")) {
          const name = id.slice(5);
          local.gastAnwesend[name] = !local.gastAnwesend[name];
          if (local.gastAnwesend[name] && !local.gastZahlungen[name]) {
            local.gastZahlungen[name] = vm.kasse.Startgeld.toFixed(2).replace(".", ",");
          }
        } else if (id.startsWith("neugast-")) {
          const gid = id.slice(8);
          const g = local.neueGäste.find((x) => x.id === gid);
          if (g) {
            g.selected = !g.selected;
            if (g.selected && !g.zahlung) g.zahlung = vm.kasse.Startgeld.toFixed(2).replace(".", ",");
          }
        }
        render();
      });
    });

    card.querySelectorAll("[data-zahlungsart]").forEach((seg) => {
      seg.querySelectorAll("button").forEach((btn) => {
        btn.addEventListener("click", () => {
          const id = seg.dataset.zahlungsart;
          const perKarte = btn.dataset.val === "true";
          if (id.startsWith("stamm-art-")) local.zahlungsarten[id.slice(10)] = perKarte;
          else if (id.startsWith("gast-art-")) local.gastZahlungsarten[id.slice(9)] = perKarte;
          else if (id.startsWith("neugast-art-")) {
            const g = local.neueGäste.find((x) => x.id === id.slice(12));
            if (g) g.perKarte = perKarte;
          }
          render();
        });
      });
    });

    card.querySelectorAll("[data-numfield]").forEach((btn) => {
      const id = btn.dataset.numfield;
      bindNumField(
        btn,
        () => readNumField(id),
        (val) => {
          writeNumField(id, val);
        },
        { allowsDecimal: true, placeholder: "0,00" }
      );
    });

    const nameInput = card.querySelector("#new-guest-name");
    if (nameInput) {
      nameInput.addEventListener("input", () => {
        local.neuerGastName = nameInput.value;
        card.querySelector("#add-guest-btn").disabled = local.neuerGastName.trim() === "";
      });
    }
    const addBtn = card.querySelector("#add-guest-btn");
    if (addBtn) {
      addBtn.addEventListener("click", () => {
        const n = local.neuerGastName.trim();
        if (!n) return;
        // A guest must not share a name with an existing member — spielStarten()
        // would otherwise either downgrade a Stamm-Mitglied or merge into the
        // wrong record.
        if (Object.keys(vm.mitglieder).some((m) => namesEqual(m, n)) || local.neueGäste.some((g) => namesEqual(g.name, n))) {
          vm.alert = {
            title: "Name bereits vergeben",
            message: `„${n}" ist bereits als Mitglied oder Gast angelegt. Bitte einen anderen Namen verwenden.`,
            buttons: [{ label: "OK", role: "cancel" }],
          };
          alertHostRender(vm.alert);
          return;
        }
        local.neueGäste.push({ id: String(Math.random()), name: n, selected: true, zahlung: vm.kasse.Startgeld.toFixed(2).replace(".", ",") });
        local.neuerGastName = "";
        render();
      });
    }
  }

  function readNumField(id) {
    if (id.startsWith("stamm-zahlung-")) return local.zahlungen[id.slice(14)] || "";
    if (id.startsWith("gast-zahlung-")) return local.gastZahlungen[id.slice(13)] || "";
    if (id.startsWith("neugast-zahlung-")) {
      const g = local.neueGäste.find((x) => x.id === id.slice(16));
      return g?.zahlung || "";
    }
    return "";
  }
  function writeNumField(id, val) {
    if (id.startsWith("stamm-zahlung-")) local.zahlungen[id.slice(14)] = val;
    else if (id.startsWith("gast-zahlung-")) local.gastZahlungen[id.slice(13)] = val;
    else if (id.startsWith("neugast-zahlung-")) {
      const g = local.neueGäste.find((x) => x.id === id.slice(16));
      if (g) g.zahlung = val;
    }
  }

  function weiter() {
    // 1. Persist new guests so berechneStartgebuehren can process their payments
    for (const gast of local.neueGäste) {
      if (!vm.mitglieder[gast.name]) vm.spielerHinzufügen(gast.name, "Gast", 0);
    }

    // 2. Merge attendance + payments
    const allAnwesend = { ...local.anwesend };
    for (const [name] of gastMitglieder()) if (local.gastAnwesend[name]) allAnwesend[name] = true;
    for (const gast of local.neueGäste) if (gast.selected) allAnwesend[gast.name] = true;

    const parsedZahlungen = {};
    const parsedZahlungsarten = {};
    for (const [name, str] of Object.entries(local.zahlungen)) if (local.anwesend[name]) { parsedZahlungen[name] = parseDecimal(str); parsedZahlungsarten[name] = !!local.zahlungsarten[name]; }
    for (const [name, str] of Object.entries(local.gastZahlungen)) if (local.gastAnwesend[name]) { parsedZahlungen[name] = parseDecimal(str); parsedZahlungsarten[name] = !!local.gastZahlungsarten[name]; }
    for (const gast of local.neueGäste) if (gast.selected) { parsedZahlungen[gast.name] = parseDecimal(gast.zahlung); parsedZahlungsarten[gast.name] = !!gast.perKarte; }

    vm.berechneStartgebuehren(allAnwesend, parsedZahlungen, parsedZahlungsarten);

    // 3. Build player lists
    const anwesendeSpieler = stammMitglieder()
      .filter(([n]) => local.anwesend[n])
      .map(([n]) => n);
    const selectedKnownGäste = gastMitglieder()
      .filter(([n]) => local.gastAnwesend[n])
      .map(([n, d]) => ({ name: n, typ: d.typ, punkte: [0, 0, 0, 0], offene_zahlung: d.offene_zahlung, pumpen: 0, neuner: 0, kranz: 0 }));
    const selectedNeueGäste = local.neueGäste
      .filter((g) => g.selected)
      .map((g) => ({ name: g.name, typ: "Gast", punkte: [0, 0, 0, 0], offene_zahlung: 0, pumpen: 0, neuner: 0, kranz: 0 }));

    const alleGäste = [...selectedKnownGäste, ...selectedNeueGäste];
    vm.pendingAttendees = [...anwesendeSpieler, ...alleGäste.map((g) => g.name)];
    vm.pendingGäste = alleGäste;

    ctx.close();
    ctx.openSheet("playerSort");
  }

  render();
}
