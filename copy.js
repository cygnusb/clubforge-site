// Kopier-Knopf für jeden Befehlsblock (pre). Kommentare (span.c) kommen nicht mit, damit sich die Zeilen direkt ins
// Terminal einfügen lassen. Ohne Skript bleiben die Blöcke normal markierbar.
(function () {
  var en = document.documentElement.lang === 'en';
  var LABEL = en ? 'Copy' : 'Kopieren';
  var DONE = en ? 'Copied' : 'Kopiert';
  var FAIL = en ? 'Select and copy' : 'Markieren und kopieren';

  function text(pre) {
    var clone = pre.cloneNode(true);
    clone.querySelectorAll('.c').forEach(function (c) { c.remove(); });
    var lines = clone.textContent.split('\n').map(function (l) { return l.replace(/\s+$/, ''); });
    // Zeilen, die nur aus einem Kommentar bestanden, fallen weg; gewollte Leerzeilen bleiben
    var src = pre.textContent.split('\n');
    lines = lines.filter(function (l, i) { return l !== '' || src[i].trim() === ''; });
    return lines.join('\n').replace(/^\n+|\n+$/g, '') + '\n';
  }

  function copy(value) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(value);
    return new Promise(function (resolve, reject) {
      var ta = document.createElement('textarea');
      ta.value = value;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      ta.remove();
      ok ? resolve() : reject();
    });
  }

  function init() {
    document.querySelectorAll('pre').forEach(function (pre) {
      var box = document.createElement('div');
      box.className = 'code';
      pre.parentNode.insertBefore(box, pre);
      box.appendChild(pre);
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'copy';
      btn.textContent = LABEL;
      btn.setAttribute('aria-live', 'polite');
      var timer;
      btn.addEventListener('click', function () {
        copy(text(pre)).then(function () { btn.textContent = DONE; }, function () { btn.textContent = FAIL; })
          .then(function () {
            clearTimeout(timer);
            timer = setTimeout(function () { btn.textContent = LABEL; }, 2000);
          });
      });
      box.appendChild(btn);
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
