const MAP_NAME = "NoahShotchartSvg";
const SVG_URL = "/shotchart.svg";

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

function zoneToSeriesDatum(zone) {
  const attempts = Number(zone?.attempts || 0);
  const made = Number(zone?.made || 0);
  const fgPct = attempts > 0 ? (made / attempts) * 100 : 0;

  return {
    name: String(zone?.name || "unassigned"),
    value: Math.round(fgPct * 10) / 10,
    attempts,
    made
  };
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

function buildBaseOption() {
  return {
    backgroundColor: "transparent",
    animationDuration: 250,
    tooltip: {
      trigger: "item",
      formatter(params) {
        if (!params?.data) return params?.name || "";

        const datum = params.data;
        return `
          <div style="min-width:130px;">
            <div style="font-weight:600; margin-bottom:4px;">${formatZoneLabel(datum.name)}</div>
            <div>FG%: ${Number(datum.value || 0).toFixed(1)}%</div>
            <div>Made: ${datum.made || 0} / ${datum.attempts || 0}</div>
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
      textStyle: {
        color: "inherit"
      }
    },
    series: [
      {
        name: "Shotchart",
        type: "map",
        map: MAP_NAME,
        selectedMode: "single",
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
            color: "#fff"
          },
          itemStyle: {
            borderColor: "#fff",
            borderWidth: 4,
            areaColor: "#F92994"
          }
        },
        select: {
          label: {
            show: true,
            color: "#fff"
          },
          itemStyle: {
            areaColor: "#F92994",
            borderColor: "#fff",
            borderWidth: 4
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
  let zonesByName = new Map();
  let selectedZone = "";

  const sendEvent = (name, detail = {}) => {
    chartHost.dispatchEvent(new CustomEvent(name, { bubbles: true, detail }));
  };

  const applyPayload = () => {
    const payload = parsePayload(payloadContainer);
    const seriesData = payload.zones.map(zoneToSeriesDatum);

    zonesByName = new Map(seriesData.map((zone) => [zone.name, zone]));

    if (selectedZone && !zonesByName.has(selectedZone)) {
      selectedZone = "";
      sendEvent("noah-zone-clear", {});
    }

    chart.setOption({ series: [{ data: seriesData }] });

    if (selectedZone) {
      chart.dispatchAction({ type: "select", seriesIndex: 0, name: selectedZone });
    }
  };

  const resizeObserver = new ResizeObserver(() => chart.resize());
  resizeObserver.observe(chartHost);

  const payloadObserver = new MutationObserver(() => applyPayload());
  payloadObserver.observe(payloadContainer, { childList: true, subtree: true, characterData: true });

  chart.on("mouseover", { seriesIndex: 0 }, (event) => {
    if (!event?.name) return;
    sendEvent("noah-zone-hover", { zone: event.name });
  });

  chart.on("mouseout", { seriesIndex: 0 }, () => {
    sendEvent("noah-zone-hover", { zone: "" });
  });

  chart.on("click", { seriesIndex: 0 }, (event) => {
    if (!event?.name) return;

    if (selectedZone === event.name) {
      chart.dispatchAction({ type: "unselect", seriesIndex: 0, name: selectedZone });
      selectedZone = "";
      sendEvent("noah-zone-clear", {});
      return;
    }

    if (selectedZone) {
      chart.dispatchAction({ type: "unselect", seriesIndex: 0, name: selectedZone });
    }

    selectedZone = event.name;
    chart.dispatchAction({ type: "select", seriesIndex: 0, name: selectedZone });

    const selectedData = zonesByName.get(selectedZone);
    sendEvent("noah-zone-select", {
      zone: selectedZone,
      attempts: selectedData?.attempts ?? 0,
      made: selectedData?.made ?? 0,
      fgpct: selectedData?.value ?? 0
    });
  });

  const onZoneClear = () => {
    if (!selectedZone) return;
    chart.dispatchAction({ type: "unselect", seriesIndex: 0, name: selectedZone });
    selectedZone = "";
  };

  root.addEventListener("noah-zone-clear", onZoneClear);

  fetch(SVG_URL)
    .then((response) => response.text())
    .then((svgText) => {
      echarts.registerMap(MAP_NAME, { svg: svgText });
      chart.setOption(buildBaseOption(), true);
      applyPayload();
      chart.resize();
    })
    .catch((error) => {
      console.error("[noah-shotchart] Failed to load shotchart.svg", error);
    });

  root.__noahShotchartCleanup = () => {
    root.removeEventListener("noah-zone-clear", onZoneClear);
    resizeObserver.disconnect();
    payloadObserver.disconnect();
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
