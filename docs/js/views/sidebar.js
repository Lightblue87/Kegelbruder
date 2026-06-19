// Sidebar — port of ContentView.swift's NavigationSplitView sidebar List.
import { sidebarIconTile } from "../components.js";

export function renderSidebar(vm) {
  const gameSection = vm.gameRunning
    ? `
      <button class="sidebar-item ${vm.route === "game" || vm.route === null ? "selected" : ""}" data-act="nav" data-route="game">
        ${sidebarIconTile("⬤", "var(--kb-primary)")} Laufendes Spiel
      </button>
      <button class="sidebar-item" data-act="abrechnung">
        ${sidebarIconTile("€", "var(--kb-success)")} Abrechnung
      </button>
      <button class="sidebar-item danger" data-act="abbrechen">
        ${sidebarIconTile("✕", "var(--kb-danger)")} Spiel abbrechen
      </button>
    `
    : `
      <button class="sidebar-item accent" data-act="neues-spiel">
        ${sidebarIconTile("▶", "var(--kb-primary)")} Neues Spiel
      </button>
    `;

  return `
    <div class="sidebar-header">
      <div class="logo"><img src="./icons/icon.svg" alt="Kegel Brüder" /></div>
      <div class="title">Kegel Brüder</div>
    </div>

    <div class="sidebar-section">
      <div class="sidebar-section-label">Spiel</div>
      ${gameSection}
    </div>

    <div class="sidebar-section">
      <div class="sidebar-section-label">Verwaltung</div>
      <button class="sidebar-item ${vm.route === "cash" ? "selected" : ""}" data-act="nav" data-route="cash">
        ${sidebarIconTile("€", "var(--kb-success)")} Kassenverwaltung
      </button>
      <button class="sidebar-item ${vm.route === "players" ? "selected" : ""}" data-act="nav" data-route="players">
        ${sidebarIconTile("👥", "var(--kb-neuner)")} Spieler verwalten
      </button>
      <button class="sidebar-item ${vm.route === "archive" ? "selected" : ""}" data-act="nav" data-route="archive">
        ${sidebarIconTile("🕘", "#8e8e93")} Archiv
      </button>
      <button class="sidebar-item ${vm.route === "settings" ? "selected" : ""}" data-act="nav" data-route="settings">
        ${sidebarIconTile("⚙", "#aeaeb2")} Einstellungen
      </button>
    </div>
  `;
}

export function bindSidebar(el, vm, actions) {
  el.querySelectorAll("[data-act]").forEach((node) => {
    node.addEventListener("click", () => {
      const act = node.dataset.act;
      if (act === "nav") actions.navigate(node.dataset.route);
      else if (act === "neues-spiel") actions.starteNeuesSpiel();
      else if (act === "abrechnung") actions.abrechnungStarten();
      else if (act === "abbrechen") actions.confirmAbbrechen();
    });
  });
}
