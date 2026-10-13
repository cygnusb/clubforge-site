'use strict';
// Einladungsseite: der Parameter "host" wird streng als Hostname geprüft; alles, was vom
// Vereinsserver kommt (Manifest), wird nur als Text bzw. als geprüfte Farbe/https-Adresse verwendet.
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var LABEL = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

  function validHost(raw) {
    if (typeof raw !== 'string') return null;
    var h = raw.trim().toLowerCase();
    if (h.length < 4 || h.length > 253) return null;
    var labels = h.split('.');
    if (labels.length < 2) return null;
    for (var i = 0; i < labels.length; i++) if (!LABEL.test(labels[i])) return null;
    if (!/^[a-z]{2,63}$/.test(labels[labels.length - 1])) return null;
    return h;
  }

  function hexColor(v) { return typeof v === 'string' && /^#[0-9a-f]{6}$/i.test(v) ? v : null; }
  function inkFor(hex) {
    var n = parseInt(hex.slice(1), 16), r = n >> 16, g = (n >> 8) & 255, b = n & 255;
    return (0.299 * r + 0.587 * g + 0.114 * b) > 150 ? '#1b1714' : '#ffffff';
  }
  function httpsUrl(v) {
    try { var u = new URL(v); return u.protocol === 'https:' && !u.username && !u.password ? u.href : null; } catch (e) { return null; }
  }
  function text(v, max) { return typeof v === 'string' && v.trim() ? v.trim().slice(0, max) : null; }
  function show(id) { $(id).hidden = false; }

  var raw = new URLSearchParams(location.search).get('host');
  if (raw === null) return; // ohne host: nur die Erklärung

  var host = validHost(raw);
  if (!host) {
    $('intro').textContent = 'Dieser Einladungslink ist ungültig. Der Teil nach „host=“ muss ein Servername wie app.euer-verein.example sein, ohne https:// und ohne Pfad.';
    $('intro').className = 'err';
    return;
  }

  $('intro').textContent = 'Du wurdest in einen Verein eingeladen.';
  $('name').textContent = host;
  $('host').textContent = host;
  show('host');
  $('open-app').href = 'org.clubforge.app://join?host=' + encodeURIComponent(host);
  $('open-web').href = 'https://' + host + '/';
  show('open-app');
  show('open-web');
  $('note').textContent = 'Die App ist noch nicht in den Stores. Bis dahin: „Im Browser öffnen“ funktioniert auf jedem Gerät, auch als Verknüpfung auf dem Homescreen.';

  var ctl = new AbortController();
  var timer = setTimeout(function () { ctl.abort(); }, 6000);
  fetch('https://' + host + '/.well-known/clubforge.json', {
    credentials: 'omit', redirect: 'error', referrerPolicy: 'no-referrer', cache: 'no-store',
    headers: { Accept: 'application/json' }, signal: ctl.signal
  }).then(function (r) {
    if (!r.ok) throw new Error('status');
    return r.json();
  }).then(function (m) {
    clearTimeout(timer);
    var club = m && typeof m === 'object' && m.club && typeof m.club === 'object' ? m.club : {};
    var name = text(club.app_name, 80) || text(club.name, 80);
    if (name) {
      $('name').textContent = name;
      $('logo').textContent = name.charAt(0).toUpperCase();
    }
    var theme = m && m.theme && m.theme.light;
    var color = theme && hexColor(theme.primary);
    if (color) {
      var card = $('card').style;
      card.setProperty('--club', color);
      card.setProperty('--club-ink', inkFor(color));
    }
    var logo = httpsUrl(club.logo);
    if (logo) {
      var img = document.createElement('img');
      img.alt = '';
      img.referrerPolicy = 'no-referrer';
      img.onload = function () { $('logo').replaceWith(img); };
      img.src = logo;
    }
  }).catch(function () {
    clearTimeout(timer);
    // Manifest nicht erreichbar oder ohne CORS-Freigabe: Hostname genügt
  });
})();
