/**
 * Salary Book UI glue (vanilla JS)
 *
 * Responsibilities:
 * 1) Scroll-spy (active team) for the main canvas.
 * 2) Salary table horizontal scroll sync (header <-> body).
 *
 * Public API (exposed on window):
 * - __salaryBookScrollToTeam(teamCode, behavior = "smooth")
 * - __salaryBookRebuildCache()
 * - __salaryBookPreserveContext()
 */

let main = null;
let lastActiveTeam = null;

// Programmatic scroll lock - ignore scroll-spy updates during programmatic scroll
let isScrollingProgrammatically = false;
let scrollLockTimer = null;

// RAF throttle for scroll-spy
let scrollSpyRaf = null;

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
// Scroll-spy (active team)
// -------------------------------------------------------------------------

/**
 * Determine which team is currently active.
 *
 * Desired behavior:
 * - The active team is the one whose TeamHeader is currently "sticky" at the
 *   top of the main canvas.
 *
 * Why we use elementFromPoint():
 * - IntersectionObserver + sentinels is surprisingly easy to get wrong here,
 *   because "not intersecting" conflates (a) elements above the sticky line
 *   and (b) elements far below the viewport.
 * - The browser already knows which sticky header is actually at the top; we
 *   can ask it directly with a single hit-test.
 */
const getActiveTeamFromDOM = () => {
  if (!main) return null;

  const rect = main.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return null;

  // Probe point: inside the main canvas, near the top-left corner.
  // This lands inside the sticky TeamHeader for the active section.
  const x = Math.min(rect.right - 1, rect.left + 24);
  const y = Math.min(rect.bottom - 1, rect.top + 8);

  const hit = document.elementFromPoint(x, y);
  if (!hit) return null;

  const section = hit.closest?.("section[data-teamcode]");
  return section?.dataset?.teamcode || null;
};

const dispatchActiveTeam = (team) => {
  if (!main) return;
  if (!team) return;
  if (team === lastActiveTeam) return;

  lastActiveTeam = team;

  main.dispatchEvent(
    new CustomEvent("salarybook-activeteam", {
      detail: { team },
      bubbles: true,
    })
  );
};

const getTeamFromHash = () => {
  const raw = (window.location.hash || "").replace(/^#/, "").trim().toUpperCase();
  if (!raw.match(/^[A-Z]{3}$/)) return null;
  return raw;
};

const updateActiveTeam = () => {
  const team = getActiveTeamFromDOM();
  if (team) dispatchActiveTeam(team);
};

const onMainScroll = () => {
  if (isScrollingProgrammatically) return;

  if (scrollSpyRaf !== null) return;
  scrollSpyRaf = requestAnimationFrame(() => {
    scrollSpyRaf = null;
    updateActiveTeam();
  });
};

// -------------------------------------------------------------------------
// Programmatic navigation API (used by command bar)
// -------------------------------------------------------------------------

const scrollToTeam = (teamCode, behavior = "smooth") => {
  const section = main?.querySelector(`section[data-teamcode="${teamCode}"]`);
  if (!section) return;

  // Lock to prevent scroll-spy updates during scroll animation
  isScrollingProgrammatically = true;
  if (scrollLockTimer) clearTimeout(scrollLockTimer);

  // Immediately set as active to prevent flicker
  dispatchActiveTeam(teamCode);

  const maxScroll = main.scrollHeight - main.clientHeight;
  const targetTop = section.offsetTop;

  main.scrollTo({
    top: Math.max(0, Math.min(targetTop, maxScroll)),
    behavior,
  });

  // Unlock after scroll completes (or after timeout)
  const unlockDelay = behavior === "instant" ? 50 : 500;
  scrollLockTimer = setTimeout(() => {
    isScrollingProgrammatically = false;
    scrollLockTimer = null;

    // Re-sync (covers interrupted/short-circuited smooth scroll)
    updateActiveTeam();
  }, unlockDelay);
};

// Preserve context after layout changes (filter toggles)
const preserveContext = () => {
  requestAnimationFrame(() => {
    if (lastActiveTeam) {
      scrollToTeam(lastActiveTeam, "instant");
    } else {
      updateActiveTeam();
    }

    // Layout toggles (like EPM) can change table widths; force header/body re-sync.
    syncAllSalaryTableScrollPositions();
  });
};

// "Cache rebuild" kept for backwards-compat with earlier approaches.
// Today: re-init table sync + re-evaluate active team.
const rebuildCache = () => {
  if (!main) return;
  initAllSalaryTables();
  syncAllSalaryTableScrollPositions();
  updateActiveTeam();
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

  // Scroll-spy
  main.addEventListener("scroll", onMainScroll, { passive: true });

  // Initial active team:
  // - if URL has #TEAM (e.g. #POR), force main-canvas sync to that team
  // - otherwise derive from current sticky position
  requestAnimationFrame(() => {
    const hashTeam = getTeamFromHash();
    const hasHashSection = hashTeam && main.querySelector(`section[data-teamcode="${hashTeam}"]`);

    if (hasHashSection) {
      scrollToTeam(hashTeam, "instant");
    } else {
      updateActiveTeam();
    }
  });

  // Late sync pass for browsers that apply hash/restored scroll after first paint.
  setTimeout(() => {
    const hashTeam = getTeamFromHash();
    const hasHashSection = hashTeam && main.querySelector(`section[data-teamcode="${hashTeam}"]`);

    if (hasHashSection && hashTeam !== lastActiveTeam) {
      scrollToTeam(hashTeam, "instant");
    } else {
      updateActiveTeam();
    }
  }, 120);

  window.addEventListener(
    "resize",
    () =>
      requestAnimationFrame(() => {
        initAllSalaryTables();
        syncAllSalaryTableScrollPositions();
        updateActiveTeam();
      }),
    { passive: true }
  );

  window.addEventListener("hashchange", () => {
    const hashTeam = getTeamFromHash();
    const hasHashSection = hashTeam && main.querySelector(`section[data-teamcode="${hashTeam}"]`);
    if (!hasHashSection) return;

    scrollToTeam(hashTeam, "smooth");
  });

  // Observe DOM changes inside main (future-proofing for Datastar patches)
  const mutationObserver = new MutationObserver(() => {
    requestAnimationFrame(() => {
      initAllSalaryTables();
      syncAllSalaryTableScrollPositions();
      updateActiveTeam();
    });
  });
  mutationObserver.observe(main, { childList: true, subtree: true });

  // Expose public API
  window.__salaryBookScrollToTeam = scrollToTeam;
  window.__salaryBookRebuildCache = rebuildCache;
  window.__salaryBookPreserveContext = preserveContext;

  console.debug("[salary_book] initialized");
};

// Auto-init when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}

// Export for ES module usage
export { init, scrollToTeam, rebuildCache, preserveContext };
