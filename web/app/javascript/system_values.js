/**
 * System Values UI glue (vanilla JS)
 *
 * Responsibilities:
 * 1) Scoped horizontal scrolling per section table
 * 2) Sticky-left shadow visibility while horizontally scrolled
 * 3) Re-sync after Datastar DOM patches / layout changes
 */

let main = null;

const initSectionScrollShadow = (scrollEl) => {
  if (!scrollEl) return;
  if (scrollEl.dataset.systemValuesScrollInit === "true") return;

  const shadowEl = scrollEl.querySelector("[data-system-values-sticky-shadow]");
  if (!shadowEl) return;

  scrollEl.dataset.systemValuesScrollInit = "true";

  const updateShadow = () => {
    const showShadow = scrollEl.scrollLeft > 2;
    shadowEl.classList.toggle("opacity-0", !showShadow);
    shadowEl.classList.toggle("opacity-100", showShadow);
  };

  scrollEl.addEventListener("scroll", updateShadow, { passive: true });
  updateShadow();
};

const initAllSectionShadows = () => {
  if (!main) return;

  const scrollEls = main.querySelectorAll("[data-system-values-table-scroll]");
  scrollEls.forEach(initSectionScrollShadow);
};

const syncAllSectionShadows = () => {
  if (!main) return;

  const scrollEls = main.querySelectorAll("[data-system-values-table-scroll]");
  scrollEls.forEach((scrollEl) => {
    const shadowEl = scrollEl.querySelector("[data-system-values-sticky-shadow]");
    if (!shadowEl) return;

    const showShadow = scrollEl.scrollLeft > 2;
    shadowEl.classList.toggle("opacity-0", !showShadow);
    shadowEl.classList.toggle("opacity-100", showShadow);
  });
};

const init = () => {
  main = document.getElementById("maincanvas");
  if (!main) return;

  initAllSectionShadows();
  syncAllSectionShadows();

  window.addEventListener(
    "resize",
    () =>
      requestAnimationFrame(() => {
        initAllSectionShadows();
        syncAllSectionShadows();
      }),
    { passive: true }
  );

  const mutationObserver = new MutationObserver(() => {
    requestAnimationFrame(() => {
      initAllSectionShadows();
      syncAllSectionShadows();
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
