const MAP_NAME = "NoahShotchartSvg";
const SVG_URL = "/shotchart.svg";

const FONT_SANS = "ui-sans-serif, system-ui, -apple-system, \"Segoe UI\", Roboto, Helvetica, Arial, sans-serif";
const FONT_MONO = "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace";

const FALLBACK_ZONES = [
  { name: "left-corner-three", attempts: 45, made: 18 },
  { name: "left-wing-three", attempts: 62, made: 24 },
  { name: "middle-three", attempts: 38, made: 12 },
  { name: "right-wing-three", attempts: 58, made: 26 },
  { name: "right-corner-three", attempts: 42, made: 19 },
  { name: "left-corner-two", attempts: 28, made: 16 },
  { name: "left-wing-two", attempts: 52, made: 28 },
  { name: "middle-two", attempts: 34, made: 18 },
  { name: "right-wing-two", attempts: 48, made: 25 },
  { name: "right-corner-two", attempts: 30, made: 17 },
  { name: "paint", attempts: 125, made: 82 },
  { name: "rim", attempts: 156, made: 118 },
  { name: "far-three", attempts: 8, made: 2 }
];

function formatZoneLabel(zoneName) {
  return String(zoneName || "")
    .split("-")
    .map((part) => (part ? part[0].toUpperCase() + part.slice(1) : ""))
    .join(" ");
}

function numberWithDelimiter(value) {
  const number = Number(value || 0);
  if (!Number.isFinite(number)) return "0";
  return number.toLocaleString("en-US");
}

function currentThemePalette() {
  const rootStyles = getComputedStyle(document.documentElement);
  const isDark = document.documentElement.classList.contains("dark");

  const cssVar = (name, fallback) => {
    const value = rootStyles.getPropertyValue(name);
    return value && value.trim() ? value.trim() : fallback;
  };

  return {
    isDark,
    foreground: cssVar("--foreground", isDark ? "#ededed" : "#171717"),
    mutedForeground: cssVar("--muted-foreground", isDark ? "#a3a3a3" : "#737373"),
    border: cssVar("--border", isDark ? "#262626" : "#e5e5e5"),
    noShots: "#E9EAEC",
    tooltipBackground: isDark ? "rgba(17, 17, 17, 0.96)" : "rgba(255, 255, 255, 0.96)",
    tooltipBorder: isDark ? "rgba(255, 255, 255, 0.12)" : "rgba(0, 0, 0, 0.10)",
    tooltipShadow: isDark ? "0 8px 24px rgba(0, 0, 0, 0.50)" : "0 8px 24px rgba(0, 0, 0, 0.12)"
  };
}

function zoneToSeriesDatum(zone) {
  const attempts = Number(zone?.attempts || 0);
  const made = Number(zone?.made || 0);
  const fgPct = attempts > 0 ? (made / attempts) * 100 : null;
  const heatValue = fgPct == null ? null : Math.round(fgPct * 10) / 10;

  return {
    name: String(zone?.name || "unassigned"),
    value: heatValue,
    fgPct,
    attempts,
    made,
    noAttempts: attempts <= 0
  };
}

function buildSeriesData(zones, theme) {
  return zones.map((zone) => {
    const datum = zoneToSeriesDatum(zone);
    if (!datum.noAttempts) return datum;

    return {
      ...datum,
      itemStyle: {
        areaColor: theme.noShots
      }
    };
  });
}

function parsePayload(container) {
  if (!container) return { zones: FALLBACK_ZONES };

  const script = container.querySelector("#noah-shotchart-payload");
  if (!script) return { zones: FALLBACK_ZONES };

  try {
    const payload = JSON.parse(script.textContent || "{}");
    if (!payload || typeof payload !== "object") {
      return { zones: FALLBACK_ZONES };
    }

    const zones = Array.isArray(payload.zones) ? payload.zones : FALLBACK_ZONES;
    return { zones };
  } catch (error) {
    console.error("[noah-shotchart] Failed to parse payload", error);
    return { zones: FALLBACK_ZONES };
  }
}

