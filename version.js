// Zeigt die aktuelle Version (version.json, von scripts/set-version.sh und site/publish.sh aus VERSION geschrieben).
// Ohne Datei oder bei Fehler bleibt alles ohne Versionsangabe.
(function () {
  fetch('version.json', { cache: 'no-cache' })
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(function (v) {
      if (!v || !/^\d+\.\d+\.\d+$/.test(v.version)) return;
      document.querySelectorAll('[data-version]').forEach(function (el) { el.textContent = 'v' + v.version + ' '; });
      document.querySelectorAll('[data-version-line]').forEach(function (el) { el.hidden = false; });
    })
    .catch(function () {});
})();
