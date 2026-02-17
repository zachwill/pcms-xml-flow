import { mountLiveline, unmountLiveline } from "shared/liveline_datastar";

const WINDOW_OPTIONS = [
  { label: "15s", secs: 15 },
  { label: "30s", secs: 30 },
  { label: "2m", secs: 120 },
  { label: "5m", secs: 300 },
  { label: "15m", secs: 900 }
];

const DEFAULT_COLOR = "#3b82f6";

const resolveAppTheme = () => (document.documentElement.classList.contains("dark") ? "dark" : "light");

const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

const formatClock = (unixSeconds) => {
  const d = new Date(unixSeconds * 1000);
  const hh = d.getHours().toString().padStart(2, "0");
  const mm = d.getMinutes().toString().padStart(2, "0");
  const ss = d.getSeconds().toString().padStart(2, "0");
  return `${hh}:${mm}:${ss}`;
};

const detectLocalMomentum = (points) => {
  if (!Array.isArray(points) || points.length < 6) return "flat";

  const tail = points.slice(-6);
  const delta = tail[tail.length - 1].value - tail[0].value;

  if (Math.abs(delta) < 0.08) return "flat";
  return delta > 0 ? "up" : "down";
};

const buildOrderbook = (midValue, momentum) => {
  const bids = [];
  const asks = [];

  for (let level = 1; level <= 10; level += 1) {
    const step = 0.02 * level;

    const baseSize = 0.4 + Math.random() * 5;
    const bidBoost = momentum === "up" ? 1.3 : momentum === "down" ? 0.85 : 1;
    const askBoost = momentum === "down" ? 1.3 : momentum === "up" ? 0.85 : 1;

    bids.push([midValue - step, Number((baseSize * bidBoost).toFixed(3))]);
    asks.push([midValue + step, Number((baseSize * askBoost).toFixed(3))]);
  }

  return { bids, asks };
};

