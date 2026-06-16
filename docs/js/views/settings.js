// SettingsView — port of SettingsView.swift.
// The iCloud folder picker is replaced by manual JSON export/import since the
// PWA has no shared backend — the 3-4 club devices exchange a snapshot file
// instead. Erscheinungsbild / Gebühren / Strafen & Boni are 1:1.
import { escapeHtml, parseDecimal } from "../format.js";
import { bindNumField } from "../numpad.js";
import { DB } from "../db.js";

export function mountSettings(el, vm, ctx) {
  const local = {};
  function ladenLocal() {
    const k = vm.kasse;
    local.startgeld = fmt(k.Startgeld);
    local.strafeStamm = fmt(k.Strafe_Stamm);
    local.bahngebuehr = fmt(k.Bahngebuehr);
    local.pumpe = fmt(k.Pumpe);
    local.neuner = fmt(k.Neuner);
    local.kranz = fmt(k.Kranz);
  }
  function fmt(v) {
    return v.toFixed(2).replace(".", ",");
  }
  ladenLocal();

  let saved = false;
  let importMsg = null;
  const theme = DB.getSettings().theme || "system";

  function render() {
    el.innerHTML = `
      <div class="kb-screen">
        <div class="kb-screen-title">Einstellungen</div>

        <div class="kb-group">
          <div class="kb-group-header">Erscheinungsbild</div>
          <div class="kb-group-body">
            <div style="padding:12px 16px">
              <div class="kb-segmented" data-seg="theme">
                <button class="${theme === "system" ? "active" : ""}" data-val="system">System</button>
                <button class="${theme === "light" ? "active" : ""}" data-val="light">Hell</button>
                <button class="${theme === "dark" ? "active" : ""}" data-val="dark">Dunkel</button>
              </div>
            </div>
          </div>
        </div>

        <div class="kb-group">
          <div class="kb-group-header">Gebühren</div>
          <div class="kb-group-body">
            ${betragRow("Startgeld", "startgeld")}
            <div class="kb-row-divider"></div>
            ${betragRow("Strafe (Abwesend)", "strafeStamm")}
            <div class="kb-row-divider"></div>
            ${betragRow("Bahngebühr", "bahngebuehr")}
          </div>
        </div>

        <div class="kb-group">
          <div class="kb-group-header">Strafen &amp; Boni</div>
          <div class="kb-group-body">
            ${betragRow("Pumpe (Gutter)", "pumpe")}
            <div class="kb-row-divider"></div>
            ${betragRow("Neuner", "neuner")}
            <div class="kb-row-divider"></div>
            ${betragRow("Kranz", "kranz")}
          </div>
        </div>

        <button class="kb-btn prominent block" data-act="speichern">Speichern</button>
        ${saved ? `<div style="text-align:center;margin-top:10px;color:var(--kb-success);font-weight:600">✓ Gespeichert</div>` : ""}

        <div class="kb-group" style="margin-top:28px">
          <div class="kb-group-header">Daten &amp; Backup</div>
          <div class="kb-group-body">
            <div class="kb-row">
              <div class="leading">
                <div style="font-weight:600">Daten exportieren</div>
                <div style="font-size:12px;color:var(--kb-text-secondary)">Sichert Mitglieder, Kasse &amp; Archiv als Datei</div>
              </div>
              <div class="trailing"><button class="kb-btn" data-act="export">⬇ Export</button></div>
            </div>
            <div class="kb-row-divider"></div>
            <div class="kb-row">
              <div class="leading">
                <div style="font-weight:600">Daten importieren</div>
                <div style="font-size:12px;color:var(--kb-text-secondary)">Überschreibt alle lokalen Daten auf diesem Gerät</div>
              </div>
              <div class="trailing">
                <button class="kb-btn" data-act="import">⬆ Import</button>
                <input type="file" id="import-file" accept="application/json" style="display:none" />
              </div>
            </div>
            ${importMsg ? `<div class="kb-row-divider"></div><div style="padding:10px 16px;font-size:13px;color:${importMsg.ok ? "var(--kb-success)" : "var(--kb-danger)"}">${escapeHtml(importMsg.text)}</div>` : ""}
            <div class="kb-row-divider"></div>
            <div class="kb-row">
              <div class="leading"><div style="font-weight:600;color:var(--kb-danger)">Alle Daten zurücksetzen</div></div>
              <div class="trailing"><button class="kb-btn tint-danger" data-act="reset">Zurücksetzen</button></div>
            </div>
          </div>
        </div>

        <div style="text-align:center;font-size:12px;color:var(--kb-text-tertiary);margin-top:24px">
          Kegel Brüder · läuft offline als installierte Web-App auf diesem Gerät.
        </div>
      </div>
    `;
    attach();
  }

  function betragRow(label, key) {
    return `
      <div class="kb-field-row">
        <span>${label}</span>
        <div style="display:flex;align-items:center;gap:6px">
          <button class="kb-numfield align-right ${local[key] ? "" : "placeholder"}" style="width:80px" data-numfield="${key}">${escapeHtml(local[key]) || "0,00"}</button>
          <span class="u-muted">€</span>
        </div>
      </div>
    `;
  }

  function attach() {
    el.querySelectorAll("[data-numfield]").forEach((btn) => {
      const key = btn.dataset.numfield;
      bindNumField(btn, () => local[key], (val) => (local[key] = val), { allowsDecimal: true, placeholder: "0,00" });
    });

    el.querySelector("[data-seg='theme']")
      .querySelectorAll("button")
      .forEach((b) => {
        b.addEventListener("click", () => {
          DB.saveSettings({ theme: b.dataset.val });
          ctx.applyTheme(b.dataset.val);
          render();
        });
      });

    el.querySelector("[data-act='speichern']").addEventListener("click", () => {
      const k = { ...vm.kasse };
      // Explicit blank check instead of `|| fallback` — 0 is a valid fee/penalty
      // value (e.g. disabling the Pumpe penalty) and must not be discarded.
      const apply = (key, raw) => {
        if (raw.trim() !== "") k[key] = parseDecimal(raw);
      };
      apply("Startgeld", local.startgeld);
      apply("Strafe_Stamm", local.strafeStamm);
      apply("Bahngebuehr", local.bahngebuehr);
      apply("Pumpe", local.pumpe);
      apply("Neuner", local.neuner);
      apply("Kranz", local.kranz);
      vm.einstellungenSpeichern(k);
      saved = true;
      render();
      setTimeout(() => {
        saved = false;
        render();
      }, 2000);
    });

    el.querySelector("[data-act='export']").addEventListener("click", () => {
      const blob = new Blob([DB.exportJSON()], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `kegelbrueder-backup-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);
    });

    const fileInput = el.querySelector("#import-file");
    el.querySelector("[data-act='import']").addEventListener("click", () => fileInput.click());
    fileInput.addEventListener("change", () => {
      const file = fileInput.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = () => {
        try {
          DB.importJSON(reader.result);
          vm.laden();
          ladenLocal();
          importMsg = { ok: true, text: "Import erfolgreich. Daten wurden übernommen." };
          ctx.refreshSidebar();
        } catch (e) {
          importMsg = { ok: false, text: "Import fehlgeschlagen: Datei ungültig." };
        }
        render();
      };
      reader.readAsText(file);
    });

    el.querySelector("[data-act='reset']").addEventListener("click", () => {
      vm.alert = {
        title: "Alle Daten löschen?",
        message: "Mitglieder, Kassenstand und Archiv werden unwiderruflich gelöscht.",
        buttons: [
          { label: "Abbrechen", role: "cancel" },
          {
            label: "Löschen",
            role: "destructive",
            onClick: () => {
              DB.resetAll();
              vm.laden();
              ladenLocal();
              ctx.refreshSidebar();
              render();
            },
          },
        ],
      };
      ctx.showAlert(vm.alert);
    });
  }

  render();
}
