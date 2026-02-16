const DEFAULT_SCROLL_OFFSET = 120;
const WORKSPACE_TOP_GAP = 12; // matches the `pt-3`/`py-6` era top content spacing under the commandbar

function workspaceExtraOffset(workspace) {
  if (!workspace) return 0;

  const raw = workspace.dataset.scrollOffsetExtra;
  if (!raw) return 0;

  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) return 0;

  return Math.max(0, parsed);
}

function computeScrollOffset(workspace) {
  const bar = document.getElementById("commandbar");
  const extraOffset = workspaceExtraOffset(workspace);

  if (!bar) return Math.max(DEFAULT_SCROLL_OFFSET, Math.ceil(DEFAULT_SCROLL_OFFSET + extraOffset));

  const height = bar.getBoundingClientRect().height || bar.offsetHeight || 0;
  if (!height) return Math.max(DEFAULT_SCROLL_OFFSET, Math.ceil(DEFAULT_SCROLL_OFFSET + extraOffset));

  // Ensure we never go *smaller* than the legacy value (helps during transitions / no-commandbar pages).
  return Math.max(DEFAULT_SCROLL_OFFSET, Math.ceil(height + WORKSPACE_TOP_GAP + extraOffset));
}

function setActiveLink(links, activeId) {
  links.forEach((link) => {
    const href = link.getAttribute("href") || "";
    const id = href.startsWith("#") ? href.slice(1) : null;
    const isActive = id && id === activeId;

    link.dataset.active = isActive ? "true" : "false";
    if (isActive) {
      link.setAttribute("aria-current", "true");
    } else {
      link.removeAttribute("aria-current");
    }
  });
}

function setupWorkspace(workspace) {
  if (!workspace || workspace.dataset.entityScrollspyReady === "true") return;

  const nav = workspace.querySelector("[data-entity-scrollspy-nav]");
  if (!nav) return;

  const links = Array.from(nav.querySelectorAll("[data-entity-scrollspy-link]"));
  if (links.length === 0) return;

  const sections = links
    .map((link) => {
      const href = link.getAttribute("href") || "";
      if (!href.startsWith("#")) return null;

      const id = href.slice(1);
      if (!id) return null;

      const element = workspace.querySelector(`#${CSS.escape(id)}`);
      if (!element) return null;

      return { id, element };
    })
    .filter(Boolean)
    .sort((a, b) => a.element.offsetTop - b.element.offsetTop);

  if (sections.length === 0) return;

  let scrollOffset = computeScrollOffset(workspace);

  const findSectionById = (id) => sections.find((section) => section.id === id);

  const scrollToSection = (id, behavior = "smooth") => {
    const target = findSectionById(id);
    if (!target) return;

    const top = window.scrollY + target.element.getBoundingClientRect().top - scrollOffset + 1;
    window.scrollTo({ top: Math.max(top, 0), behavior });
    setActiveLink(links, id);
  };

  const refreshActiveFromScroll = () => {
    let active = sections[0];

    for (const section of sections) {
      const top = section.element.getBoundingClientRect().top;
      if (top - scrollOffset <= 0) {
        active = section;
      } else {
        break;
      }
    }

    setActiveLink(links, active.id);
  };

  let ticking = false;
  const onScroll = () => {
    if (ticking) return;

    ticking = true;
    requestAnimationFrame(() => {
      refreshActiveFromScroll();
      ticking = false;
    });
  };

  const refreshActiveFromHash = () => {
    const id = window.location.hash.replace(/^#/, "");
    if (!id) return;

    const target = findSectionById(id);
    if (!target) return;

    setActiveLink(links, id);
  };

  const onResize = () => {
    scrollOffset = computeScrollOffset(workspace);
    refreshActiveFromScroll();
  };

  const onLinkClick = (event) => {
    const href = event.currentTarget?.getAttribute("href") || "";
    if (!href.startsWith("#")) return;

    const id = href.slice(1);
    if (!id) return;

    const target = findSectionById(id);
    if (!target) return;

    event.preventDefault();
    history.replaceState(null, "", `#${id}`);
    scrollToSection(id);
  };

  links.forEach((link) => link.addEventListener("click", onLinkClick));

  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("hashchange", refreshActiveFromHash);
  window.addEventListener("resize", onResize, { passive: true });

  refreshActiveFromHash();
  refreshActiveFromScroll();

  workspace.dataset.entityScrollspyReady = "true";
}

function initEntityWorkspaces() {
  document.querySelectorAll("[data-entity-workspace]").forEach(setupWorkspace);
}

document.addEventListener("DOMContentLoaded", initEntityWorkspaces);
window.addEventListener("pageshow", initEntityWorkspaces);
