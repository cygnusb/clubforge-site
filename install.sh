#!/usr/bin/env bash
# Installiert clubforge auf einem frischen Server (Debian 12/13, Ubuntu 24.04; x86_64 und arm64): Docker aus dem
# offiziellen Repository, Firewall (nur 22/80/443), automatische Sicherheitsupdates, Benutzer "clubforge", fertiges Image
# aus der Registry (kein Git, kein Bau auf dem Server), Konfiguration mit Zufalls-Geheimnissen, Start, tägliches
# verschlüsseltes Backup, Gesundheitsprüfung.
# Idempotent: ein zweiter Lauf überspringt, was schon steht (vorhandene .env bleibt unangetastet).
#
#   sudo ./install.sh --app app.verein.de --sync sync.verein.de --login login.verein.de --email admin@verein.de \
#                     --club "Mein Verein" [--version 0.1.0] [--image REGISTRY/NAME] [--age-recipient age1…] [--dry-run]
#
# Die drei Namen müssen vorher per DNS auf diesen Server zeigen (A, ggf. AAAA) und Port 80/443 muss von außen offen sein.
# Optionen:
#   --version X.Y.Z     Version des Images; Standard: die neueste (Tag "latest"), eingetragen wird die konkrete Nummer
#   --image NAME        Image (Standard: $CLUBFORGE_IMAGE oder docker.io/cygnusbn/clubforge; Alternative ghcr.io/cygnusb/clubforge)
#   Vereinsmarke (Details und Beispiele: deploy/branding.sh --help; später änderbar mit deploy/branding.sh):
#     --club NAME --short-name NAME --logo DATEI|https://… [--logo-light …] [--favicon …]
#     --primary #rrggbb --dark #rrggbb --accent #rrggbb --signal #rrggbb --primary-dark #rrggbb
#     --group-one Team --group-other Teams --group-gender n
#   --admin-first VORNAME --admin-last NACHNAME [--admin-email ADRESSE]   erste Admin-Person gleich anlegen (Standard: --email)
#   --dir PFAD          Installationsverzeichnis (Standard /opt/clubforge)
#   --smtp-host/--smtp-port/--smtp-user/--smtp-security/--smtp-from   Mailversand (Passwort: Umgebungsvariable CF_SMTP_PASSWORD)
#   --s3-endpoint/--s3-region/--s3-bucket/--s3-access-key/--s3-prefix   Object Storage für Anhänge (Secret Key: Umgebungsvariable
#                       CF_S3_SECRET_KEY; ohne --s3-endpoint gibt es keine Anhänge, siehe docs/betrieb/anhaenge.md)
#   --age-recipient K   öffentlicher age-Schlüssel für Backups; ohne Angabe wird ein Schlüsselpaar erzeugt
#   --restore DIR --identity KEY   statt Neuinstallation ein Backup einspielen (Umzug / Wiederherstellung)
#   --skip-dns-check    DNS-Prüfung überspringen
#   --no-start          alles vorbereiten, aber den Stack nicht starten
#   --yes               keine Rückfragen (z. B. cloud-init)
#   --dry-run           nur anzeigen, was getan würde
# Ohne --app/--sync/--login/--email fragt der Installer im Terminal alles ab (Fragemodus: sudo bash install.sh).
# Entwickler: --ref TAG und --repo URL holen den Code stattdessen per Git (Standard: https://github.com/cygnusb/clubforge.git)
# und bauen das Image auf dem Server.
set -euo pipefail

app="" sync="" login="" email="" club="" ref="" dir=/opt/clubforge version=""
image="${CLUBFORGE_IMAGE:-docker.io/cygnusbn/clubforge}"
repo="${CLUBFORGE_REPO:-https://github.com/cygnusb/clubforge.git}"
git_mode=0
brand_args=() admin_email="" admin_first="" admin_last="" brand_tmp=""
[ -z "${CLUBFORGE_REPO:-}" ] || git_mode=1
smtp_host="" smtp_port="" smtp_user="" smtp_security="" smtp_from="" age_recipient=""
s3_endpoint="" s3_region="" s3_bucket="" s3_access_key="" s3_prefix=""
restore="" identity="" skip_dns=0 no_start=0 yes=0 dry=0

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
	case "$1" in
	--dry-run) dry=1; shift; continue ;;
	--yes | -y) yes=1; shift; continue ;;
	--skip-dns-check) skip_dns=1; shift; continue ;;
	--no-start) no_start=1; shift; continue ;;
	-h | --help) usage; exit 0 ;;
	--app | --sync | --login | --email | --club | --ref | --repo | --version | --image | --dir | --short-name | --logo | --logo-light | --favicon | --primary | --dark | --accent | --signal | --primary-dark | --group-one | --group-other | --group-gender | --admin-email | --admin-first | --admin-last | --smtp-host | --smtp-port | --smtp-user | --smtp-security | --smtp-from | --s3-endpoint | --s3-region | --s3-bucket | --s3-access-key | --s3-prefix | --age-recipient | --restore | --identity) ;;
	*) echo "Unbekannte Option: $1" >&2; usage >&2; exit 2 ;;
	esac
	[ $# -ge 2 ] || { echo "Wert für $1 fehlt" >&2; exit 2; }
	case "$1" in
	--app) app="$2" ;; --sync) sync="$2" ;; --login) login="$2" ;; --email) email="$2" ;; --club) club="$2" ;;
	--ref) ref="$2"; git_mode=1 ;; --repo) repo="$2"; git_mode=1 ;; --dir) dir="$2" ;;
	--version) version="${2#v}" ;; --image) image="$2" ;;
	--admin-email) admin_email="$2" ;; --admin-first) admin_first="$2" ;; --admin-last) admin_last="$2" ;;
	--short-name | --logo | --logo-light | --favicon | --primary | --dark | --accent | --signal | --primary-dark | --group-one | --group-other | --group-gender) brand_args+=("$1" "$2") ;;
	--smtp-host) smtp_host="$2" ;; --smtp-port) smtp_port="$2" ;; --smtp-user) smtp_user="$2" ;;
	--smtp-security) smtp_security="$2" ;; --smtp-from) smtp_from="$2" ;;
	--s3-endpoint) s3_endpoint="$2" ;; --s3-region) s3_region="$2" ;; --s3-bucket) s3_bucket="$2" ;;
	--s3-access-key) s3_access_key="$2" ;; --s3-prefix) s3_prefix="$2" ;;
	--age-recipient) age_recipient="$2" ;; --restore) restore="$2" ;; --identity) identity="$2" ;;
	esac
	shift 2
