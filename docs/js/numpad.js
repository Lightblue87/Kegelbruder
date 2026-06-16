// Custom numeric popover — port of KBNumPadField/KBNumPadGrid.
// Avoids the native mobile keyboard entirely so behaviour stays identical
// across iPad/iPhone/Android/Desktop (same reasoning as the iOS app).

let host = null;
let activeOnDone = null;

function ensureHost() {
  if (host) return host;
  host = document.getElementById("numpad-host");
  return host;
}

function close() {
  const h = ensureHost();
  h.classList.remove("open");
  h.innerHTML = "";
  if (activeOnDone) {
    const cb = activeOnDone;
    activeOnDone = null;
    cb();
  }
}

/**
 * Opens the numpad popover for the given text value.
 * @param {string} value current text
 * @param {{allowsDecimal:boolean}} opts
 * @param {(value:string)=>void} onChange called on every keystroke
 * @param {()=>void} [onDone] called when the user taps "Fertig"
 */
export function openNumpad(value, opts, onChange, onDone) {
  const h = ensureHost();
  let text = value || "";
  const allowsDecimal = !!opts.allowsDecimal;
  const sep = (0.5).toLocaleString(undefined, { minimumFractionDigits: 1 }).includes(",") ? "," : ".";

  activeOnDone = onDone || null;

  const rows = [
    ["1", "2", "3"],
    ["4", "5", "6"],
    ["7", "8", "9"],
  ];

  function render() {
    h.innerHTML = `
      <div class="numpad-card" role="dialog">
        <div class="numpad-grid">
          ${rows.flat().map((d) => `<button class="numpad-key" data-digit="${d}">${d}</button>`).join("")}
          ${allowsDecimal ? `<button class="numpad-key" data-sep="1">${sep}</button>` : `<div></div>`}
          <button class="numpad-key" data-digit="0">0</button>
          <button class="numpad-key" data-back="1">⌫</button>
        </div>
        <button class="numpad-done">Fertig</button>
      </div>
    `;
    h.querySelectorAll("[data-digit]").forEach((btn) => {
      btn.addEventListener("click", () => {
        text += btn.dataset.digit;
        onChange(text);
      });
    });
    const sepBtn = h.querySelector("[data-sep]");
    if (sepBtn) {
      sepBtn.addEventListener("click", () => {
        if (text.includes(",") || text.includes(".")) return;
        text += text === "" ? `0${sep}` : sep;
        onChange(text);
      });
    }
    h.querySelector("[data-back]").addEventListener("click", () => {
      text = text.slice(0, -1);
      onChange(text);
    });
    h.querySelector(".numpad-done").addEventListener("click", close);
  }

  render();
  h.classList.add("open");

  // Tap outside the card also confirms/closes (matches popover dismiss).
  h.onclick = (e) => {
    if (e.target === h) close();
  };
}

/**
 * Wires a "numfield" element (a <button> styled like a text field) to open
 * the numpad popover on click, mirroring KBNumPadField's behaviour.
 */
export function bindNumField(el, getValue, setValue, opts = {}) {
  el.addEventListener("click", () => {
    openNumpad(getValue(), opts, (val) => {
      setValue(val);
      el.textContent = val === "" ? (opts.placeholder || "0") : val;
      el.classList.toggle("placeholder", val === "");
    });
  });
}
