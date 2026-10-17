// Einrichtungs-Assistent: stellt aus dem Formular den Installationsaufruf, die cloud-init-Datei für die Hetzner-Konsole
// oder die terraform.tfvars zusammen. Alles bleibt im Browser; Passwörter fragt der Assistent nie ab (sie werden auf dem
// Server verdeckt eingegeben). Die Prüfungen entsprechen deploy/gen-env.sh und deploy/branding.sh, zusätzlich ohne `,
// weil die Werte in cloud-init in doppelten Anführungszeichen einer Shell landen.
(function () {
  var en = document.documentElement.lang === 'en';
  var T = en ? {
    missing: 'Still missing or invalid:',
    required: 'required',
    host: 'lowercase letters, digits, dot and hyphen, without https://',
    distinct: 'app, sync and sign-in need three different names',
    email: 'not a valid email address',
    text: 'without " $ \\ `',
    textTofu: 'without \' " $ \\ ` (OpenTofu template)',
    s3Tofu: 'letters, digits, . _ - (OpenTofu template)',
    httpsOnly: 'https:// only (OpenTofu template)',
    version: 'form x.y.z, e.g. 0.2.1',
    logo: 'https address ending in .svg, .png, .webp or .jpg',
    color: 'color of the form #rrggbb',
    both: 'first and last name belong together',
    port: 'a number, usually 587',
    s3: 'letters, digits, . _ - /',
    s3endpoint: 'form https://name.example.org',
    s3need: 'bucket and access key are needed with an endpoint',
    age: 'form age1… (62 characters, from age-keygen)',
    sshkey: 'a public key such as ssh-ed25519 AAAA… name@computer',
    cidr: 'addresses with prefix, e.g. 203.0.113.7/32',
    smtppw: 'SMTP password: ',
    s3pw: 'S3 secret key: ',
    cloudinitErr: 'The cloud-init template could not be loaded. It is at /cloud-init.yaml on this website; reload the page and try again.',
    pwPlaceholder: '…your password…',
    keyPlaceholder: '…secret key…'
  } : {
    missing: 'Noch offen oder ungültig:',
    required: 'fehlt',
    host: 'Kleinbuchstaben, Ziffern, Punkt und Bindestrich, ohne https://',
    distinct: 'App, Synchronisation und Anmeldung brauchen drei verschiedene Namen',
    email: 'keine gültige E-Mail-Adresse',
    text: 'ohne " $ \\ `',
    textTofu: 'ohne \' " $ \\ ` (OpenTofu-Vorlage)',
    s3Tofu: 'Buchstaben, Ziffern, . _ - (OpenTofu-Vorlage)',
    httpsOnly: 'nur https:// (OpenTofu-Vorlage)',
    version: 'Form x.y.z, z. B. 0.2.1',
    logo: 'https-Adresse auf .svg, .png, .webp oder .jpg',
    color: 'Farbe der Form #rrggbb',
    both: 'Vor- und Nachname gehören zusammen',
    port: 'eine Zahl, meist 587',
    s3: 'Buchstaben, Ziffern, . _ - /',
    s3endpoint: 'Form https://name.example.org',
    s3need: 'mit Endpunkt sind Bucket und Access Key nötig',
    age: 'Form age1… (62 Zeichen, aus age-keygen)',
    sshkey: 'ein öffentlicher Schlüssel wie ssh-ed25519 AAAA… name@rechner',
    cidr: 'Adressen mit Präfix, z. B. 203.0.113.7/32',
    smtppw: 'SMTP-Passwort: ',
    s3pw: 'S3 Secret Key: ',
    cloudinitErr: 'Die cloud-init-Vorlage ließ sich nicht laden. Sie liegt unter /cloud-init.yaml auf dieser Webseite; Seite neu laden und noch einmal versuchen.',
    pwPlaceholder: '…euer Passwort…',
    keyPlaceholder: '…Secret Key…'
  };

  var form = document.getElementById('assist');
  if (!form) return;
  var $ = function (id) { return document.getElementById(id); };
  var KEY = 'cf-assistent';
  var cloudInit = null;

  var RE = {
    host: /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/,
    email: /^[^\s@"]+@[^\s@"]+\.[^\s@"]+$/,
    bad: /["$\\`\n]/,
    badTofu: /['"$\\`\n]/,
    s3Tofu: /^[A-Za-z0-9._-]+$/,
    version: /^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$/,
    logo: /^https:\/\/[^\s"$\\`]+\.(svg|png|webp|jpg|jpeg)$/i,
    color: /^#[0-9a-fA-F]{6}$/,
    port: /^[0-9]{1,5}$/,
    s3: /^[A-Za-z0-9._\/-]+$/,
    s3endpoint: /^https?:\/\/[A-Za-z0-9.-]+(:[0-9]+)?$/,
    age: /^age1[0-9a-z]{58}$/,
    sshkey: /^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) [A-Za-z0-9+\/=]+( [^"$\\`]*)?$/,
    cidr: /^[0-9a-fA-F:.]+\/[0-9]{1,3}$/
  };

  function val(id) { var el = $(id); return el ? el.value.trim() : ''; }
  function route() { var r = form.querySelector('input[name="route"]:checked'); return r ? r.value : 'ssh'; }
  function hosts() {
    var d = val('domain');
    return {
      app: val('app') || (d ? 'app.' + d : ''),
      sync: val('sync') || (d ? 'sync.' + d : ''),
      login: val('login') || (d ? 'login.' + d : '')
    };
  }
  function cidrs() { return val('ssh_cidrs').split(/[\s,]+/).filter(Boolean); }
  function smtpFrom() { var c = val('club'), d = val('domain'); return val('smtp_from') || (c && d ? c + ' <noreply@' + d + '>' : ''); }

  // Prüfung: liefert [{id, msg}] für alles, was fehlt oder nicht passt
  function check() {
    var errs = [], r = route(), h = hosts();
    function need(id, ok, msg) {
      var v = val(id);
      if (!v) errs.push({ id: id, msg: T.required });
      else if (ok && !ok(v)) errs.push({ id: id, msg: msg });
    }
    function may(id, ok, msg) { var v = val(id); if (v && !ok(v)) errs.push({ id: id, msg: msg }); }
    var isHost = function (v) { return RE.host.test(v); };
    // Die OpenTofu-Vorlage (variables.tf) ist strenger: kein ' in Namen, kein / in Region, Bucket und Schlüssel, nur https
    var tofu = r === 'tofu';
    var isText = function (v) { return !(tofu ? RE.badTofu : RE.bad).test(v); };
    var textMsg = tofu ? T.textTofu : T.text;
    need('domain', isHost, T.host);
    ['app', 'sync', 'login'].forEach(function (k) { may(k, isHost, T.host); });
    if (h.app && (h.app === h.sync || h.app === h.login || h.sync === h.login)) errs.push({ id: 'app', msg: T.distinct });
    need('email', function (v) { return RE.email.test(v); }, T.email);
    need('club', isText, textMsg);
    may('version', function (v) { return RE.version.test(v); }, T.version);
    may('admin_first', isText, textMsg);
    may('admin_last', isText, textMsg);
    if (!val('admin_first') !== !val('admin_last')) errs.push({ id: val('admin_first') ? 'admin_last' : 'admin_first', msg: T.both });
    may('logo', function (v) { return RE.logo.test(v); }, T.logo);
    may('logo_light', function (v) { return RE.logo.test(v); }, T.logo);
    ['primary', 'dark', 'accent'].forEach(function (k) { may(k, function (v) { return RE.color.test(v); }, T.color); });
    may('group_one', isText, textMsg);
    may('group_other', isText, textMsg);
    if (val('group_one') || val('group_other')) {
      if (!val('group_one')) errs.push({ id: 'group_one', msg: T.required });
      if (!val('group_other')) errs.push({ id: 'group_other', msg: T.required });
    }
    if (val('smtp_host') || val('smtp_user')) {
      need('smtp_host', isHost, T.host);
      may('smtp_port', function (v) { return RE.port.test(v); }, T.port);
      may('smtp_user', isText, textMsg);
      may('smtp_from', isText, textMsg);
    }
    if (val('s3_endpoint') || val('s3_bucket') || val('s3_access_key')) {
      need('s3_endpoint', function (v) { return RE.s3endpoint.test(v); }, T.s3endpoint);
      var s3ok = function (v) { return (tofu ? RE.s3Tofu : RE.s3).test(v); }, s3msg = tofu ? T.s3Tofu : T.s3;
      need('s3_bucket', s3ok, s3msg);
      need('s3_access_key', s3ok, s3msg);
      may('s3_region', s3ok, s3msg);
      if (tofu && /^http:/.test(val('s3_endpoint'))) errs.push({ id: 's3_endpoint', msg: T.httpsOnly });
      may('s3_prefix', function (v) { return RE.s3.test(v); }, T.s3);
    }
    may('age', function (v) { return RE.age.test(v); }, T.age);
    if (r === 'tofu') {
      need('ssh_key', function (v) { return RE.sshkey.test(v); }, T.sshkey);
      if (cidrs().some(function (c) { return !RE.cidr.test(c); })) errs.push({ id: 'ssh_cidrs', msg: T.cidr });
      may('dns_zone', isHost, T.host);
    }
    return errs;
  }

  // Shell: Wert in einfachen Anführungszeichen, wo nötig (wie quote in install.sh)
  function q(v) { return /^[A-Za-z0-9._@:\/+=-]+$/.test(v) ? v : "'" + v.replace(/'/g, "'\\''") + "'"; }
  function hcl(v) { return '"' + v + '"'; }

  // Gemeinsame Angaben als Liste [Option, Wert] in der Reihenfolge von install.sh
  function options() {
    var h = hosts(), o = [['--app', h.app], ['--sync', h.sync], ['--login', h.login], ['--email', val('email')], ['--club', val('club')]];
    [['version', '--version'], ['logo', '--logo'], ['logo_light', '--logo-light'], ['primary', '--primary'], ['dark', '--dark'],
      ['accent', '--accent'], ['group_one', '--group-one'], ['group_other', '--group-other']].forEach(function (p) {
      if (val(p[0])) o.push([p[1], val(p[0])]);
    });
    if (val('group_one')) o.push(['--group-gender', val('group_gender')]);
    if (val('admin_first')) o.push(['--admin-first', val('admin_first')], ['--admin-last', val('admin_last')]);
    return o;
  }

  function sshCommand() {
    var o = options();
    if (val('smtp_host')) {
      o.push(['--smtp-host', val('smtp_host')], ['--smtp-port', val('smtp_port') || '587'], ['--smtp-security', val('smtp_security')]);
      if (val('smtp_user')) o.push(['--smtp-user', val('smtp_user')]);
      o.push(['--smtp-from', smtpFrom()]);
    }
    if (val('s3_endpoint')) {
      o.push(['--s3-endpoint', val('s3_endpoint')], ['--s3-bucket', val('s3_bucket')], ['--s3-access-key', val('s3_access_key')]);
      if (val('s3_region')) o.push(['--s3-region', val('s3_region')]);
      if (val('s3_prefix')) o.push(['--s3-prefix', val('s3_prefix')]);
    }
    if (val('age')) o.push(['--age-recipient', val('age')]);
    var env = [];
    if (val('smtp_user')) env.push('CF_SMTP_PASSWORD');
    if (val('s3_endpoint')) env.push('CF_S3_SECRET_KEY');
    var head = env.length ? 'sudo --preserve-env=' + env.join(',') + ' bash install.sh' : 'sudo bash install.sh';
    return head + ' \\\n' + o.map(function (p) { return '  ' + p[0] + ' ' + q(p[1]); }).join(' \\\n') + '\n';
  }

  // Eine Zeile: Beim Einfügen mehrerer Zeilen könnte ein read die nächste Zeile als Passwort schlucken
  function secretsBlock() {
    var parts = [], names = [];
    if (val('smtp_user')) { parts.push("read -rsp '" + T.smtppw + "' CF_SMTP_PASSWORD; echo"); names.push('CF_SMTP_PASSWORD'); }
    if (val('s3_endpoint')) { parts.push("read -rsp '" + T.s3pw + "' CF_S3_SECRET_KEY; echo"); names.push('CF_S3_SECRET_KEY'); }
    return parts.length ? parts.join('; ') + '; export ' + names.join(' ') : '';
  }

  function cloudInitText() {
    if (cloudInit === null) return null;
    var h = hosts(), v = {
      APP_HOST: h.app, SYNC_HOST: h.sync, LOGIN_HOST: h.login, ADMIN_EMAIL: val('email'), CLUB_NAME: val('club'),
      VERSION: val('version'), LOGO: val('logo'), LOGO_LIGHT: val('logo_light'), COLOR_PRIMARY: val('primary'),
      COLOR_DARK: val('dark'), COLOR_ACCENT: val('accent'), GROUP_ONE: val('group_one'), GROUP_OTHER: val('group_other'),
      GROUP_GENDER: val('group_one') ? val('group_gender') : '', ADMIN_FIRST: val('admin_first'), ADMIN_LAST: val('admin_last'),
      AGE_RECIPIENT: val('age'), S3_ENDPOINT: val('s3_endpoint'), S3_REGION: val('s3_region'), S3_BUCKET: val('s3_bucket'),
      S3_ACCESS_KEY: val('s3_access_key'), S3_PREFIX: val('s3_prefix')
    };
    var text = cloudInit;
    Object.keys(v).forEach(function (k) {
      text = text.replace(new RegExp('^(\\s+' + k + '=)"[^"]*"', 'm'), function (m, a) { return a + '"' + v[k] + '"'; });
    });
    return text;
  }

  function tfvars() {
    var h = hosts(), w = 18, out = [];
    function line(k, v) { out.push((k + ' '.repeat(w)).slice(0, w) + '= ' + v); }
    line('app_host', hcl(h.app)); line('sync_host', hcl(h.sync)); line('login_host', hcl(h.login));
    line('admin_email', hcl(val('email'))); line('club_name', hcl(val('club')));
    line('ssh_public_key', hcl(val('ssh_key')));
    if (cidrs().length) line('ssh_allowed_cidrs', '[' + cidrs().map(hcl).join(', ') + ']');
    line('server_type', hcl(val('server_type'))); line('location', hcl(val('location')));
    if (val('dns_zone')) line('dns_zone', hcl(val('dns_zone')));
    if (val('version')) line('clubforge_version', hcl(val('version')));
    if (val('age')) line('age_recipient', hcl(val('age')));
    [['logo', 'logo'], ['logo_light', 'logo_light'], ['primary', 'color_primary'], ['dark', 'color_dark'], ['accent', 'color_accent'],
      ['group_one', 'group_one'], ['group_other', 'group_other']].forEach(function (p) { if (val(p[0])) line(p[1], hcl(val(p[0]))); });
    if (val('group_one')) line('group_gender', hcl(val('group_gender')));
    if (val('admin_first')) { line('admin_first', hcl(val('admin_first'))); line('admin_last', hcl(val('admin_last'))); }
    [['s3_endpoint', 's3_endpoint'], ['s3_region', 's3_region'], ['s3_bucket', 's3_bucket'], ['s3_access_key', 's3_access_key'],
      ['s3_prefix', 's3_prefix']].forEach(function (p) { if (val(p[0])) line(p[1], hcl(val(p[0]))); });
    return out.join('\n') + '\n';
  }

  // Mail und S3-Secret gibt es bei cloud-init und OpenTofu nur nach der Installation in der .env
  function afterEnv() {
    var lines = [];
    if (val('smtp_host')) {
      lines.push('CF_SMTP_HOST=' + val('smtp_host'), 'CF_SMTP_PORT=' + (val('smtp_port') || '587'), 'CF_SMTP_SECURITY=' + val('smtp_security'));
      if (val('smtp_user')) lines.push('CF_SMTP_USER=' + val('smtp_user'), "CF_SMTP_PASSWORD='" + T.pwPlaceholder + "'");
      lines.push('CF_MAIL_FROM="' + smtpFrom() + '"');
    }
    if (val('s3_endpoint')) lines.push('CF_S3_SECRET_KEY=' + T.keyPlaceholder);
    return lines.join('\n');
  }

  function set(id, text) { var el = $(id); if (el) el.textContent = text; }
  function show(id, on) { var el = $(id); if (el) el.hidden = !on; }

  function render() {
    var r = route(), h = hosts(), errs = check();
    ['ssh', 'console', 'tofu'].forEach(function (k) { show('out-' + k, k === r); });
    show('f-tofu', r === 'tofu');
    show('f-hetzner', r !== 'ssh');
    ['app', 'sync', 'login'].forEach(function (k) { var el = $(k); if (el) el.placeholder = val('domain') ? k + '.' + val('domain') : k + '.mein-verein.example'; });
    var from = $('smtp_from'); if (from) from.placeholder = smtpFrom() || (en ? 'Your Club <noreply@your-club.example>' : 'Mein Verein <noreply@mein-verein.example>');
    ['primary', 'dark', 'accent'].forEach(function (k) {
      var sw = $(k + '_sw'); if (sw) sw.style.background = RE.color.test(val(k)) ? val(k) : 'transparent';
    });

    form.querySelectorAll('[aria-invalid]').forEach(function (el) { el.removeAttribute('aria-invalid'); });
    form.querySelectorAll('.field-err').forEach(function (el) { el.textContent = ''; });
    errs.forEach(function (e) {
      var el = $(e.id), m = $(e.id + '_err');
      if (el && (el.value || el.dataset.touched)) { el.setAttribute('aria-invalid', 'true'); if (m) m.textContent = e.msg; }
    });
    var list = $('errors');
    list.innerHTML = '';
    if (errs.length) {
      var p = document.createElement('p'); p.textContent = T.missing; list.appendChild(p);
      var ul = document.createElement('ul');
      errs.forEach(function (e) {
        var li = document.createElement('li'), a = document.createElement('a'), lab = form.querySelector('label[for="' + e.id + '"]');
        a.href = '#' + e.id; a.textContent = lab ? lab.textContent.replace(/\s*\(.*\)\s*$/, '') : e.id;
        li.appendChild(a); li.appendChild(document.createTextNode(': ' + e.msg)); ul.appendChild(li);
      });
      list.appendChild(ul);
    }
    show('errors', errs.length > 0);
    show('outputs', errs.length === 0);
    if (errs.length) return;

    var dig = ['app', 'sync', 'login'].map(function (k) { return 'dig +short ' + h[k]; }).join('\n');
    set('o-dig-console', dig); set('o-dig-tofu', dig);
    var sec = secretsBlock();
    show('ssh-secrets', !!sec); set('o-ssh-secrets', sec);
    set('o-ssh', sshCommand());
    var ci = cloudInitText();
    show('cloudinit-err', ci === null); show('cloudinit-ok', ci !== null);
    if (ci === null) set('cloudinit-err', T.cloudinitErr);
    if (ci !== null) set('o-cloudinit', ci);
    set('o-tofu-get', 'cid=$(docker create docker.io/cygnusbn/clubforge:' + (val('version') || 'latest') + ')\n' +
      'docker cp "$cid:/opt/clubforge/deploy/cloud" ./clubforge-cloud && docker rm "$cid"\n' +
      'cd clubforge-cloud/hetzner');
    set('o-tfvars', tfvars());
    var after = afterEnv();
    ['console', 'tofu'].forEach(function (k) { show('after-' + k, !!after); set('o-after-' + k, after); });
    set('o-tofu-type', val('server_type')); set('o-console-type', val('server_type'));
    var loc = $('location'); set('o-console-location', loc && loc.selectedOptions[0] ? loc.selectedOptions[0].textContent : '');
  }

  function save() {
    try {
      var data = {};
      form.querySelectorAll('input, select, textarea').forEach(function (el) {
        if (el.type === 'radio') { if (el.checked) data[el.name] = el.value; } else if (el.id) data[el.id] = el.value;
      });
      localStorage.setItem(KEY, JSON.stringify(data));
    } catch (e) { /* ohne Speicher geht es auch */ }
  }
  function load() {
    try {
      var data = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (!data) return;
      Object.keys(data).forEach(function (k) {
        if (k === 'route') { var r = form.querySelector('input[name="route"][value="' + data[k] + '"]'); if (r) r.checked = true; }
        else if ($(k)) $(k).value = data[k];
      });
    } catch (e) { /* ohne Speicher geht es auch */ }
  }

  load();
  form.addEventListener('input', function (ev) { if (ev.target.id) ev.target.dataset.touched = '1'; render(); save(); });
  form.addEventListener('change', function () { render(); save(); });
  form.addEventListener('submit', function (ev) { ev.preventDefault(); });
  $('reset').addEventListener('click', function () {
    try { localStorage.removeItem(KEY); } catch (e) { /* egal */ }
    form.reset();
    form.querySelectorAll('[data-touched]').forEach(function (el) { delete el.dataset.touched; });
    fillVersion(); render();
  });

  // Vorgabe für die Version: die aktuelle aus version.json (wie version.js), nur wenn das Feld leer ist
  var base = (document.currentScript && document.currentScript.src || '').replace(/einrichten\/[^/]*$/, '');
  var current = '';
  function fillVersion() { if (current && !val('version')) $('version').value = current; }
  fetch(base + 'version.json', { cache: 'no-cache' }).then(function (r) { return r.ok ? r.json() : null; }).then(function (v) {
    if (v && RE.version.test(v.version)) { current = v.version; fillVersion(); render(); }
  }).catch(function () {});
  fetch(base + 'cloud-init.yaml', { cache: 'no-cache' }).then(function (r) { return r.ok ? r.text() : null; }).then(function (t) {
    if (t && /^\s+APP_HOST="/m.test(t)) { cloudInit = t; render(); }
  }).catch(function () {});

  render();
})();