done

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNUNG: %s\n' "$*" >&2; }
die() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }
# image_verify <Image:Tag> <Version>: Signatur des Release-Workflows prüfen (cosign keyless, Sigstore), wenn cosign
# installiert ist. Ab 0.5.3 ist jedes veröffentlichte Image signiert: Fehlt die Signatur, ist das ein Fehler (sonst
# genügte es, sie in der Registry zu löschen). Ältere Versionen sind unsigniert, dort nur ein Hinweis. Eigene Images
# (anderer CLUBFORGE_IMAGE) prüft das Skript nicht.
image_verify() {
	local ref="$1" ver="$2" first=0.5.3
	case "$ref" in docker.io/cygnusbn/clubforge:* | cygnusbn/clubforge:* | ghcr.io/cygnusb/clubforge:*) ;; *) return 0 ;; esac
	if ! command -v cosign >/dev/null 2>&1; then
		warn "cosign ist nicht installiert: Signatur von $ref ungeprüft (Installation: https://docs.sigstore.dev/cosign/system_config/installation/)"
		return 0
	fi
	if cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com \
		--certificate-identity-regexp '^https://github[.]com/cygnusb/clubforge/[.]github/workflows/release[.]yml@refs/tags/v' \
		"$ref" >/dev/null 2>&1; then
		log "Signatur von $ref geprüft"
	elif [ "$(printf '%s\n%s\n' "$first" "$ver" | sort -V | head -n 1)" = "$first" ]; then
		die "Signatur von $ref fehlt oder ist ungültig – Image nicht verwenden"
	else
		warn "$ref (Version $ver) stammt aus der Zeit vor den Signaturen; ungeprüft"
	fi
}
# run <Befehl…>: führt aus bzw. zeigt im Trockenlauf nur an
run() {
	if [ "$dry" = 1 ]; then printf '  + %s\n' "$*"; else "$@"; fi
}
# write_file <Pfad> <Modus>: Inhalt von der Standardeingabe
write_file() {
	if [ "$dry" = 1 ]; then printf '  + schreibe %s (Modus %s):\n' "$1" "$2"; sed 's/^/      | /'; return 0; fi
	install -m "$2" /dev/stdin "$1"
}
as_cf() { run runuser -u clubforge -- "$@"; }

# ---- Vorprüfung
log "Vorprüfung"
[ "$dry" = 1 ] || [ "$(id -u)" -eq 0 ] || die "Bitte als root ausführen (sudo $0 …)"
[ -r /etc/os-release ] || die "/etc/os-release fehlt: kein unterstütztes Linux"
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}:${VERSION_ID:-}" in
debian:12 | debian:13 | ubuntu:24.04) ;;
*) die "Nicht unterstützt: ${PRETTY_NAME:-$ID $VERSION_ID} (Debian 12/13 oder Ubuntu 24.04)" ;;
esac
codename="${VERSION_CODENAME:-}"
[ -n "$codename" ] || die "VERSION_CODENAME fehlt in /etc/os-release"
case "$(uname -m)" in
x86_64 | aarch64) ;;
*) die "Nicht unterstützte Architektur: $(uname -m) (x86_64 oder aarch64)" ;;
esac
echo "System: ${PRETTY_NAME:-$ID $VERSION_ID}, $(uname -m), Docker-Repository: $ID/$codename"
mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
if [ "$git_mode" = 1 ]; then
	[ "$mem_mb" -ge 3500 ] || warn "Nur $mem_mb MB Arbeitsspeicher; für den Bau der Web-App und den Betrieb werden 4 GB empfohlen"
