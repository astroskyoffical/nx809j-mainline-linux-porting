(() => {
  "use strict";

  const GROUPS = [
    "Boot & recovery",
    "Platform",
    "Display & input",
    "Graphics",
    "Radio & network",
    "Audio & cameras",
    "Sensors & power",
    "Desktop",
  ];
  const VIEWS = {
    overview: { label: "Overview", kinds: new Set(["evidence", "module"]) },
    evidence: { label: "Decoded evidence", kinds: new Set(["evidence"]) },
    module: { label: "Driver files", kinds: new Set(["module"]) },
    hardware: { label: "Phone tests", kinds: new Set(["hardware"]) },
  };
  const TYPE_LABELS = { evidence: "Decoded evidence", module: "Driver file", hardware: "Phone-test scope" };
  const BACKUP_STATES = {
    active: "In progress (reported)",
    running: "In progress (reported)",
    collecting: "In progress (reported)",
    paused: "Paused",
    complete: "Capture finished — review",
    completed: "Capture finished — review",
    none: "No capture recorded",
    stopped: "Stopped — review",
    "captured-with-gaps": "Capture needs review",
    "archives-verified-restore-unproven": "Archives verified; restore untested",
    error: "Needs attention",
    failed: "Needs attention",
    blocked: "Blocked",
    idle: "Not active",
    waiting: "Waiting",
  };

  const $ = (selector) => document.querySelector(selector);
  const groupBoard = $("#group-board");
  const emptyState = $("#empty-state");
  const noticeArea = $("#notice-area");
  const searchInput = $("#search-input");
  const namesToggle = $("#names-toggle");
  const viewTabs = [...document.querySelectorAll(".view-tab")];
  const filterButtons = [...document.querySelectorAll(".filter-button")];
  const markers = new Map();

  let items = [];
  let selectedKey = null;
  let view = "overview";
  let stateFilter = "all";
  let hasSnapshot = false;
  let refreshing = false;
  let lastReceivedAt = null;

  function stringValue(value, fallback = "") {
    return typeof value === "string" ? value : fallback;
  }

  function normalizedArray(value) {
    return Array.isArray(value) ? value : [];
  }

  function normalizeItem(raw, index) {
    const item = raw && typeof raw === "object" ? raw : {};
    const id = stringValue(item.id, `scope-${index + 1}`);
    const kind = stringValue(item.kind, "evidence").toLowerCase();
    const group = stringValue(item.group, "Unmapped");
    const evidence = normalizedArray(item.evidence).map((entry) => {
      const source = entry && typeof entry === "object" ? entry : {};
      return {
        path: stringValue(source.path, "Path not supplied"),
        note: stringValue(source.note),
        hashOk: source.hash_ok === true ? true : source.hash_ok === false ? false : null,
      };
    });
    return {
      key: `${id}#${index}`,
      id,
      kind,
      group,
      label: stringValue(item.label, "Unnamed scope"),
      scope: stringValue(item.scope, "No scope statement supplied."),
      state: item.state === "ready" ? "ready" : "pending",
      reason: stringValue(item.reason, "No status reason supplied."),
      blockers: normalizedArray(item.blockers).filter((entry) => typeof entry === "string"),
      evidence,
    };
  }

  function setText(selector, value) {
    $(selector).textContent = value;
  }

  function createElement(tag, className, text) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text !== undefined) element.textContent = text;
    return element;
  }

  function currentItems() {
    const query = searchInput.value.trim().toLocaleLowerCase();
    const kindSet = VIEWS[view].kinds;
    return items.filter((item) => {
      if (!kindSet.has(item.kind)) return false;
      if (stateFilter !== "all" && item.state !== stateFilter) return false;
      if (!query) return true;
      const searchable = [
        item.label,
        item.scope,
        item.reason,
        item.group,
        ...item.blockers,
        ...item.evidence.flatMap((entry) => [entry.path, entry.note]),
      ].join(" ").toLocaleLowerCase();
      return searchable.includes(query);
    });
  }

  function setSelected(item, shouldFocus = false) {
    selectedKey = item ? item.key : null;
    renderBoard();
    renderInspector(item || null);
    if (shouldFocus && item) {
      const button = markers.get(item.key);
      if (button) button.focus();
    }
  }

  function markerAccessibleName(item) {
    const stateLabel = item.state === "ready" ? "verified stated scope" : "open or unresolved";
    return `${item.label}. ${item.group}. ${stateLabel}. ${item.scope}`;
  }

  function renderBoard() {
    const visibleItems = currentItems();
    const knownGroups = new Set(GROUPS);
    const groupsToShow = GROUPS.map((name) => [name, visibleItems.filter((item) => item.group === name)]);
    const unmapped = visibleItems.filter((item) => !knownGroups.has(item.group));
    if (unmapped.length) groupsToShow.push(["Unmapped scopes", unmapped]);

    markers.clear();
    groupBoard.replaceChildren();
    emptyState.hidden = visibleItems.length !== 0;
    $("#empty-message").textContent = hasSnapshot
      ? "Try another view, change the filter, or clear the search."
      : "The local inventory has not returned any scopes yet.";

    for (const [groupName, groupItems] of groupsToShow) {
      const section = createElement("section", "group-card");
      section.setAttribute("aria-label", `${groupName}: ${groupItems.length} visible scopes`);
      const heading = createElement("div", "group-heading");
      const title = createElement("h2", "group-title", groupName);
      const count = createElement("span", "group-count", String(groupItems.length));
      heading.append(title, count);
      section.append(heading);

      if (groupItems.length) {
        const cluster = createElement("div", "marker-cluster");
        for (const item of groupItems) {
          const button = createElement("button", `scope-marker ${item.state === "ready" ? "is-ready" : "is-pending"}`);
          button.type = "button";
          button.tabIndex = item.key === selectedKey ? 0 : -1;
          button.setAttribute("aria-label", markerAccessibleName(item));
          button.setAttribute("aria-pressed", item.key === selectedKey ? "true" : "false");
          button.dataset.itemKey = item.key;
          const glyph = createElement("span", "marker-glyph", item.state === "ready" ? "✓" : "–");
          glyph.setAttribute("aria-hidden", "true");
          const name = createElement("span", "marker-name", item.label);
          name.setAttribute("aria-hidden", "true");
          button.append(glyph, name);
          button.addEventListener("click", () => setSelected(item));
          button.addEventListener("keydown", onMarkerKeydown);
          cluster.append(button);
          markers.set(item.key, button);
        }
        section.append(cluster);
      } else {
        section.append(createElement("p", "group-empty", "No matching scopes"));
      }
      groupBoard.append(section);
    }

    groupBoard.classList.toggle("show-names", namesToggle.checked);
  }

  function renderInspector(item) {
    const inspector = $("#inspector");
    const content = $("#inspector-content");
    const statePill = $("#inspector-state");
    if (!item) {
      inspector.classList.remove("has-selection");
      statePill.className = "state-pill state-empty";
      statePill.textContent = "No selection";
      $("#inspector-title").textContent = "Select a marker";
      $("#inspector-hint").hidden = false;
      content.hidden = true;
      return;
    }

    inspector.classList.add("has-selection");
    statePill.className = `state-pill ${item.state === "ready" ? "state-ready" : "state-pending"}`;
    statePill.textContent = item.state === "ready" ? "Verified · stated scope" : "Needs work";
    $("#inspector-title").textContent = item.label;
    $("#inspector-hint").hidden = true;
    content.hidden = false;
    $("#detail-meta").textContent = `${item.group} · ${TYPE_LABELS[item.kind] || "Inventory scope"}`;
    $("#detail-scope").textContent = item.scope;
    $("#detail-reason").textContent = item.reason;

    const blockersField = $("#blockers-field");
    const blockersList = $("#detail-blockers");
    blockersList.replaceChildren();
    blockersField.hidden = item.blockers.length === 0;
    for (const blocker of item.blockers) blockersList.append(createElement("li", "", blocker));

    const evidenceList = $("#detail-evidence");
    evidenceList.replaceChildren();
    if (item.evidence.length === 0) {
      evidenceList.append(createElement("li", "evidence-empty", "No evidence paths listed."));
    }
    for (const entry of item.evidence) {
      const listItem = createElement("li", "evidence-entry");
      const path = createElement("code", "evidence-path", entry.path);
      const hashState = entry.hashOk === true
        ? "SHA-256 verified"
        : entry.hashOk === false
          ? "SHA-256 mismatch"
          : "SHA-256 status unavailable";
      const hash = createElement("span", `hash-state ${entry.hashOk === true ? "hash-ok" : entry.hashOk === false ? "hash-bad" : "hash-unknown"}`, hashState);
      listItem.append(path, hash);
      if (entry.note) listItem.append(createElement("p", "evidence-note", entry.note));
      evidenceList.append(listItem);
    }
  }

  function onMarkerKeydown(event) {
    const navKeys = ["ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp", "Home", "End"];
    if (!navKeys.includes(event.key)) return;
    const visibleItems = currentItems();
    if (!visibleItems.length) return;
    const activeKey = event.currentTarget.dataset.itemKey;
    let index = Math.max(0, visibleItems.findIndex((item) => item.key === activeKey));
    if (event.key === "Home") index = 0;
    else if (event.key === "End") index = visibleItems.length - 1;
    else if (event.key === "ArrowRight" || event.key === "ArrowDown") index = (index + 1) % visibleItems.length;
    else index = (index - 1 + visibleItems.length) % visibleItems.length;
    event.preventDefault();
    setSelected(visibleItems[index], true);
  }

  function updateTabs(nextView, focusTab = false) {
    view = nextView;
    const activeTab = viewTabs.find((tab) => tab.dataset.view === view);
    for (const tab of viewTabs) {
      const active = tab === activeTab;
      tab.setAttribute("aria-selected", active ? "true" : "false");
      tab.tabIndex = active ? 0 : -1;
    }
    $("#atlas-panel").setAttribute("aria-labelledby", activeTab.id);
    if (focusTab) activeTab.focus();
    keepSelectionVisible();
  }

  function keepSelectionVisible() {
    const visibleItems = currentItems();
    const selected = visibleItems.find((item) => item.key === selectedKey);
    setSelected(selected || visibleItems[0] || null);
  }

  function updateFilters(nextFilter) {
    stateFilter = nextFilter;
    for (const button of filterButtons) {
      button.setAttribute("aria-pressed", button.dataset.filter === stateFilter ? "true" : "false");
    }
    keepSelectionVisible();
  }

  function formatDate(value) {
    if (typeof value !== "string" || !value) return "time unavailable";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "time unavailable";
    return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date);
  }

  function formatCount(value) {
    return Number.isSafeInteger(value) && value >= 0 ? new Intl.NumberFormat().format(value) : "—";
  }

  function formatBytes(value) {
    if (!Number.isSafeInteger(value) || value < 0) return "—";
    if (value < 1024) return `${value} B`;
    const units = ["KB", "MB", "GB", "TB"];
    let amount = value;
    let unit = "B";
    for (const candidate of units) {
      amount /= 1024;
      unit = candidate;
      if (amount < 1024 || candidate === "TB") break;
    }
    return `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(amount)} ${unit}`;
  }

  function renderBackup(backup) {
    const data = backup && typeof backup === "object" ? backup : {};
    const rawState = stringValue(data.state).toLowerCase();
    setText("#backup-state", BACKUP_STATES[rawState] || (rawState ? "Reported state unavailable" : "Not reported"));

    const batch = typeof data.current_batch === "number"
      ? (Number.isSafeInteger(data.current_batch) && data.current_batch >= 0 ? String(data.current_batch) : "")
      : stringValue(data.current_batch);
    const safeBatch = /^\d+(?:\s*\/\s*\d+)?$/.test(batch) ? `Batch ${batch.replace(/\s+/g, "")}` : "—";
    setText("#backup-batch", safeBatch);
    setText("#backup-verified", formatCount(data.verified_batches));
    setText("#backup-bytes", formatBytes(data.active_output_bytes));
  }

  function renderNotices(errors, fetchError = "") {
    noticeArea.replaceChildren();
    const messages = [];
    if (fetchError) messages.push(`Local inventory refresh failed: ${fetchError}`);
    for (const error of normalizedArray(errors)) {
      if (typeof error === "string" && error.trim()) messages.push(error.trim());
      else if (error && typeof error === "object" && typeof error.message === "string") messages.push(error.message);
    }
    if (!messages.length) {
      noticeArea.hidden = true;
      return;
    }
    noticeArea.hidden = false;
    noticeArea.setAttribute("role", fetchError ? "alert" : "status");
    const title = createElement("strong", "notice-title", fetchError ? "Inventory is stale" : "Inventory warnings");
    const list = createElement("ul", "notice-list");
    for (const message of messages.slice(0, 4)) list.append(createElement("li", "", message));
    if (messages.length > 4) list.append(createElement("li", "", `${messages.length - 4} additional warning(s) not shown.`));
    noticeArea.append(title, list);
  }

  function renderSummary() {
    const ready = items.filter((item) => item.state === "ready").length;
    const pending = items.length - ready;
    const hardwareItems = items.filter((item) => item.kind === "hardware");
    const hardwarePassed = hardwareItems.filter((item) => item.state === "ready").length;
    setText("#ready-count", formatCount(ready));
    setText("#pending-count", formatCount(pending));
    setText("#hardware-count", `${formatCount(hardwarePassed)} / ${formatCount(hardwareItems.length)}`);
  }

  function renderSnapshot(payload) {
    const source = payload && typeof payload === "object" ? payload : {};
    items = normalizedArray(source.items).map(normalizeItem);
    hasSnapshot = true;
    lastReceivedAt = new Date();
    const generated = formatDate(source.generated_at);
    $("#last-refresh").textContent = `Received ${formatDate(lastReceivedAt.toISOString())} · data generated ${generated}`;
    const inventoryNote = stringValue(source.inventory_note);
    const noteElement = $("#inventory-note");
    noteElement.textContent = inventoryNote;
    noteElement.hidden = !inventoryNote;
    renderBackup(source.backup);
    renderSummary();
    renderNotices(source.errors);
    setConnection("current", "Local inventory connected");
    keepSelectionVisible();
  }

  function setConnection(state, text) {
    const dot = $("#connection-dot");
    dot.className = `connection-dot connection-${state}`;
    setText("#connection-label", text);
  }

  async function refresh() {
    if (refreshing) return;
    refreshing = true;
    if (!hasSnapshot) setConnection("loading", "Connecting to local inventory…");
    try {
      const response = await fetch("/api/state", { cache: "no-store", headers: { Accept: "application/json" } });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const payload = await response.json();
      renderSnapshot(payload);
    } catch (error) {
      const reason = error instanceof Error ? error.message : "request failed";
      setConnection("stale", hasSnapshot ? "Showing last saved inventory · stale" : "Local inventory unavailable");
      const received = lastReceivedAt ? formatDate(lastReceivedAt.toISOString()) : "none yet";
      setText("#last-refresh", `Last successful refresh: ${received}`);
      renderNotices([], reason);
    } finally {
      refreshing = false;
    }
  }

  viewTabs.forEach((tab, index) => {
    tab.addEventListener("click", () => updateTabs(tab.dataset.view));
    tab.addEventListener("keydown", (event) => {
      if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      let next = index;
      if (event.key === "Home") next = 0;
      else if (event.key === "End") next = viewTabs.length - 1;
      else if (event.key === "ArrowRight") next = (index + 1) % viewTabs.length;
      else next = (index - 1 + viewTabs.length) % viewTabs.length;
      updateTabs(viewTabs[next].dataset.view, true);
    });
  });

  filterButtons.forEach((button) => button.addEventListener("click", () => updateFilters(button.dataset.filter)));
  searchInput.addEventListener("input", keepSelectionVisible);
  namesToggle.addEventListener("change", () => groupBoard.classList.toggle("show-names", namesToggle.checked));

  document.addEventListener("keydown", (event) => {
    const target = event.target;
    const typing = target instanceof HTMLElement && (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName));
    if (event.key === "/" && !typing && !event.ctrlKey && !event.metaKey && !event.altKey) {
      event.preventDefault();
      searchInput.focus();
    } else if (event.key === "Escape" && target === searchInput && searchInput.value) {
      searchInput.value = "";
      keepSelectionVisible();
    }
  });

  updateTabs("overview");
  refresh();
  window.setInterval(refresh, 30_000);
})();
