/* ============================================================
   nui.js — NUI bridge between the page and client/creator.lua
   Keeps the resource-name resolution + fetch wrapper in one place
   so app.js stays focused on rendering. Do not change the callback
   names below; they map 1:1 to RegisterNUICallback in creator.lua.
   ============================================================ */
(function () {
  // FiveM serves the page from https://cfx-nui-<resource>/web/index.html
  function resolveResource() {
    try {
      if (typeof GetParentResourceName === "function") return GetParentResourceName();
    } catch (e) {}
    var host = (location.hostname || "");
    if (host.indexOf("cfx-nui-") === 0) return host.slice("cfx-nui-".length);
    return "ParTay_airlines"; // resource folder fallback
  }

  var RESOURCE = resolveResource();
  var handlers = [];

  // POST to a RegisterNUICallback. Resolves with the cb() payload.
  function post(name, data) {
    if (window.__DEV__) {
      // Browser preview harness — never touch the network.
      if (window.__devPost) return Promise.resolve(window.__devPost(name, data) || {});
      return Promise.resolve({});
    }
    return fetch("https://" + RESOURCE + "/" + name, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(data || {})
    })
      .then(function (r) { return r.json().catch(function () { return {}; }); })
      .catch(function () { return {}; });
  }

  // Lua -> page messages (SendNUIMessage). Dispatch to every handler.
  window.addEventListener("message", function (ev) {
    var msg = ev.data;
    if (!msg || typeof msg !== "object") return;
    for (var i = 0; i < handlers.length; i++) {
      try { handlers[i](msg); } catch (e) { console.error("[aircreator]", e); }
    }
  });

  window.NUI = {
    resource: RESOURCE,
    post: post,
    onMessage: function (fn) { handlers.push(fn); }
  };
})();