else
	[ "$mem_mb" -ge 3000 ] || warn "Nur $mem_mb MB Arbeitsspeicher; für den Betrieb werden 4 GB empfohlen"
	[ -z "$version" ] || [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] || die "Ungültige Version: $version (erwartet x.y.z)"
	[[ "$image" =~ ^[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._-]+)+$ ]] || die "Ungültiger Image-Name: $image (ohne Tag, z. B. docker.io/cygnusbn/clubforge)"
fi

# dns_check: zeigen die drei Namen auf diesen Server? Rückgabe 1, wenn einer fehlt oder woandershin zeigt
dns_check() {
	local h ips bad=0
	[ -n "${my_ip:-}" ] || my_ip="$(curl -4 -fsS -m 6 https://api.ipify.org 2>/dev/null || true)"
	for h in "$app" "$sync" "$login"; do
		ips="$(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' || true)"
		if [ -z "$ips" ]; then echo "  $h: kein A-Eintrag"; bad=1
		elif [ -n "$my_ip" ] && [[ " $ips" != *" $my_ip "* ]]; then echo "  $h: zeigt auf $ips, dieser Server ist $my_ip"; bad=1
		else echo "  $h: $ips"; fi
	done
	return "$bad"
}

# ---- Fragemodus
# Ohne Namen und E-Mail fragt der Installer im Terminal nach (nie mit --yes, also nie unter cloud-init). Gelesen wird von
# /dev/tty, damit es auch mit umgeleiteter Eingabe geht. Die Prüfungen entsprechen gen-env.sh und branding.sh: Ein Tippfehler
# soll hier auffallen, nicht erst nach der Docker-Installation. Geändert wird erst nach dem „ja“ zur Zusammenfassung.
valid_host() { [[ "$1" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; }
valid_email() { [[ "$1" =~ ^[^[:space:]@\"]+@[^[:space:]@\"]+\.[^[:space:]@\"]+$ ]]; }
valid_text() { case "$1" in *\"* | *$'\n'* | *'$'* | *\\*) return 1 ;; esac; }
valid_color() { [[ "$1" =~ ^#[0-9a-fA-F]{6}$ ]]; }
valid_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; }
valid_logo() { [[ "${1,,}" =~ ^https://[^[:space:]\"\$\\]+\.(svg|png|webp|jpg|jpeg)$ ]] || { [ -f "$1" ] && valid_text "$1"; }; }
valid_gender() { [[ "$1" =~ ^[mfn]$ ]]; }
valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]]; }
valid_security() { [[ "$1" =~ ^(none|starttls|ssl)$ ]]; }
valid_s3_endpoint() { [[ "$1" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; }
valid_s3() { [[ "$1" =~ ^[A-Za-z0-9._/-]+$ ]]; }
valid_age() { [[ "$1" =~ ^age1[0-9a-z]{58}$ ]]; }
# wie gen-env.sh: Passwort ohne ', Secret Key ohne ' " $ und Leerzeichen
bad_smtp_password() { [[ "$1" == *"'"* ]]; }
bad_s3_secret() { [[ "$1" =~ [\'\"\$[:space:]] ]]; }
req() { [ -n "$2" ] && "$1" "$2"; }
opt() { [ -z "$2" ] || "$1" "$2"; }
# frage <Variable> <Frage> <Vorgabe> <Prüfung, z. B. "req valid_host"> <Hinweis bei Fehler>
frage() {
	local a
	while :; do
		if [ -n "$3" ]; then printf '%s [%s]: ' "$2" "$3" >/dev/tty; else printf '%s: ' "$2" >/dev/tty; fi
		IFS= read -r a </dev/tty || die "Eingabe abgebrochen"
		a="${a:-$3}"
		# shellcheck disable=SC2086 # $4 ist absichtlich „Art Prüffunktion“
		if $4 "$a"; then printf -v "$1" '%s' "$a"; return 0; fi
		printf '  %s\n' "$5" >/dev/tty
	done
}
# jein <Frage> <j|n>: Rückgabe 0 bei ja
jein() {
	local a
	while :; do
		if [ "$2" = j ]; then printf '%s [J/n]: ' "$1" >/dev/tty; else printf '%s [j/N]: ' "$1" >/dev/tty; fi
		IFS= read -r a </dev/tty || die "Eingabe abgebrochen"
		case "${a:-$2}" in j | J | ja | Ja | y | Y | yes) return 0 ;; n | N | nein | Nein | no) return 1 ;; esac
	done
}
# geheim <Variable> <Frage> <Prüfung auf verbotene Zeichen>: verdeckte Eingabe, zweimal zur Kontrolle
geheim() {
	local a b
	while :; do
		printf '%s (Eingabe unsichtbar): ' "$2" >/dev/tty
		IFS= read -rs a </dev/tty || die "Eingabe abgebrochen"
		printf '\nNoch einmal: ' >/dev/tty
		IFS= read -rs b </dev/tty || die "Eingabe abgebrochen"
		printf '\n' >/dev/tty
		if [ -z "$a" ]; then echo "  Leer – bitte eingeben (oder Strg+C)" >/dev/tty
		elif [ "$a" != "$b" ]; then echo "  Die Eingaben stimmen nicht überein" >/dev/tty
		elif "$3" "$a"; then echo "  Enthält ein nicht erlaubtes Zeichen" >/dev/tty
		else printf -v "$1" '%s' "$a"; return 0; fi
	done
}
# quote: Wert für die Befehlszeile in einfachen Anführungszeichen, wo nötig
quote() { if [[ "$1" =~ ^[A-Za-z0-9._@:/+=-]+$ ]]; then printf '%s' "$1"; else printf "'%s'" "${1//\'/\'\\\'\'}"; fi; }

wizard() {
	local domain="" b v ok
	cat >/dev/tty <<-'EOF'

		clubforge einrichten
		Ein paar Fragen, dann richtet der Installer alles ein. Vorgaben in [Klammern] mit Enter übernehmen.
		Geändert wird erst, wenn ihr am Ende mit „ja“ bestätigt. Abbrechen jederzeit mit Strg+C.

		Namen. Drei Adressen eurer Domain zeigen auf diesen Server; sie lassen sich später nicht mehr ändern.
	EOF
	while :; do
		frage domain "Domain des Vereins (z. B. mein-verein.de)" "" "req valid_host" "Nur Kleinbuchstaben, Ziffern, Punkt und Bindestrich, ohne https:// und Pfad"
		frage app "Adresse der App" "app.$domain" "req valid_host" "Ungültiger Name"
		frage sync "Adresse der Synchronisation" "sync.$domain" "req valid_host" "Ungültiger Name"
		frage login "Adresse der Anmeldung" "login.$domain" "req valid_host" "Ungültiger Name"
		{ [ "$app" != "$sync" ] && [ "$app" != "$login" ] && [ "$sync" != "$login" ]; } && break
		echo "  App, Synchronisation und Anmeldung brauchen drei verschiedene Namen." >/dev/tty
	done
	printf '\nDNS-Prüfung (A-Einträge auf diesen Server):\n' >/dev/tty
	while ! dns_check >/dev/tty; do
		printf 'Einträge setzen oder warten (neue Einträge brauchen einige Minuten).\nEnter = erneut prüfen, w = ohne Prüfung weiter: ' >/dev/tty
		IFS= read -r v </dev/tty || die "Eingabe abgebrochen"
		if [ "$v" = w ]; then
			skip_dns=1
			echo "  Weiter ohne DNS: Das Zertifikat holt der Server erst, wenn die Namen stimmen." >/dev/tty
			break
		fi
	done

	printf '\nVerein\n' >/dev/tty
	frage email "E-Mail-Adresse der Administration (Let's Encrypt, Hinweise, Anmeldung der ersten Admin-Person)" "" "req valid_email" "Keine gültige E-Mail-Adresse"
	frage club "Name des Vereins" "" "req valid_text" "Bitte angeben, ohne \" \$ \\"
	frage version "Version (leer = neueste, empfohlen ist eine feste wie 0.2.1)" "$version" "opt valid_version" "Form x.y.z, z. B. 0.2.1"
	if jein "Logo und Farben jetzt festlegen? (später in der App änderbar)" n; then
		for b in "--logo:Logo für dunklen Grund, weiß oder hell (https://…, SVG/PNG/WebP/JPEG)" "--logo-light:Logo für hellen Grund, dunkel (https://…)"; do
			frage v "${b#*:}" "" "opt valid_logo" "https-Adresse auf .svg, .png, .webp oder .jpg (oder eine Datei auf dem Server)"
			[ -z "$v" ] || brand_args+=("${b%%:*}" "$v")
		done
		for b in "--primary:Hauptfarbe" "--dark:Dunkle Farbe für Kopfzeile und Anmeldung (weißer Text muss lesbar sein)" "--accent:Akzentfarbe"; do
			frage v "${b#*:} (#rrggbb, leer = Standard)" "" "opt valid_color" "Farbe der Form #rrggbb, z. B. #117733"
			[ -z "$v" ] || brand_args+=("${b%%:*}" "$v")
		done
	fi
	if jein "Eigener Begriff statt Gruppe (z. B. Team, Abteilung)?" n; then
		frage v "Einzahl" "" "req valid_text" "Bitte angeben"; brand_args+=(--group-one "$v")
		frage v "Mehrzahl" "" "req valid_text" "Bitte angeben"; brand_args+=(--group-other "$v")
		frage v "Geschlecht (m, f oder n, für der/die/das)" "" "req valid_gender" "m, f oder n"; brand_args+=(--group-gender "$v")
	fi
	if jein "Erste Admin-Person ($email) gleich anlegen?" j; then
		frage admin_first "Vorname" "" "req valid_text" "Bitte angeben"
		frage admin_last "Nachname" "" "req valid_text" "Bitte angeben"
	fi

	printf '\nOptionale Dienste (alles auch später in /opt/clubforge/deploy/.env)\n' >/dev/tty
	if jein "Mailversand (SMTP) einrichten? Ohne verschickt der Server keine Mails, App und Push laufen trotzdem" n; then
		frage smtp_host "SMTP-Server" "" "req valid_host" "Name des Servers, z. B. smtp.example.org"
		frage smtp_port "Port" "587" "req valid_port" "Zahl, meist 587"
		frage smtp_security "Verschlüsselung (starttls, ssl oder none)" "starttls" "req valid_security" "starttls, ssl oder none"
		frage smtp_user "Benutzername (leer = ohne Anmeldung)" "" "opt valid_text" "Ohne \" \$ \\"
		[ -z "$smtp_user" ] || { geheim CF_SMTP_PASSWORD "SMTP-Passwort (ohne ')" bad_smtp_password; export CF_SMTP_PASSWORD; }
		frage smtp_from "Absender" "$club <noreply@$domain>" "req valid_text" "Ohne \" \$ \\"
	fi
	if jein "Speicher für Anhänge (S3, z. B. Hetzner Object Storage) einrichten? Ohne gibt es keine Anhänge" n; then
		frage s3_endpoint "Endpunkt" "https://fsn1.your-objectstorage.com" "req valid_s3_endpoint" "Form https://name.example.org"
		frage s3_region "Region" "fsn1" "req valid_s3" "Buchstaben, Ziffern, . _ - /"
		frage s3_bucket "Bucket (eigener Bucket, nicht der der Backups)" "" "req valid_s3" "Buchstaben, Ziffern, . _ - /"
		frage s3_access_key "Access Key" "" "req valid_s3" "Buchstaben, Ziffern, . _ - /"
		geheim CF_S3_SECRET_KEY "Secret Key" bad_s3_secret
		export CF_S3_SECRET_KEY
		frage s3_prefix "Präfix im Bucket (leer = keins)" "" "opt valid_s3" "Buchstaben, Ziffern, . _ - /"
	fi
	if jein "Eigenen öffentlichen Backup-Schlüssel (age1…) eintragen? Sonst erzeugt der Installer einen und zeigt den geheimen Teil einmal an" n; then
		frage age_recipient "Öffentlicher Schlüssel" "" "req valid_age" "Form age1… (62 Zeichen), aus age-keygen"
	fi

	# Zusammenfassung und derselbe Aufruf ohne Rückfragen (ohne Passwörter), zum Aufheben
	local cmd=(sudo bash install.sh --app "$app" --sync "$sync" --login "$login" --email "$email" --club "$club")
	[ -z "$version" ] || cmd+=(--version "$version")
	cmd+=("${brand_args[@]}")
	[ -z "$admin_first" ] || cmd+=(--admin-first "$admin_first" --admin-last "$admin_last")
	for v in smtp_host smtp_port smtp_security smtp_user smtp_from s3_endpoint s3_region s3_bucket s3_access_key s3_prefix age_recipient; do
		[ -z "${!v}" ] || cmd+=("--${v//_/-}" "${!v}")
	done
	[ "$skip_dns" = 0 ] || cmd+=(--skip-dns-check)
	cat >/dev/tty <<-EOF

		Zusammenfassung
		  App, Sync, Anmeldung: $app, $sync, $login
		  Verein: $club, Administration: $email
		  Version: ${version:-neueste}
		  Erste Admin-Person: $([ -n "$admin_first" ] && echo "$admin_first $admin_last" || echo "später mit admin.sh")
		  Mail: ${smtp_host:-nein}, Anhänge (S3): ${s3_bucket:-nein}
		  Backup-Schlüssel: $([ -n "$age_recipient" ] && echo "eigener" || echo "wird erzeugt und einmal angezeigt")

		Derselbe Aufruf ohne Rückfragen (Passwörter über CF_SMTP_PASSWORD und CF_S3_SECRET_KEY):
	EOF
	ok=""
	for v in "${cmd[@]}"; do ok+="${ok:+ }$(quote "$v")"; done
	printf '  %s\n\n' "$ok" >/dev/tty
	jein "Mit diesen Angaben installieren?" j || die "Abgebrochen – nichts geändert"
}

if [ -z "$restore" ] && [ "$yes" = 0 ] && [ -z "$app$sync$login$email" ]; then
	{ : </dev/tty; } 2>/dev/null || die "Ohne Angaben fragt der Installer im Terminal nach; hier gibt es keins. --app, --sync, --login und --email angeben (siehe --help)"
	if [ -f "$dir/deploy/.env" ]; then
		# Zweiter Lauf: die Einstellungen stehen schon fest
		env_val() { sed -n "s/^$1=//p" "$dir/deploy/.env" | head -n 1 | tr -d '"'; }
		app="$(env_val APP_HOST)" sync="$(env_val SYNC_HOST)" login="$(env_val LOGIN_HOST)" email="$(env_val ACME_EMAIL)"
		[ -n "$version" ] || version="$(env_val CLUBFORGE_VERSION)"
		echo "$dir/deploy/.env gibt es schon; Namen und Einstellungen kommen von dort ($app, $sync, $login)."
	else
		wizard
	fi
fi
if [ -z "$restore" ]; then
	for v in app sync login email; do [ -n "${!v}" ] || die "--$v fehlt (siehe --help)"; done
	{ [ -z "$admin_first" ] && [ -z "$admin_last" ]; } || { [ -n "$admin_first" ] && [ -n "$admin_last" ]; } || die "--admin-first und --admin-last gehören zusammen"
	[ -z "$admin_email" ] || [ -n "$admin_first" ] || die "--admin-email braucht --admin-first und --admin-last"
	[ -z "$admin_first" ] || [ -n "$admin_email" ] || admin_email="$email"
else
	[ -d "$restore" ] || die "Backup-Verzeichnis nicht gefunden: $restore"
	[ -r "$identity" ] || die "--identity SCHLÜSSELDATEI nötig für --restore"
fi

# ---- Pakete
log "Pakete installieren"
export DEBIAN_FRONTEND=noninteractive
run apt-get update -qq
run apt-get install -y -qq ca-certificates curl gnupg ufw unattended-upgrades age openssl jq util-linux
[ "$git_mode" = 0 ] || run apt-get install -y -qq git

log "DNS"
if [ -z "$restore" ] && [ "$skip_dns" = 0 ]; then
	my_ip=""
	bad=0
	dns_check || bad=1
	if [ "$bad" = 1 ]; then
		if [ "$dry" = 1 ]; then warn "DNS stimmt noch nicht (im Trockenlauf nur Hinweis)"
		else die "DNS stimmt nicht. Einträge setzen und warten (oder mit --skip-dns-check fortfahren, dann holt Caddy das Zertifikat erst später)."; fi
	fi
fi

# ---- Docker
log "Docker"
compose_ok=0
if command -v docker >/dev/null 2>&1 && cv="$(docker compose version --short 2>/dev/null)"; then
	[ "$(printf '%s\n2.24.0\n' "${cv#v}" | sort -V | head -n 1)" = "2.24.0" ] && compose_ok=1
fi
if [ "$compose_ok" = 1 ]; then
	echo "Docker Compose ${cv} ist vorhanden"
else
	arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
	run install -m 0755 -d /etc/apt/keyrings
	run curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
	run chmod a+r /etc/apt/keyrings/docker.asc
	echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $codename stable" |
		write_file /etc/apt/sources.list.d/docker.list 644
	run apt-get update -qq
	# Container-Logs rotieren (sonst wachsen sie unbegrenzt); nur anlegen, wenn es noch keine Docker-Konfiguration gibt
	if [ ! -e /etc/docker/daemon.json ]; then
		run install -d -m 755 /etc/docker
		printf '{\n  "log-driver": "json-file",\n  "log-opts": { "max-size": "10m", "max-file": "5" }\n}\n' | write_file /etc/docker/daemon.json 644
	fi
	run apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	run systemctl enable --now docker
fi

# ---- Firewall und automatische Updates
log "Firewall (nur 22, 80, 443) und automatische Sicherheitsupdates"
ssh_port="$(printf '%s' "${SSH_CONNECTION:-}" | awk '{print $4}')"
run ufw default deny incoming
run ufw default allow outgoing
run ufw allow 22/tcp
[ -z "$ssh_port" ] || [ "$ssh_port" = 22 ] || run ufw allow "$ssh_port/tcp"
run ufw allow 80/tcp
run ufw allow 443/tcp
run ufw --force enable
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' | write_file /etc/apt/apt.conf.d/20auto-upgrades 644

# ---- Benutzer und Code
log "Benutzer clubforge"
if ! id clubforge >/dev/null 2>&1; then
	run useradd --system --create-home --home-dir /home/clubforge --shell /bin/bash clubforge
fi
run usermod -aG docker clubforge
run install -d -o clubforge -g clubforge -m 755 "$dir"
run install -d -o clubforge -g clubforge -m 700 /var/backups/clubforge

if [ "$git_mode" = 1 ]; then
	log "Code per Git ($repo)"
	if [ ! -d "$dir/.git" ]; then
		as_cf git clone "$repo" "$dir"
	else
		echo "Checkout $dir vorhanden"
		as_cf git -C "$dir" fetch --tags --prune -q
	fi
	if [ "$dry" = 1 ]; then
		echo "  + git checkout ${ref:-<neuestes Tag v*, sonst Standardbranch>}"
	else
		if [ -z "$ref" ]; then
			ref="$(runuser -u clubforge -- git -C "$dir" tag --list 'v*' --sort=-v:refname | head -n 1)"
			[ -n "$ref" ] || { warn "Keine Versions-Tags gefunden; es bleibt der Standardbranch"; ref=""; }
		fi
		[ -z "$ref" ] || as_cf git -C "$dir" checkout --detach -q "$ref"
		echo "Version: $(runuser -u clubforge -- git -C "$dir" describe --tags --always)"
	fi
else
	log "Image holen ($image:${version:-latest})"
	if [ "$dry" = 1 ]; then
		echo "  + docker pull $image:${version:-latest}"
		echo "  + Betriebsdateien aus dem Image nach $dir/deploy entpacken (docker create, docker cp)"
		echo "Version: ${version:-<neueste>}"
		[ -n "$version" ] || version="<neueste>"
	else
		docker pull -q "$image:${version:-latest}" >/dev/null || die "Image $image:${version:-latest} nicht abrufbar (Version und Netzwerk prüfen)"
		found="$(docker run --rm --pull=never --entrypoint cat "$image:${version:-latest}" /opt/clubforge/deploy/VERSION | tr -d '[:space:]')"
		[[ "$found" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] || die "Das Image enthält keine gültige Versionsnummer ($found)"
		if [ -z "$version" ]; then
			version="$found"
			docker pull -q "$image:$version" >/dev/null || die "Image $image:$version nicht abrufbar"
		elif [ "$found" != "$version" ]; then
			warn "Das Image $image:$version meldet die Version $found"
		fi
		echo "Version: $version"
		image_verify "$image:$version" "$version"
		tmp="$(mktemp -d)"
		cid="$(docker create --pull=never "$image:$version")"
		docker cp "$cid:/opt/clubforge/deploy/." "$tmp" >/dev/null
		docker rm -f "$cid" >/dev/null
		install -d -o clubforge -g clubforge -m 755 "$dir/deploy"
		# vorhandene Dateien (.env, caddy/extra/*.caddy, eigenes Branding) bleiben
		(cd "$tmp" && tar -cf - --exclude='./branding' .) | (cd "$dir/deploy" && tar -xpf -)
		install -d "$dir/deploy/branding"
		(cd "$tmp/branding" && find . -type f) | while IFS= read -r f; do
			[ -e "$dir/deploy/branding/$f" ] || cp -p "$tmp/branding/$f" "$dir/deploy/branding/$f"
		done
		(cd "$tmp" && find . -type f ! -path './branding/*' | sort) >"$dir/deploy/.managed"
		rm -rf "$tmp"
		chown -R clubforge:clubforge "$dir"
	fi
	export CLUBFORGE_IMAGE="$image" CLUBFORGE_VERSION="$version"
fi

# ---- Konfiguration bzw. Wiederherstellung
if [ -n "$restore" ]; then
	log "Backup einspielen (holt .env, Datenbanken und Schlüssel, startet den Stack)"
	run "$dir/deploy/restore.sh" --yes --identity "$identity" "$restore"
	run chown -R clubforge:clubforge "$dir"
fi

log "Konfiguration (.env)"
key_note=""
if [ -n "$restore" ]; then
	echo "kommt aus dem Backup"
elif [ -f "$dir/deploy/.env" ]; then
	echo "$dir/deploy/.env existiert – bleibt unverändert"
else
	if [ -z "$age_recipient" ]; then
		if [ "$dry" = 1 ]; then
			echo "  + age-keygen → Schlüsselpaar für Backups"
			age_recipient="age1-wird-erzeugt"
		else
			# mktemp legt die Datei an; `age-keygen -o` überschreibt keine vorhandene Datei, daher über stdout
			keyfile="$(mktemp)"
			age-keygen >"$keyfile"
			age_recipient="$(age-keygen -y "$keyfile")"
			if [ "$yes" = 0 ] && { : </dev/tty; } 2>/dev/null; then
				echo
				echo "Geheimer Schlüssel für die Backups. Jetzt in den Passwortmanager des Vereins kopieren (zwei Personen)."
				echo "Ohne diesen Schlüssel lassen sich Backups NICHT entschlüsseln; er wird nicht auf dem Server gespeichert."
				echo "------------------------------------------------------------------"
				grep AGE-SECRET-KEY "$keyfile"
				echo "------------------------------------------------------------------"
				read -r -p "Gespeichert? Mit 'ja' fortfahren: " answer </dev/tty
				[ "$answer" = ja ] || { rm -f "$keyfile"; die "Abgebrochen – nichts weiter geändert"; }
				rm -f "$keyfile"
			else
				install -m 600 "$keyfile" /root/clubforge-backup-key.txt
				rm -f "$keyfile"
				key_note="Der geheime Backup-Schlüssel liegt in /root/clubforge-backup-key.txt. Jetzt in den Passwortmanager kopieren und die Datei löschen (check.sh erinnert daran)."
			fi
		fi
	fi
	args=(--public --app "$app" --sync "$sync" --login "$login" --email "$email" --age-recipient "$age_recipient")
	[ -z "$club" ] || args+=(--club "$club")
	[ -z "$smtp_host" ] || args+=(--smtp-host "$smtp_host")
	[ -z "$smtp_port" ] || args+=(--smtp-port "$smtp_port")
	[ -z "$smtp_user" ] || args+=(--smtp-user "$smtp_user")
	[ -z "$smtp_security" ] || args+=(--smtp-security "$smtp_security")
	[ -z "$smtp_from" ] || args+=(--smtp-from "$smtp_from")
	export CF_SMTP_PASSWORD="${CF_SMTP_PASSWORD:-}"
	[ -z "$s3_endpoint" ] || args+=(--s3-endpoint "$s3_endpoint")
	[ -z "$s3_region" ] || args+=(--s3-region "$s3_region")
	[ -z "$s3_bucket" ] || args+=(--s3-bucket "$s3_bucket")
	[ -z "$s3_access_key" ] || args+=(--s3-access-key "$s3_access_key")
	[ -z "$s3_prefix" ] || args+=(--s3-prefix "$s3_prefix")
	export CF_S3_SECRET_KEY="${CF_S3_SECRET_KEY:-}"
	# Logo-Dateien lesbar für den Benutzer clubforge bereitstellen (root-Verzeichnisse wie /root sind es nicht)
	if [ ${#brand_args[@]} -gt 0 ]; then
		brand_tmp="$(mktemp -d)"
		chmod 755 "$brand_tmp"
		i=0
		while [ $i -lt ${#brand_args[@]} ]; do
			case "${brand_args[$i]}" in
			--logo | --logo-light | --favicon)
				v="${brand_args[$((i + 1))]}"
				if [ -f "$v" ]; then
					cp "$v" "$brand_tmp/$(basename "$v")"
					chmod 644 "$brand_tmp/$(basename "$v")"
					brand_args[$((i + 1))]="$brand_tmp/$(basename "$v")"
				fi ;;
			esac
			i=$((i + 2))
		done
		args+=("${brand_args[@]}")
	fi
	as_cf "$dir/deploy/gen-env.sh" "${args[@]}"
	[ -z "$brand_tmp" ] || rm -rf "$brand_tmp"
fi

# ---- Backup-Timer
log "Tägliches Backup (systemd-Timer 03:15)"
write_file /etc/systemd/system/clubforge-backup.service 644 <<EOF
[Unit]
Description=clubforge Backup (verschlüsselt)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=clubforge
ExecStart=$dir/deploy/backup.sh
EOF
write_file /etc/systemd/system/clubforge-backup.timer 644 <<EOF
[Unit]
Description=clubforge Backup täglich

[Timer]
OnCalendar=*-*-* 03:15:00
RandomizedDelaySec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF
run systemctl daemon-reload
run systemctl enable --now clubforge-backup.timer

# ---- Start
if [ -n "$restore" ]; then
	log "Gesundheitsprüfung"
	if [ "$dry" = 1 ]; then echo "  + $dir/deploy/check.sh --wait 600"; else
		runuser -u clubforge -- "$dir/deploy/check.sh" --wait 600 || warn "Die Prüfung meldet Fehler; Hinweise stehen in docs/betrieb/fehlerbehebung.md"
	fi
elif [ "$no_start" = 1 ]; then
	log "Stack wird nicht gestartet (--no-start). Start: cd $dir/deploy && docker compose up -d$([ "$git_mode" = 0 ] || echo ' --build')"
else
	if [ "$git_mode" = 1 ]; then
		log "Stack bauen und starten (der erste Lauf braucht einige Minuten)"
		run runuser -u clubforge -- bash -c "cd '$dir/deploy' && docker compose up -d --build"
	else
		log "Stack starten (Zitadel und PowerSync brauchen beim ersten Start einige Minuten)"
		run runuser -u clubforge -- bash -c "cd '$dir/deploy' && docker compose up -d"
	fi
	log "Gesundheitsprüfung (wartet bis zu 10 Minuten auf Zertifikat und Zitadel)"
	if [ "$dry" = 1 ]; then echo "  + $dir/deploy/check.sh --wait 600"; else
		runuser -u clubforge -- "$dir/deploy/check.sh" --wait 600 || warn "Die Prüfung meldet Fehler; Hinweise stehen in docs/betrieb/fehlerbehebung.md"
	fi
fi

# ---- Erste Admin-Person (wenn angegeben)
admin_done=0
if [ -n "$admin_first" ] && [ -z "$restore" ] && [ "$no_start" = 0 ]; then
	log "Erste Admin-Person anlegen ($admin_email)"
	if [ "$dry" = 1 ]; then
		echo "  + $dir/deploy/admin.sh $admin_email '$admin_first' '$admin_last'"
		admin_done=1
	else
		admin_out="$(mktemp)"
		if runuser -u clubforge -- "$dir/deploy/admin.sh" "$admin_email" "$admin_first" "$admin_last" >"$admin_out" 2>&1; then
			admin_done=1
			if [ "$yes" = 0 ] && { : </dev/tty; } 2>/dev/null; then
				cat "$admin_out"
				rm -f "$admin_out"
			else
				install -m 600 "$admin_out" /root/clubforge-erste-anmeldung.txt
				rm -f "$admin_out"
				key_note="${key_note:+$key_note }Die Zugangsdaten der ersten Admin-Person (Einmalpasswort) stehen in /root/clubforge-erste-anmeldung.txt: weitergeben und die Datei löschen."
			fi
		else
			cat "$admin_out" >&2
			rm -f "$admin_out"
			warn "Die Admin-Person konnte nicht angelegt werden. Später: sudo -u clubforge $dir/deploy/admin.sh $admin_email '$admin_first' '$admin_last'"
		fi
	fi
fi

cat <<EOF

==> Nächste Schritte
$([ "$admin_done" = 1 ] || printf '%s\n%s\n' "  1. Erste Admin-Person anlegen (bei --restore entfällt das, die Konten kommen aus dem Backup):" "       sudo -u clubforge $dir/deploy/admin.sh <e-mail> <vorname> <nachname>")
  2. Anmelden unter https://${app:-<app-adresse>}
  3. Backup-Schlüssel sichern und Restore einmal testen (docs/betrieb/backups.md)
${key_note:+
  HINWEIS: $key_note
}
EOF
