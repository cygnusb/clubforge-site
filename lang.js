/* Sprache der Projektseite.
   Ohne gespeicherte Wahl zählt die Browsersprache (en → Englisch, de → Deutsch,
   sonst die aufgerufene Seite). DE/EN merkt sich die Wahl nur auf dem Gerät
   (localStorage), es wird kein Cookie gesetzt. Suchmaschinen bleiben auf der
   aufgerufenen Adresse, damit beide Sprachen auffindbar bleiben. */
(function () {
  var KEY = "cf-site-lang";
  var FROM = "cf-site-from";

  function preferred(saved, languages) {
    if (saved === "de" || saved === "en") return saved;
    var list = languages && languages.length ? languages : [];
    for (var i = 0; i < list.length; i++) {
      var two = String(list[i] || "").toLowerCase().slice(0, 2);
      if (two === "en" || two === "de") return two;
    }
    return null;
  }

  function isBot(ua) {
    return /googlebot|bingbot|baiduspider|yandexbot|duckduckbot|slurp|facebookexternalhit|twitterbot|linkedinbot|embedly|whatsapp|telegrambot|slackbot|discordbot|applebot|semrushbot|ahrefsbot|petalbot|bytespider|gptbot|claudebot|amazonbot|ia_archiver/i.test(ua || "");
  }

  // base ist das Verzeichnis von lang.js, also /clubforge-site/ oder / bei lokalem Aufruf.
  function swapPath(base, pathname, want) {
    if (!base) return null;
    if (base.slice(-1) !== "/") base += "/";
    if (pathname.indexOf(base) !== 0) return null;
    var rest = pathname.slice(base.length);
    var onEn = rest === "en" || rest.indexOf("en/") === 0;
    var stripped = onEn ? rest.replace(/^en\/?/, "") : rest;
    if (want === "en") return onEn ? null : base + "en/" + stripped;
    if (want === "de") return onEn ? base + stripped : null;
    return null;
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { preferred: preferred, isBot: isBot, swapPath: swapPath };
    return;
  }

  function remember(e) {
    var node = e.target;
    if (!node || !node.closest) return;
    var a = node.closest(".lang a[hreflang]");
    if (!a) return;
    var lang = a.getAttribute("hreflang");
    if (lang !== "de" && lang !== "en") return;
    try { localStorage.setItem(KEY, lang); } catch (err) {}
  }
  document.addEventListener("mousedown", remember, true);
  document.addEventListener("click", remember, true);

  var origin = null;
  try {
    origin = sessionStorage.getItem(FROM);
    sessionStorage.removeItem(FROM);
  } catch (err) {}

  if (isBot(navigator.userAgent)) return;
  var here = document.documentElement.lang === "en" ? "en" : "de";
  var saved = null;
  try { saved = localStorage.getItem(KEY); } catch (err) {}
  var langs = navigator.languages;
  if (!langs || !langs.length) langs = [navigator.language || ""];
  var want = preferred(saved, langs);
  if (!want || want === here) return;

  var target = null;
  if (document.querySelector('meta[name="robots"][content="noindex"]')) {
    var link = document.querySelector('link[rel="alternate"][hreflang="' + want + '"]');
    if (!link) return;
    target = new URL(link.getAttribute("href"), location.href).pathname;
  } else {
    var src = document.currentScript && document.currentScript.src;
    if (!src) return;
    var path = swapPath(new URL("./", src).pathname, location.pathname, want);
    if (!path) return;
    target = path + location.search + location.hash;
  }

  var current = location.pathname + location.search + location.hash;
  if (!target || target === current) return;
  if (origin && origin === target) return;
  try { sessionStorage.setItem(FROM, current); } catch (err) {}
  location.replace(target);
})();
