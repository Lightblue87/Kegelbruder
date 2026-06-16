// Small reusable HTML-string components — mirrors KBPill/KBGlassButton/KBGroupBox/KBRow.
import { escapeHtml } from "./format.js";

export function pill(text, tone = "neutral") {
  return `<span class="kb-pill ${tone}">${escapeHtml(text)}</span>`;
}

export function icon(emoji) {
  return `<span aria-hidden="true">${emoji}</span>`;
}

export function sidebarIconTile(emoji, colorVar) {
  return `<span class="sidebar-icon" style="background:${colorVar}">${emoji}</span>`;
}

export function groupHeader(title) {
  return `<div class="kb-group-header">${escapeHtml(title.toUpperCase())}</div>`;
}

export function rowDivider() {
  return `<div class="kb-row-divider"></div>`;
}

export function emptyState(emoji, title, subtitle = "") {
  return `
    <div class="u-empty">
      <div class="ico">${emoji}</div>
      <div style="font-size:18px;font-weight:600;color:var(--kb-text)">${escapeHtml(title)}</div>
      ${subtitle ? `<div style="font-size:13px;max-width:320px">${escapeHtml(subtitle)}</div>` : ""}
    </div>
  `;
}

export function alertHostRender(alertState) {
  const host = document.getElementById("alert-host");
  if (!alertState) {
    host.classList.remove("open");
    host.innerHTML = "";
    return;
  }
  host.classList.add("open");
  host.innerHTML = `
    <div class="alert-card">
      <h3>${escapeHtml(alertState.title)}</h3>
      ${alertState.message ? `<p>${escapeHtml(alertState.message)}</p>` : ""}
      <div class="alert-actions">
        ${alertState.buttons
          .map(
            (b, i) =>
              `<button data-idx="${i}" class="${b.role === "destructive" ? "destructive" : b.role === "cancel" ? "cancel" : ""}">${escapeHtml(b.label)}</button>`
          )
          .join("")}
      </div>
    </div>
  `;
  host.querySelectorAll("button[data-idx]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const b = alertState.buttons[Number(btn.dataset.idx)];
      host.classList.remove("open");
      host.innerHTML = "";
      if (b.onClick) b.onClick();
    });
  });
}
