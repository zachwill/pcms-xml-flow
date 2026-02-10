/**
 * Salary Book UI glue (vanilla JS)
 *
 * Responsibilities:
 * 1) Salary table horizontal scroll sync (header <-> body)
 * 2) Re-sync after Datastar DOM patches / layout changes
 */

let main = null;

// -------------------------------------------------------------------------
// SalaryTable horizontal scroll sync (per team section)
// -------------------------------------------------------------------------

const initSalaryTableSync = (tableEl) => {
  if (!tableEl) return;
  if (tableEl.dataset.salarytableInit === "true") return;

  const headerEl = tableEl.querySelector("[data-salarytable-header-scroll]");
  const bodyEl = tableEl.querySelector("[data-salarytable-body-scroll]");
  const shadowEl = tableEl.querySelector("[data-salarytable-sticky-shadow]");

  if (!headerEl || !bodyEl) return;

  tableEl.dataset.salarytableInit = "true";

  let syncing = null;

  const setShadow = (scrollLeft) => {
    if (!shadowEl) return;
    if (scrollLeft > 2) {
      shadowEl.classList.add("opacity-100");
      shadowEl.classList.remove("opacity-0");
    } else {
      shadowEl.classList.add("opacity-0");
      shadowEl.classList.remove("opacity-100");
    }
  };

  const syncScroll = (source) => {
    if (syncing && syncing !== source) return;
    syncing = source;

    if (source === "body") {
      headerEl.scrollLeft = bodyEl.scrollLeft;
      setShadow(bodyEl.scrollLeft);
    } else {
      bodyEl.scrollLeft = headerEl.scrollLeft;
      setShadow(headerEl.scrollLeft);
    }

    requestAnimationFrame(() => {
      syncing = null;
    });
  };

  headerEl.addEventListener("scroll", () => syncScroll("header"), { passive: true });
  bodyEl.addEventListener("scroll", () => syncScroll("body"), { passive: true });

  // Initial state
  setShadow(bodyEl.scrollLeft);
};

const initAllSalaryTables = () => {
  if (!main) return;
  const tables = main.querySelectorAll("[data-salarytable]");
  tables.forEach(initSalaryTableSync);
};

const syncAllSalaryTableScrollPositions = () => {
  if (!main) return;

  const tables = main.querySelectorAll("[data-salarytable]");
  tables.forEach((tableEl) => {
    const headerEl = tableEl.querySelector("[data-salarytable-header-scroll]");
    const bodyEl = tableEl.querySelector("[data-salarytable-body-scroll]");
    const shadowEl = tableEl.querySelector("[data-salarytable-sticky-shadow]");

    if (!headerEl || !bodyEl) return;

    headerEl.scrollLeft = bodyEl.scrollLeft;

    if (!shadowEl) return;
    if (bodyEl.scrollLeft > 2) {
      shadowEl.classList.add("opacity-100");
      shadowEl.classList.remove("opacity-0");
    } else {
      shadowEl.classList.add("opacity-0");
      shadowEl.classList.remove("opacity-100");
    }
  });
};

// -------------------------------------------------------------------------
// Public API (kept for backwards compatibility)
// -------------------------------------------------------------------------

const scrollToTeam = (_teamCode, _behavior = "smooth") => {
  // Single-team canvas now loads by Datastar signal; no JS scrolling needed.
};

const preserveContext = () => {
  requestAnimationFrame(() => {
    syncAllSalaryTableScrollPositions();
  });
};

const rebuildCache = () => {
  if (!main) return;
  initAllSalaryTables();
  syncAllSalaryTableScrollPositions();
};

// -------------------------------------------------------------------------
// Initialization
// -------------------------------------------------------------------------

const init = () => {
  main = document.getElementById("maincanvas");
  if (!main) {
    console.debug("[salary_book] #maincanvas not found, skipping init");
    return;
  }

  initAllSalaryTables();
  syncAllSalaryTableScrollPositions();

  window.addEventListener(
    "resize",
    () =>
      requestAnimationFrame(() => {
        initAllSalaryTables();
        syncAllSalaryTableScrollPositions();
      }),
    { passive: true }
  );

  const mutationObserver = new MutationObserver(() => {
    requestAnimationFrame(() => {
      initAllSalaryTables();
      syncAllSalaryTableScrollPositions();
    });
  });

  mutationObserver.observe(main, { childList: true, subtree: true });

  // Expose public API
  window.__salaryBookScrollToTeam = scrollToTeam;
  window.__salaryBookRebuildCache = rebuildCache;
  window.__salaryBookPreserveContext = preserveContext;

  console.debug("[salary_book] initialized");
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}

export { init, scrollToTeam, rebuildCache, preserveContext };