function buildBaseOption(theme) {
  return {
    backgroundColor: "transparent",
    animationDuration: 250,
    textStyle: {
      fontFamily: FONT_SANS
    },
    tooltip: {
      trigger: "item",
      backgroundColor: theme.tooltipBackground,
      borderColor: theme.tooltipBorder,
      borderWidth: 1,
      textStyle: {
        color: theme.foreground,
        fontFamily: FONT_SANS,
        fontSize: 12
      },
      extraCssText: `box-shadow: ${theme.tooltipShadow}; border-radius: 8px;`,
      formatter(params) {
        if (!params?.data) return params?.name || "";

        const datum = params.data;
        const attempts = Number(datum.attempts || 0);
        const made = Number(datum.made || 0);
        const hasAttempts = attempts > 0;

        const fgText = hasAttempts
          ? `${Number(datum.fgPct || 0).toFixed(1)}%`
          : "—";

        const shotText = hasAttempts
          ? `${numberWithDelimiter(made)} / ${numberWithDelimiter(attempts)}`
          : "No shots";

        return `
          <div style="min-width: 148px; font-family: ${FONT_SANS};">
            <div style="font-size: 12px; font-weight: 600; margin-bottom: 6px;">${formatZoneLabel(datum.name)}</div>
            <div style="display: flex; justify-content: space-between; gap: 12px; font-size: 11px; margin-bottom: 2px;">
              <span style="color: ${theme.mutedForeground};">FG%</span>
              <span style="font-family: ${FONT_MONO}; font-variant-numeric: tabular-nums;">${fgText}</span>
            </div>
            <div style="display: flex; justify-content: space-between; gap: 12px; font-size: 11px;">
              <span style="color: ${theme.mutedForeground};">Made</span>
              <span style="font-family: ${FONT_MONO}; font-variant-numeric: tabular-nums;">${shotText}</span>
            </div>
          </div>
        `;
      }
    },
    visualMap: {
      min: 0,
      max: 100,
      left: "center",
      bottom: "2%",
      orient: "horizontal",
      text: ["Hot", "Cold"],
      calculable: true,
      inRange: {
        color: ["#2E90FA", "#58A6FB", "#82BCFC", "#F3F9FD", "#FFC766", "#FFB433", "#FFA100"]
      },
      outOfRange: {
        color: [theme.noShots]
      },
      textStyle: {
        color: theme.mutedForeground,
        fontFamily: FONT_SANS
      }
    },
    series: [
      {
        name: "Shotchart",
        type: "map",
        map: MAP_NAME,
        selectedMode: false,
        roam: false,
        layoutCenter: ["50%", "46%"],
        layoutSize: "98%",
        itemStyle: {
          borderColor: "#fff",
          borderWidth: 3
        },
        emphasis: {
          label: {
            show: true,
            fontWeight: 700,
            fontFamily: FONT_SANS,
            color: "#fff"
          },
          itemStyle: {
            borderColor: "#fff",
            borderWidth: 4,
            areaColor: "#F92994"
          }
        },
        data: []
      }
    ]
  };
}

function init() {
  const root = document.getElementById("noah-workspace");
  if (!root) return;

  if (typeof root.__noahShotchartCleanup === "function") {
    root.__noahShotchartCleanup();
  }

  const chartHost = document.getElementById("noah-shotchart");
  const payloadContainer = document.getElementById("noah-shotchart-data");

  if (!chartHost || !payloadContainer) return;

  const echarts = window.echarts;
  if (!echarts) {
    console.warn("[noah-shotchart] ECharts not available on window.");
    return;
  }

  const chart = echarts.init(chartHost);

  const applyPayload = () => {
    const payload = parsePayload(payloadContainer);
    const theme = currentThemePalette();
    const seriesData = buildSeriesData(payload.zones, theme);

    chart.setOption({
      visualMap: {
        outOfRange: {
          color: [theme.noShots]
        }
      },
      series: [{ data: seriesData }]
    });
  };

  const resizeObserver = new ResizeObserver(() => chart.resize());
  resizeObserver.observe(chartHost);

  const payloadObserver = new MutationObserver(() => applyPayload());
  payloadObserver.observe(payloadContainer, { childList: true, subtree: true, characterData: true });

  const themeObserver = new MutationObserver((mutations) => {
    const classChanged = mutations.some((mutation) => mutation.type === "attributes" && mutation.attributeName === "class");
    if (!classChanged) return;
    if (!echarts.getMap(MAP_NAME)) return;

    chart.setOption(buildBaseOption(currentThemePalette()), true);
    applyPayload();
    chart.resize();
  });
  themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });

  fetch(SVG_URL)
    .then((response) => response.text())
    .then((svgText) => {
      echarts.registerMap(MAP_NAME, { svg: svgText });
      chart.setOption(buildBaseOption(currentThemePalette()), true);
      applyPayload();
      chart.resize();
    })
    .catch((error) => {
      console.error("[noah-shotchart] Failed to load shotchart.svg", error);
    });

  root.__noahShotchartCleanup = () => {
    resizeObserver.disconnect();
    payloadObserver.disconnect();
    themeObserver.disconnect();
    chart.dispose();
    delete root.__noahShotchartCleanup;
  };
}

window.__noahShotchartInit = init;

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}

window.addEventListener("pageshow", init);

export { init };
