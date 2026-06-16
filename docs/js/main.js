import { createVm } from "./state.js";
import { DB } from "./db.js";
import { renderSidebar, bindSidebar } from "./views/sidebar.js";
import { renderReadyScreen, bindReadyScreen, renderGameSession, bindGameSession } from "./views/gameSession.js";
import { mountCashManagement } from "./views/cashManagement.js";
import { mountPlayerManagement } from "./views/playerManagement.js";
import { mountArchive } from "./views/archive.js";
import { mountSettings } from "./views/settings.js";
import { mountAttendance } from "./views/attendance.js";
import { mountPlayerSort } from "./views/playerSort.js";
import { mountBilling } from "./views/billing.js";
import { mountTiebreak } from "./views/tiebreak.js";
import { mountPumpenTiebreak } from "./views/pumpenTiebreak.js";
import { alertHostRender } from "./components.js";

const sidebarEl = document.getElementById("sidebar");
const detailEl = document.getElementById("detail");
const sheetHost = document.getElementById("sheet-host");
const sidebarToggle = document.getElementById("sidebar-toggle");

let vm; // assigned once DB.init() resolves, see boot() at the bottom
let lastDetailKey = undefined;

function detailKey() {
  if (vm.route === "game" || (vm.route === null && vm.gameRunning)) return "game";
  if (vm.route === null) return "ready";
  return vm.route;
}

// ---------------------------------------------------------------- Sidebar

function renderSidebarOnly() {
  sidebarEl.innerHTML = renderSidebar(vm);
  bindSidebar(sidebarEl, vm, actions);
}

// ---------------------------------------------------------------- Detail (only remounts when the route actually changes)

function mountDetail() {
  const key = detailKey();
  if (key === lastDetailKey) return;
  lastDetailKey = key;

  if (key === "ready") {
    detailEl.innerHTML = renderReadyScreen();
    bindReadyScreen(detailEl, actions);
  } else if (key === "game") {
    renderGameDetail();
  } else if (key === "cash") {
    mountCashManagement(detailEl, vm, ctx);
  } else if (key === "players") {
    mountPlayerManagement(detailEl, vm, ctx);
  } else if (key === "archive") {
    mountArchive(detailEl, vm, ctx);
  } else if (key === "settings") {
    mountSettings(detailEl, vm, ctx);
  }
}

function renderGameDetail() {
  detailEl.innerHTML = renderGameSession(vm);
  bindGameSession(detailEl, vm, {
    rerender: () => {
      renderGameDetail();
      renderSidebarOnly();
    },
    abrechnungStarten: actions.abrechnungStarten,
  });
}

// ---------------------------------------------------------------- Sheets

function openSheet(name) {
  sheetHost.classList.add("open");
  sheetHost.innerHTML = `<div class="sheet-backdrop"></div><div class="sheet-card"></div>`;
  const card = sheetHost.querySelector(".sheet-card");
  const sheetCtx = {
    close: () => closeSheet(),
    openSheet: (n) => openSheet(n),
    rerenderApp: () => fullRender(),
  };
  if (name === "attendance") mountAttendance(card, vm, sheetCtx);
  else if (name === "playerSort") mountPlayerSort(card, vm, sheetCtx);
  else if (name === "billing") mountBilling(card, vm, sheetCtx);
  else if (name === "tiebreak") mountTiebreak(card, vm, sheetCtx);
  else if (name === "pumpenStechen") mountPumpenTiebreak(card, vm, sheetCtx);
}

function closeSheet() {
  sheetHost.classList.remove("open");
  sheetHost.innerHTML = "";
  renderSidebarOnly();
}

// ---------------------------------------------------------------- Actions (wired from sidebar / views)

const ctx = {
  refreshSidebar: () => renderSidebarOnly(),
  showAlert: (a) => alertHostRender(a),
  applyTheme: (theme) => applyTheme(theme),
};

const actions = {
  navigate(route) {
    vm.route = route;
    fullRender();
    closeMobileSidebar();
  },
  starteNeuesSpiel() {
    if (vm.starteNeuesSpiel()) openSheet("attendance");
    else alertHostRender(vm.alert);
    renderSidebarOnly();
  },
  abrechnungStarten() {
    const sheet = vm.abrechnungStarten();
    if (sheet) openSheet(sheet);
    fullRender();
  },
  confirmAbbrechen() {
    vm.alert = {
      title: "Spiel wirklich abbrechen?",
      message: "Alle Punkte und Startgebühren dieses Spiels werden zurückgesetzt. Diese Aktion kann nicht rückgängig gemacht werden.",
      buttons: [
        { label: "Abbrechen", role: "cancel" },
        {
          label: "Ja, abbrechen",
          role: "destructive",
          onClick: () => {
            vm.spielAbbrechen();
            fullRender();
          },
        },
      ],
    };
    alertHostRender(vm.alert);
  },
};

// ---------------------------------------------------------------- Theme

function applyTheme(theme) {
  document.documentElement.setAttribute("data-theme", theme);
}

// ---------------------------------------------------------------- Mobile sidebar drawer

function closeMobileSidebar() {
  sidebarEl.classList.remove("open");
}
sidebarToggle.addEventListener("click", () => sidebarEl.classList.toggle("open"));

// ---------------------------------------------------------------- Full render cycle

function fullRender() {
  renderSidebarOnly();
  mountDetail();
}

// ---------------------------------------------------------------- Boot

async function boot() {
  try {
    await DB.init(); // loads sql.js (WASM) + restores the SQLite blob from IndexedDB
    vm = createVm();
    vm.subscribe(fullRender);
    applyTheme(DB.getSettings().theme || "system");
    fullRender();
  } catch (e) {
    console.error("Start fehlgeschlagen:", e);
    detailEl.innerHTML = `
      <div class="u-empty" style="height:100%">
        <div class="ico">⚠️</div>
        <div style="font-size:18px;font-weight:600">App konnte nicht gestartet werden</div>
        <div style="max-width:360px">${e?.message || e}</div>
      </div>
    `;
  }
}
boot();

// ---------------------------------------------------------------- Service worker registration

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js").catch((e) => console.warn("SW-Registrierung fehlgeschlagen:", e));
  });
}