const init = () => {
  const root = document.getElementById("liveline-test");
  if (!root) return;

  if (typeof root.__livelineTestCleanup === "function") {
    root.__livelineTestCleanup();
  }

  const chartHost = document.getElementById("liveline-test-chart");
  const controls = root.querySelector("[data-liveline-controls]");

  if (!chartHost || !controls) return;

  const metricLatestValue = root.querySelector("[data-liveline-metric='latest-value']");
  const metricLatestTime = root.querySelector("[data-liveline-metric='latest-time']");
  const metricWindow = root.querySelector("[data-liveline-metric='window']");
  const metricPoints = root.querySelector("[data-liveline-metric='points']");
  const metricMomentum = root.querySelector("[data-liveline-metric='momentum']");
  const metricHoverValue = root.querySelector("[data-liveline-metric='hover-value']");
  const metricHoverTime = root.querySelector("[data-liveline-metric='hover-time']");

  const themeSelect = controls.querySelector("[name='theme']");
  const colorInput = controls.querySelector("[name='color']");
  const momentumSelect = controls.querySelector("[name='momentum']");

  const initialTheme = resolveAppTheme();
  if (themeSelect) {
    themeSelect.value = initialTheme;
  }
  const badgeVariantSelect = controls.querySelector("[name='badgeVariant']");
  const windowStyleSelect = controls.querySelector("[name='windowStyle']");
  const lerpInput = controls.querySelector("[name='lerpSpeed']");
  const lerpValue = controls.querySelector("[data-liveline-lerp-value]");

  let currentWindowSecs = WINDOW_OPTIONS[1].secs;

  let currentValue = 103.25;
  let trend = 0;
  const points = [];

  const now = Date.now() / 1000;
  let seedValue = currentValue;
  for (let i = 240; i >= 1; i -= 1) {
    const t = now - i * 0.5;
    const noise = (Math.random() - 0.5) * 0.14;
    seedValue += noise;
    points.push({ time: t, value: seedValue });
  }
  currentValue = points[points.length - 1].value;

  const checkbox = (name) => {
    const input = controls.querySelector(`[name='${name}']`);
    return !!(input && input.checked);
  };

  const readOptionsFromControls = () => {
    const momentumRaw = momentumSelect?.value || "auto";
    let momentum = true;
    if (momentumRaw === "off") momentum = false;
    if (["up", "down", "flat"].includes(momentumRaw)) momentum = momentumRaw;

    const lerpSpeed = Number(lerpInput?.value || 0.08);

    if (lerpValue) {
      lerpValue.textContent = lerpSpeed.toFixed(2);
    }

    return {
      theme: themeSelect?.value === "light" ? "light" : "dark",
      color: colorInput?.value || DEFAULT_COLOR,
      momentum,
      badgeVariant: badgeVariantSelect?.value === "minimal" ? "minimal" : "default",
      windowStyle: windowStyleSelect?.value || "default",
      lerpSpeed: clamp(Number.isFinite(lerpSpeed) ? lerpSpeed : 0.08, 0.01, 0.5),
      tooltipY: 14,
      grid: checkbox("grid"),
      badge: checkbox("badge"),
      badgeTail: checkbox("badgeTail"),
      fill: checkbox("fill"),
      pulse: checkbox("pulse"),
      scrub: checkbox("scrub"),
      exaggerate: checkbox("exaggerate"),
      showValue: checkbox("showValue"),
      valueMomentumColor: checkbox("valueMomentumColor"),
      degen: checkbox("degen"),
      orderbookEnabled: checkbox("orderbook")
    };
  };

  const applyStats = (momentum) => {
    if (metricLatestValue) metricLatestValue.textContent = `$${currentValue.toFixed(2)}`;
    if (metricLatestTime) metricLatestTime.textContent = formatClock(points[points.length - 1].time);
    if (metricWindow) metricWindow.textContent = `${currentWindowSecs}s`;
    if (metricPoints) metricPoints.textContent = String(points.length);
    if (metricMomentum) metricMomentum.textContent = momentum;
  };

  const chart = mountLiveline(chartHost, {
    data: points,
    value: currentValue,
    theme: initialTheme,
    color: DEFAULT_COLOR,
    window: currentWindowSecs,
    windows: WINDOW_OPTIONS,
    windowStyle: "default",
    badgeVariant: "default",
    grid: true,
    badge: true,
    badgeTail: true,
    fill: true,
    pulse: true,
    scrub: true,
    exaggerate: false,
    showValue: true,
    valueMomentumColor: false,
    degen: false,
    orderbook: buildOrderbook(currentValue, "flat"),
    tooltipY: 14,
    tooltipOutline: true,
    formatValue: (v) => `$${v.toFixed(2)}`,
    onWindowChange: (secs) => {
      currentWindowSecs = secs;
      if (metricWindow) metricWindow.textContent = `${secs}s`;
    },
    onHover: (point) => {
      if (!metricHoverValue || !metricHoverTime) return;

      if (!point) {
        metricHoverValue.textContent = "—";
        metricHoverTime.textContent = "—";
        return;
      }

      metricHoverValue.textContent = `$${point.value.toFixed(2)}`;
      metricHoverTime.textContent = formatClock(point.time);
    }
  });

  const applyControls = () => {
    const parsed = readOptionsFromControls();
    const localMomentum = detectLocalMomentum(points);

    chart.setOptions({
      data: points,
      value: currentValue,
      theme: parsed.theme,
      color: parsed.color,
      momentum: parsed.momentum,
      badgeVariant: parsed.badgeVariant,
      windowStyle: parsed.windowStyle,
      lerpSpeed: parsed.lerpSpeed,
      tooltipY: parsed.tooltipY,
      grid: parsed.grid,
      badge: parsed.badge,
      badgeTail: parsed.badgeTail,
      fill: parsed.fill,
      pulse: parsed.pulse,
      scrub: parsed.scrub,
      exaggerate: parsed.exaggerate,
      showValue: parsed.showValue,
      valueMomentumColor: parsed.valueMomentumColor,
      degen: parsed.degen,
      orderbook: parsed.orderbookEnabled ? buildOrderbook(currentValue, localMomentum) : undefined,
      windows: WINDOW_OPTIONS
    });
  };

  const onControlChange = () => applyControls();

  let themeObserver = null;
  if (typeof MutationObserver !== "undefined") {
    themeObserver = new MutationObserver(() => {
      const appTheme = resolveAppTheme();
      if (!themeSelect || themeSelect.value === appTheme) return;
      themeSelect.value = appTheme;
      applyControls();
    });

    themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class"]
    });
  }

  controls.addEventListener("input", onControlChange);
  controls.addEventListener("change", onControlChange);

  let timerId = null;

  const tick = () => {
    const nowTs = Date.now() / 1000;

    const volatilityBoost = Math.random() < 0.08 ? 2.8 : 1;
    const randomShock = (Math.random() - 0.5) * 0.45 * volatilityBoost;
    trend = trend * 0.74 + (Math.random() - 0.5) * 0.12;

    currentValue = Math.max(5, currentValue + randomShock + trend);

    points.push({ time: nowTs, value: currentValue });

    const retentionSeconds = Math.max(currentWindowSecs * 3, 900);
    const cutoff = nowTs - retentionSeconds;
    while (points.length > 3 && points[0].time < cutoff) {
      points.shift();
    }

    const parsed = readOptionsFromControls();
    const localMomentum = detectLocalMomentum(points);

    chart.setOptions({
      data: points,
      value: currentValue,
      orderbook: parsed.orderbookEnabled ? buildOrderbook(currentValue, localMomentum) : undefined
    });

    applyStats(localMomentum);
  };

  applyControls();
  applyStats("flat");
  tick();

  timerId = window.setInterval(tick, 700);

  root.__livelineTestCleanup = () => {
    controls.removeEventListener("input", onControlChange);
    controls.removeEventListener("change", onControlChange);

    if (timerId) {
      window.clearInterval(timerId);
      timerId = null;
    }

    if (themeObserver) {
      themeObserver.disconnect();
      themeObserver = null;
    }

    unmountLiveline(chartHost);
    delete root.__livelineTestCleanup;
  };
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}

window.addEventListener("pageshow", init);

export { init };
