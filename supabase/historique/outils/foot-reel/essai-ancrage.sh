#!/usr/bin/env bash
# Essai de bout en bout de l'ancrage Ed25519 contre le Supabase LOCAL éphémère (jamais la production) :
# lecture réelle par la RPC koki_foot_sync avec la clé serveur LOCALE, reçus signés, série vérifiée,
# puis deux attaques par un superutilisateur : réécriture complète de la chaîne (recalculée en base) et
# troncature. Les deux doivent être détectées par le reçu suivant.
set -euo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"; RACINE="$(cd "$ICI/../../../.." && pwd)"
: "${KOKI_ESSAI_ENV:?}"; set -a; . "$KOKI_ESSAI_ENV.supabase"; set +a
[ "$API_URL" = "http://127.0.0.1:54321" ] || { echo "REFUS : Supabase local uniquement" >&2; exit 2; }
DB=postgresql://supabase_admin:postgres@127.0.0.1:54322/postgres
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; umask 077
A="node $RACINE/scripts/ancrage-journal.mjs"
export KOKI_SUPABASE_URL="$API_URL" KOKI_SERVICE_KEY="$SERVICE_ROLE_KEY" KOKI_ANCRAGE_CLE="$T/cle.pem"
node -e "const {generateKeyPairSync}=require('crypto');const k=generateKeyPairSync('ed25519');const fs=require('fs');
fs.writeFileSync('$T/cle.pem',k.privateKey.export({type:'pkcs8',format:'pem'}));const pub=k.publicKey.export({type:'spki',format:'pem'});
const id=require('crypto').createHash('sha256').update(k.publicKey.export({type:'spki',format:'der'})).digest('hex').slice(0,16);
fs.writeFileSync('$T/trousseau.json',JSON.stringify({cles:[{id,publique:pub,valide_du:'2026-01-01T00:00:00Z',valide_au:null}]}));"
ok(){ echo "ok      $*"; }
$A lire > "$T/r1.json"; ok "reçu 1 : $(node -e "const r=require('$T/r1.json');console.log('ligne '+r.dernier_id+', '+r.lignes+' lignes, clé '+r.cle)")"
sleep 1; $A lire "$T/r1.json" > "$T/r2.json"; ok "reçu 2 chaîné au reçu 1 (contrôle de continuité relu en base)"
$A suite "$T/trousseau.json" "$T/r1.json" "$T/r2.json" >/dev/null || { echo "ÉCHEC : série invalide"; exit 1; }; ok "série de 2 reçus valide (signature, clé, chaîne, continuité, absence de secrets)"
grep -qiE "PRIVATE|eyJ|sb_secret|service_role" "$T/r1.json" "$T/r2.json" && { echo "ÉCHEC : secret dans un reçu"; exit 1; } || ok "aucun secret dans les reçus"

echo "── Attaque 1 : réécriture d'une ligne ancienne PUIS recalcul complet de la chaîne en base"
psql "$DB" -X -q -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
alter table koki_foot.corrections disable trigger user;
update koki_foot.corrections set motif='MOTIF FALSIFIÉ (essai d''attaque)' where id=(select min(id) from koki_foot.corrections);
do $$ declare c koki_foot.corrections; prec text:=null; begin
 for c in select * from koki_foot.corrections order by id loop
  update koki_foot.corrections set precedente=prec, empreinte=encode(sha256(convert_to(coalesce(prec,'')||'|'||koki_foot.corrections_contenu(c),'UTF8')),'hex') where id=c.id returning empreinte into prec;
 end loop; end $$;
alter table koki_foot.corrections enable trigger user;
SQL
v=$(psql "$DB" -X -Atc "select koki_foot.verifier_journal()"); ok "verifier_journal() en base après l'attaque : ${v:-aucune altération signalée (le contrôle interne est trompé)}"
if $A lire "$T/r2.json" > "$T/r3.json" 2> "$T/err.txt"; then echo "ÉCHEC : réécriture non détectée"; exit 1; fi
grep -q "RÉÉCRITE" "$T/err.txt" || { echo "ÉCHEC : message inattendu : $(cat "$T/err.txt")"; exit 1; }; ok "réécriture DÉTECTÉE par l'ancrage : $(cat "$T/err.txt")"

echo "── Attaque 2 : troncature (suppression de la dernière ligne)"
$A lire > "$T/n1.json"
psql "$DB" -X -q -v ON_ERROR_STOP=1 -c "alter table koki_foot.corrections disable trigger user; delete from koki_foot.corrections where id=(select max(id) from koki_foot.corrections); alter table koki_foot.corrections enable trigger user" >/dev/null
v=$(psql "$DB" -X -Atc "select koki_foot.verifier_journal()"); ok "verifier_journal() en base après troncature : ${v:-aucune altération signalée}"
if $A lire "$T/n1.json" > "$T/n2.json" 2> "$T/err.txt"; then echo "ÉCHEC : troncature non détectée"; exit 1; fi
grep -q "TRONQUÉ" "$T/err.txt" || { echo "ÉCHEC : message inattendu : $(cat "$T/err.txt")"; exit 1; }; ok "troncature DÉTECTÉE par l'ancrage : $(cat "$T/err.txt")"
echo "TERMINÉ : ancrage vérifié de bout en bout (2 attaques détectées)."
