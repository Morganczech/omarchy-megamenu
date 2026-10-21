const api = globalThis.browser || globalThis.chrome;
const HOST = "gruut.megamenu";

const t = {
  eyebrow: "Save to Megamenu",
  space: "Space",
  category: "Category",
  save: "Save page",
  saving: "Saving…",
  saved: "Saved to {space} / {category}",
  duplicate: "Already in {space}",
  noPage: "This page has no address to save.",
  badUrl: "Only http and https pages can be saved.",
  noData: "Open Megamenu once, then try again.",
  badSpace: "That space is no longer available. Reopen this popup.",
  badCategory: "Pick a category from the selected space.",
  disconnected: "Browser host is not installed. Run scripts/install-browser-host.py from the Megamenu plugin.",
  failed: "Could not reach Megamenu.",
  empty: "No spaces yet."
};

const titleEl = document.getElementById("page-title");
const urlEl = document.getElementById("page-url");
const spaceEl = document.getElementById("space");
const categoryEl = document.getElementById("category");
const saveEl = document.getElementById("save");
const statusEl = document.getElementById("status");
const formEl = document.getElementById("save-form");

document.documentElement.lang = "en";
document.getElementById("eyebrow").textContent = t.eyebrow;
document.querySelector('label[for="space"]').textContent = t.space;
document.querySelector('label[for="category"]').textContent = t.category;
saveEl.textContent = t.save;

let port = null;
const pending = [];
let spaces = [];
let pageUrl = "";
let pageTitle = "";

function setStatus(text, kind) {
  statusEl.textContent = text || "";
  statusEl.className = "status" + (kind ? " " + kind : "");
}

function fill(template, values) {
  return template.replace(/\{(\w+)\}/g, function(_, key) {
    return values[key] || "";
  });
}

function storageGet(keys) {
  return new Promise(function(resolve) {
    api.storage.local.get(keys, resolve);
  });
}

function storageSet(values) {
  return new Promise(function(resolve) {
    api.storage.local.set(values, resolve);
  });
}

function currentTab() {
  return new Promise(function(resolve) {
    api.tabs.query({ active: true, currentWindow: true }, function(tabs) {
      resolve(tabs && tabs[0] ? tabs[0] : null);
    });
  });
}

function connect() {
  port = api.runtime.connectNative(HOST);
  port.onMessage.addListener(function(message) {
    const waiter = pending.shift();
    if (waiter) waiter.resolve(message);
  });
  port.onDisconnect.addListener(function() {
    const message = (api.runtime.lastError && api.runtime.lastError.message) || "";
    const err = new Error(message || "disconnected");
    err.code = "disconnected";
    while (pending.length) pending.shift().reject(err);
    port = null;
  });
}

function send(message) {
  if (!port) connect();
  return new Promise(function(resolve, reject) {
    pending.push({ resolve: resolve, reject: reject });
    try {
      port.postMessage(message);
    } catch (err) {
      pending.pop();
      reject(err);
    }
  });
}

function categoriesFor(spaceId) {
  const space = spaces.find(function(item) { return item.id === spaceId; });
  return space && space.categories ? space.categories : [];
}

function renderCategories(preferredId) {
  const categories = categoriesFor(spaceEl.value);
  categoryEl.innerHTML = "";
  categories.forEach(function(category) {
    const option = document.createElement("option");
    option.value = category.id;
    option.textContent = category.name;
    categoryEl.appendChild(option);
  });
  if (preferredId && categories.some(function(category) { return category.id === preferredId; })) {
    categoryEl.value = preferredId;
  }
  categoryEl.disabled = categories.length === 0;
}

function renderSpaces(preferredSpaceId, preferredCategoryId) {
  spaceEl.innerHTML = "";
  spaces.forEach(function(space) {
    const option = document.createElement("option");
    option.value = space.id;
    option.textContent = space.name;
    spaceEl.appendChild(option);
  });
  const known = spaces.some(function(space) { return space.id === preferredSpaceId; });
  const reading = spaces.find(function(space) { return space.reading; });
  spaceEl.value = known ? preferredSpaceId : (reading ? reading.id : (spaces[0] ? spaces[0].id : ""));
  renderCategories(preferredCategoryId);
}

function canSave() {
  return /^https?:\/\//i.test(pageUrl) && spaces.length > 0;
}

function explainPage() {
  if (!pageUrl) {
    setStatus(t.noPage, "err");
    return;
  }
  if (!/^https?:\/\//i.test(pageUrl)) {
    setStatus(t.badUrl, "err");
  }
}

function failureText(error) {
  const code = error && (error.error || error.code);
  if (code === "no-data") return t.noData;
  if (code === "bad-url") return t.badUrl;
  if (code === "bad-space") return t.badSpace;
  if (code === "bad-category") return t.badCategory;
  if (code === "disconnected") return t.disconnected;
  return t.failed;
}

spaceEl.addEventListener("change", function() {
  renderCategories("");
  storageSet({ lastSpaceId: spaceEl.value, lastCategoryId: categoryEl.value });
});

categoryEl.addEventListener("change", function() {
  storageSet({ lastSpaceId: spaceEl.value, lastCategoryId: categoryEl.value });
});

formEl.addEventListener("submit", function(event) {
  event.preventDefault();
  if (!canSave()) {
    explainPage();
    return;
  }
  saveEl.disabled = true;
  saveEl.textContent = t.saving;
  setStatus("");
  send({
    action: "save",
    url: pageUrl,
    title: pageTitle,
    spaceId: spaceEl.value,
    categoryId: categoryEl.value
  }).then(function(result) {
    if (!result || result.ok === false) {
      setStatus(failureText(result), "err");
      return;
    }
    storageSet({ lastSpaceId: spaceEl.value, lastCategoryId: categoryEl.value });
    if (result.status === "duplicate") {
      setStatus(fill(t.duplicate, { space: result.spaceName }), "ok");
    } else {
      setStatus(fill(t.saved, {
        space: result.spaceName,
        category: result.categoryName
      }), "ok");
    }
  }).catch(function(error) {
    setStatus(failureText(error), "err");
  }).then(function() {
    saveEl.disabled = !canSave();
    saveEl.textContent = t.save;
  });
});

Promise.all([
  currentTab(),
  storageGet(["lastSpaceId", "lastCategoryId"])
]).then(function(results) {
  const tab = results[0];
  const stored = results[1] || {};
  pageUrl = (tab && tab.url) || "";
  pageTitle = (tab && tab.title) || pageUrl;
  titleEl.textContent = pageTitle || t.noPage;
  urlEl.textContent = pageUrl;
  explainPage();
  return send({ action: "list" }).then(function(result) {
    if (!result || result.ok === false) {
      setStatus(failureText(result), "err");
      saveEl.disabled = true;
      return;
    }
    spaces = result.spaces || [];
    if (!spaces.length) {
      setStatus(t.empty, "err");
      saveEl.disabled = true;
      return;
    }
    renderSpaces(stored.lastSpaceId, stored.lastCategoryId);
    saveEl.disabled = !canSave();
  });
}).catch(function(error) {
  titleEl.textContent = pageTitle || t.failed;
  setStatus(failureText(error), "err");
  saveEl.disabled = true;
});
