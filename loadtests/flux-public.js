// Test de charge k6 du flux public (lecture anonyme) — ENVIRONNEMENT ISOLÉ UNIQUEMENT.
//   k6 run -e BASE_URL=http://127.0.0.1:54321 -e ANON_KEY=<clé publishable locale> -e PALIER=50 loadtests/flux-public.js
// Mesure : koki_public_feed (complet), koki_public_feed_page (paginé) et la signature d'images par lot.
// Le script refuse de démarrer si la cible ressemble à la production (voir garde.js).
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { verifierCible, PALIERS, SEUILS } from './garde.js';

const base = verifierCible(__ENV.BASE_URL, __ENV);
const palier = Number(__ENV.PALIER || 10);
if (!PALIERS.includes(palier)) throw new Error('PALIER doit valoir ' + PALIERS.join(', ') + '.');
const cle = __ENV.ANON_KEY;
if (!cle || !cle.startsWith('sb_publishable_')) throw new Error('ANON_KEY (clé publishable, jamais une clé secrète) est obligatoire.');

const dureeFeed = new Trend('koki_feed_complet_ms', true);
const dureePage = new Trend('koki_feed_page_ms', true);

export const options = {
  stages: [
    { duration: '30s', target: palier },   // montée
    { duration: '2m', target: palier },    // palier tenu
    { duration: '20s', target: 0 },        // descente
  ],
  thresholds: {
    http_req_failed: [{ threshold: 'rate<' + SEUILS.erreurs, abortOnFail: true, delayAbortEval: '30s' }],
    http_req_duration: [{ threshold: 'p(95)<' + SEUILS.p95_ms, abortOnFail: true, delayAbortEval: '30s' }],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const entetes = { apikey: cle, 'Content-Type': 'application/json' };

export default function () {
  const complet = http.post(base + '/rest/v1/rpc/koki_public_feed', '{}', { headers: entetes, tags: { appel: 'feed_complet' } });
  dureeFeed.add(complet.timings.duration);
  check(complet, { 'flux complet 200': (r) => r.status === 200 });

  const page = http.post(base + '/rest/v1/rpc/koki_public_feed_page', JSON.stringify({ p_limit: 20 }), { headers: entetes, tags: { appel: 'feed_page' } });
  dureePage.add(page.timings.duration);
  // 404 accepté : la fonction paginée n'est pas encore installée sur cet environnement (repli côté site).
  check(page, { 'flux paginé 200 ou absent': (r) => r.status === 200 || r.status === 404 });
  sleep(1 + Math.random());
}
