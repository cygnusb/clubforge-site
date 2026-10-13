// Zentrale Stelle für den Quellcode-Link. Solange REPO_URL leer ist (Repository noch privat),
// bleiben alle Elemente mit data-repo reine Texte ohne Link. Zum Einschalten die Adresse eintragen,
// z. B. 'https://github.com/cygnusb/clubforge'; das Skript macht daraus Links mit dem Text aus data-label.
(function () {
  var REPO_URL = '';
  if (!REPO_URL) return;
  document.querySelectorAll('[data-repo]').forEach(function (el) {
    var a = document.createElement('a');
    a.className = el.className.replace(/\boff\b/, '').trim();
    a.href = REPO_URL + el.getAttribute('data-repo');
    a.textContent = el.getAttribute('data-label') || el.textContent;
    a.hidden = false;
    el.replaceWith(a);
  });
})();
