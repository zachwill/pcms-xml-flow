/**
 * Two-Way Utility UI glue (vanilla JS)
 *
 * Responsibilities:
 * 1) Horizontal scroll sync (header <-> body) per team table
 * 2) Sticky-left shadow visibility while horizontally scrolled
 * 3) Re-sync after Datastar DOM patches / layout changes
 */

let main = null;

const initTwoWayTableSync = (tableEl) => {
  if (!tableEl) return;
  if (tableEl.dataset.twoWayTableInit === "true") return;

  const headerEl = tableEl.querySelector("[data-two-way-table-header-scroll]");
  const bodyEl = tableEl.querySelector("[data-two-way-table-body-scroll]");
  const shadowEl = tableEl.querySelector("[data-two-way-table-sticky-shadow]");

  if (!headerEl || !bodyEl) return;

  tableEl.dataset.twoWayTableInit = "true";

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

  setShadow(bodyEl.scrollLeft);
};

const initAllTwoWayTables = () => {
  if (!main) return;
  const tables = main.querySelectorAll("[data-two-way-table]");
  tables.forEach(initTwoWayTableSync);
};

const syncAllTwoWayTableScrollPositions = () => {
  if (!main) return;

  const tables = main.querySelectorAll("[data-two-way-table]");
  tables.forEach((tableEl) => {
    const headerEl = tableEl.querySelector("[data-two-way-table-header-scroll]");
    const bodyEl = tableEl.querySelector("[data-two-way-table-body-scroll]");
    const shadowEl = tableEl.querySelector("[data-two-way-table-sticky-shadow]");

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

const init = () => {
  main = document.getElementById("maincanvas");
  if (!main) return;

  initAllTwoWayTables();
  syncAllTwoWayTableScrollPositions();

  window.addEventListener(
    "resize",
    () =>
      requestAnimationFrame(() => {
        initAllTwoWayTables();
        syncAllTwoWayTableScrollPositions();
      }),
    { passive: true }
  );

  const mutationObserver = new MutationObserver(() => {
    requestAnimationFrame(() => {
      initAllTwoWayTables();
      syncAllTwoWayTableScrollPositions();
    });
  });

  mutationObserver.observe(main, { childList: true, subtree: true });
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}

export { init };
