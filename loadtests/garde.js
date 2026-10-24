// Garde-fou des tests de charge : refuse toute cible qui pourrait être la production.
// Utilisé par les scripts k6 (au démarrage) et testé par tests/charge-garde.test.js.
export const REFERENCES_PRODUCTION = Object.freeze(['qsbmzzbiztfqysstepxm']);
export const HOTES_LOCAUX = Object.freeze(['127.0.0.1', 'localhost', 'host.docker.internal']);

function hoteDe(url) {
  const m = /^(https?):\/\/([^/:?#]+)(?::\d+)?(?:[/?#]|$)/i.exec(String(url || ''));
  return m ? m[2].toLowerCase() : null;
}

// env : { BASE_URL, KOKI_ENV, KOKI_HOTE_TEST } ; retourne l'URL validée ou lève une erreur explicite.
export function verifierCible(url, env = {}) {
  const hote = hoteDe(url);
  if (!hote) throw new Error('Cible invalide ou absente : définissez une URL http(s) complète.');
  for (const ref of REFERENCES_PRODUCTION) {
    if (String(url).toLowerCase().includes(ref)) throw new Error('REFUSÉ : la cible est la production Koki (' + ref + '). Les tests de charge ne visent jamais la production.');
  }
  if (HOTES_LOCAUX.includes(hote)) return String(url).replace(/\/+$/, '');
  // Hôte distant : seulement un environnement de TEST nommé explicitement, jamais un hôte contenant « prod ».
  if (env.KOKI_ENV !== 'TEST' || env.KOKI_HOTE_TEST !== hote) {
    throw new Error('REFUSÉ : hôte distant non autorisé (' + hote + '). Utilisez le Supabase local, ou déclarez KOKI_ENV=TEST et KOKI_HOTE_TEST=' + hote + ' pour un projet de test dédié.');
  }
  if (/prod/i.test(hote)) throw new Error('REFUSÉ : le nom d\'hôte évoque la production (' + hote + ').');
  return String(url).replace(/\/+$/, '');
}

export const PALIERS = Object.freeze([10, 50, 100, 250, 500]);
// Seuils d'arrêt : au-delà, k6 interrompt l'essai (saturation) et le palier suivant n'est pas lancé.
export const SEUILS = Object.freeze({ erreurs: 0.05, p95_ms: 2000 });
