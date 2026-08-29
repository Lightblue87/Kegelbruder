// SettingsView — port of SettingsView.swift.
// The iCloud folder picker is replaced by manual JSON export/import since the
// PWA has no shared backend — the 3-4 club devices exchange a snapshot file
// instead. Erscheinungsbild / Gebühren / Strafen & Boni are 1:1.
import { escapeHtml, parseDecimal } from "../format.js";
import { bindNumField } from "../numpad.js";
import { DB } from "../db.js";
import { SyncClient } from "../sync.js";

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
  let syncMsg = null;
  let syncBusy = false;
  const theme = DB.getSettings().theme || "system";
  let syncSettings = SyncClient.getSettings();

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
                <div style="font-weight:600">Datenbank exportieren (.db)</div>
                <div style="font-size:12px;color:var(--kb-text-secondary)">Echte SQLite-Datei — dasselbe Format wie kegelbruder.db aus der iOS-/Desktop-App</div>
              </div>
              <div class="trailing"><button class="kb-btn" data-act="export">⬇ Export</button></div>
            </div>
            <div class="kb-row-divider"></div>
            <div class="kb-row">
              <div class="leading">
                <div style="font-weight:600">Datenbank importieren (.db)</div>
                <div style="font-size:12px;color:var(--kb-text-secondary)">Lädt eine kegelbruder.db (z.B. von der iOS-App) — überschreibt alle lokalen Daten auf diesem Gerät</div>
              </div>
              <div class="trailing">
                <button class="kb-btn" data-act="import">⬆ Import</button>
                <input type="file" id="import-file" accept=".db,application/x-sqlite3,application/octet-stream" style="display:none" />
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

        <div class="kb-group" style="margin-top:28px">
          <div class="kb-group-header">Synchronisation</div>
          <div class="kb-group-body">
            <div style="padding:14px 16px;display:grid;gap:12px">
              ${syncInput("Sync-Endpunkt", "endpoint", "https://...workers.dev")}
              ${syncInput("Club-ID", "clubId", "kegelbrueder")}
              ${syncInput("Sync-Schlüssel", "syncKey", "Gemeinsamer Schlüssel", true)}
              ${syncInput("Gerätename", "deviceName", "iPad Kegelbahn")}
              <div style="font-size:12px;color:var(--kb-text-secondary)">
                Letzte Revision: ${escapeHtml(syncSettings.lastRevision || "noch nicht synchronisiert")}
                ${syncSettings.lastSyncAt ? `<br>Letzter Sync: ${escapeHtml(formatDateTime(syncSettings.lastSyncAt))}` : ""}
              </div>
            </div>
            <div class="kb-row-divider"></div>
            <div style="padding:12px 16px;display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end">
              <button class="kb-btn" data-sync-act="status" ${syncBusy ? "disabled" : ""}>Status prüfen</button>
              <button class="kb-btn" data-sync-act="download" ${syncBusy ? "disabled" : ""}>Remote laden</button>
              <button class="kb-btn prominent" data-sync-act="upload" ${syncBusy ? "disabled" : ""}>Dieses Gerät hochladen</button>
            </div>
            ${syncMsg ? `<div class="kb-row-divider"></div><div style="padding:10px 16px;font-size:13px;line-height:1.6;color:${syncMsg.ok ? "var(--kb-success)" : "var(--kb-danger)"}">
              ${syncMsg.lines.map((l) => escapeHtml(l)).join("<br>")}
            </div>` : ""}
            <div class="kb-row-divider"></div>
            <div style="padding:10px 16px;font-size:12px;color:var(--kb-text-secondary)">
              Offline bleibt dieses Gerät immer arbeitsfähig. Synchronisiert wird nur, wenn du eine Aktion startest und Internet verfügbar ist.
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

  function syncInput(label, key, placeholder, password = false) {
    return `
      <label class="kb-sync-field">
        <span>${label}</span>
        <input
          class="kb-text-input"
          data-sync-field="${key}"
          type="${password ? "password" : "text"}"
          value="${escapeHtml(syncSettings[key] || "")}"
          placeholder="${escapeHtml(placeholder)}"
          autocomplete="off"
        />
      </label>
    `;
  }

  function formatDateTime(iso) {
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return iso;
    return date.toLocaleString("de-DE", { dateStyle: "short", timeStyle: "short" });
  }

  function readSyncSettings() {
    const next = {};
    el.querySelectorAll("[data-sync-field]").forEach((input) => {
      next[input.dataset.syncField] = input.value;
    });
    syncSettings = SyncClient.saveSettings(next);
    return syncSettings;
  }

  function setSyncMessage(ok, lines) {
    // lines can be a string (single line) or an array of strings
    syncMsg = { ok, lines: Array.isArray(lines) ? lines : [lines] };
    syncSettings = SyncClient.getSettings();
    render();
  }

  async function runSyncAction(action) {
    readSyncSettings();
    syncBusy = true;
    syncMsg = null;
    render();
    try {
      if (action === "status") {
        const remote = await SyncClient.status();
        const revision = remote.revision || "keine";
        const lines = [`✓ Remote erreichbar · Revision: ${revision}`];
        const device = remote.deviceName || remote.device_name || "";
        const ts = remote.uploadedAt || remote.updatedAt || remote.timestamp || remote.syncedAt || "";
        if (device || ts) {
          const parts = [];
          if (device) parts.push(`Gerät: ${device}`);
          if (ts) parts.push(`Hochgeladen: ${formatDateTime(ts)}`);
          lines.push(parts.join(" · "));
        }
        setSyncMessage(true, lines);
      } else if (action === "upload") {
        const remote = await SyncClient.upload(DB.exportDb());
        setSyncMessage(true, [`Hochgeladen · Neue Revision: ${remote.revision}`]);
      } else if (action === "download") {
        const proceed = () => {
          runDownload().catch((e) => setSyncMessage(false, e.message || String(e)));
        };
        vm.alert = {
          title: "Remote-Daten laden?",
          message: "Die lokale Datenbank auf diesem Gerät wird durch den synchronisierten Stand ersetzt.",
          buttons: [
            { label: "Abbrechen", role: "cancel" },
            { label: "Laden", role: "destructive", onClick: proceed },
          ],
        };
        syncBusy = false;
        render();
        ctx.showAlert(vm.alert);
      }
    } catch (e) {
      if (e.status === 409) {
        setSyncMessage(false, "Remote ist neuer als dieses Gerät. Bitte erst Remote laden oder bewusst den richtigen Stand wählen.");
      } else {
        setSyncMessage(false, e.message || String(e));
      }
    } finally {
      if (syncBusy) {
        syncBusy = false;
        render();
      }
    }
  }

  async function runDownload() {
    syncBusy = true;
    syncMsg = null;
    render();
    try {
      const { bytes, remote } = await SyncClient.download();
      await DB.importDb(bytes);
      vm.laden();
      ladenLocal();
      ctx.refreshSidebar();
      const lines = [`Remote geladen · Revision: ${remote.revision}`];
      const device = remote.deviceName || remote.device_name || "";
      const ts = remote.uploadedAt || remote.updatedAt || remote.timestamp || remote.syncedAt || "";
      if (device || ts) {
        const parts = [];
        if (device) parts.push(`Gerät: ${device}`);
        if (ts) parts.push(`Hochgeladen: ${formatDateTime(ts)}`);
        lines.push(parts.join(" · "));
      }
      setSyncMessage(true, lines);
    } finally {
      syncBusy = false;
      render();
    }
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
      // Real SQLite binary, byte-identical format to kegelbruder.db from der
      // iOS-/Desktop-App — kann dort direkt wieder geöffnet werden.
      const bytes = DB.exportDb();
      const blob = new Blob([bytes], { type: "application/x-sqlite3" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `kegelbruder-${new Date().toISOString().slice(0, 10)}.db`;
      a.click();
      URL.revokeObjectURL(url);
    });

    const fileInput = el.querySelector("#import-file");
    el.querySelector("[data-act='import']").addEventListener("click", () => fileInput.click());
    fileInput.addEventListener("change", () => {
      const file = fileInput.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = async () => {
        try {
          await DB.importDb(new Uint8Array(reader.result));
          vm.laden();
          ladenLocal();
          importMsg = { ok: true, text: "Import erfolgreich. Daten wurden übernommen." };
          ctx.refreshSidebar();
        } catch (e) {
          importMsg = { ok: false, text: "Import fehlgeschlagen: Datei ist keine gültige kegelbruder.db." };
        }
        render();
      };
      reader.readAsArrayBuffer(file);
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

    el.querySelectorAll("[data-sync-field]").forEach((input) => {
      input.addEventListener("change", () => {
        readSyncSettings();
        syncSettings = SyncClient.getSettings();
      });
    });

    el.querySelectorAll("[data-sync-act]").forEach((btn) => {
      btn.addEventListener("click", () => runSyncAction(btn.dataset.syncAct));
    });
  }

  render();
}
