// Compression des vidéos dans le navigateur avant l'envoi (quota d'envoi Supabase, forfait mobile des visiteurs).
// La vidéo est relue une fois à 720p maximum et réenregistrée en MP4 (H.264) vers 1,2 Mbit/s : comptez la durée
// de la vidéo. Sans enregistreur MP4 (certains navigateurs), ou si le résultat n'est pas plus léger, l'original est
// envoyé tel quel : un fichier WebM ne serait pas lu sur tous les iPhone.
export const SEUIL_COMPRESSION = 4 * 1024 * 1024;
export const HAUTEUR_MAX = 720;
export const DEBIT_VIDEO = 1_200_000;
export const DEBIT_AUDIO = 96_000;
// Son AAC exigé : un MP4 avec son Opus (ce que choisit Chrome pour « video/mp4 » seul) n'est pas lu partout sur iPhone.
const TYPES_MP4 = ['video/mp4;codecs=avc1.42E01E,mp4a.40.2', 'video/mp4;codecs=avc1.4D401F,mp4a.40.2', 'video/mp4;codecs=avc1,mp4a.40.2', 'video/mp4;codecs=avc1,mp4a'];
// Safari enregistre « video/mp4 » en H.264 + AAC.
const estSafari = ua => /Safari\//.test(ua) && !/Chrome|Chromium|CriOS|Edg|OPR|Android/.test(ua);

export function typeMp4(Recorder = globalThis.MediaRecorder, ua = globalThis.navigator?.userAgent || '') {
  if (!Recorder || typeof Recorder.isTypeSupported !== 'function') return null;
  const ok = t => { try { return Recorder.isTypeSupported(t); } catch { return false; } };
  return TYPES_MP4.find(ok) || (estSafari(ua) && ok('video/mp4') ? 'video/mp4' : null);
}
// Dimensions paires (exigées par H.264), sans agrandir une vidéo déjà petite.
export function dimensions(largeur, hauteur, max = HAUTEUR_MAX) {
  if (!(largeur > 0 && hauteur > 0)) return null;
  const petit = Math.min(largeur, hauteur), echelle = petit > max ? max / petit : 1;
  const pair = v => Math.max(2, Math.round(v * echelle / 2) * 2);
  return {largeur: pair(largeur), hauteur: pair(hauteur)};
}
export function doitCompresser(file, Recorder = globalThis.MediaRecorder) {
  return !!file && file.size > SEUIL_COMPRESSION && !!typeMp4(Recorder) && typeof document !== 'undefined';
}

// Renvoie {file, compresse, avant, apres}. onProgress(0..1) pendant la relecture.
export async function compresserVideo(file, {onProgress = () => {}, Recorder = globalThis.MediaRecorder, doc = globalThis.document} = {}) {
  const avant = file.size;
  if (!doitCompresser(file, Recorder)) return {file, compresse: false, avant, apres: avant};
  const mime = typeMp4(Recorder), url = URL.createObjectURL(file);
  const video = doc.createElement('video');
  video.src = url; video.playsInline = true; video.preload = 'auto';
  let audio = null;
  try {
    await new Promise((ok, ko) => { video.onloadedmetadata = ok; video.onerror = () => ko(Error('Vidéo illisible par le navigateur.')); });
    const taille = dimensions(video.videoWidth, video.videoHeight);
    if (!taille) return {file, compresse: false, avant, apres: avant};
    const canvas = doc.createElement('canvas'); canvas.width = taille.largeur; canvas.height = taille.hauteur;
    const ctx = canvas.getContext('2d');
    const flux = canvas.captureStream(30);
    // Le son passe par Web Audio : capté pour l'enregistrement, sans sortir sur les haut-parleurs.
    try {
      const AC = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (AC) { audio = new AC(); const source = audio.createMediaElementSource(video), sortie = audio.createMediaStreamDestination(); source.connect(sortie); for (const piste of sortie.stream.getAudioTracks()) flux.addTrack(piste); }
    } catch { /* vidéo sans son ou navigateur sans Web Audio : image seule */ }
    const morceaux = [], rec = new Recorder(flux, {mimeType: mime, videoBitsPerSecond: DEBIT_VIDEO, audioBitsPerSecond: DEBIT_AUDIO});
    rec.ondataavailable = e => { if (e.data && e.data.size) morceaux.push(e.data); };
    const fini = new Promise((ok, ko) => { rec.onstop = ok; rec.onerror = () => ko(Error('Compression interrompue.')); });
    let actif = true;
    const dessiner = () => { if (!actif) return; ctx.drawImage(video, 0, 0, taille.largeur, taille.hauteur); if (video.duration) onProgress(Math.min(1, video.currentTime / video.duration)); requestAnimationFrame(dessiner); };
    rec.start(1000);
    await video.play();
    dessiner();
    await new Promise(ok => { video.onended = ok; });
    actif = false; rec.stop(); await fini; onProgress(1);
    const resultat = new Blob(morceaux, {type: 'video/mp4'});
    if (!resultat.size || resultat.size >= avant) return {file, compresse: false, avant, apres: avant};
    const nom = String(file.name || 'video').replace(/\.[^.]+$/, '') + '.mp4';
    return {file: new File([resultat], nom, {type: 'video/mp4'}), compresse: true, avant, apres: resultat.size};
  } finally {
    try { video.pause(); } catch { /* déjà arrêtée */ }
    try { await audio?.close(); } catch { /* déjà fermé */ }
    URL.revokeObjectURL(url);
  }
}
export const mo = n => (n / 1048576).toLocaleString('fr-FR', {maximumFractionDigits: 1}) + ' Mo';
// Pour les formulaires : compresse si possible, affiche l'avancement, et garde l'original en cas d'échec.
export async function preparerVideo(file, afficher = () => {}, options = {}) {
  if (!file || !doitCompresser(file, options.Recorder)) return file;
  afficher('Compression de la vidéo avant l’envoi (' + mo(file.size) + ')… gardez cette page ouverte.');
  try {
    const r = await compresserVideo(file, {...options, onProgress: p => afficher('Compression de la vidéo… ' + Math.round(p * 100) + ' %')});
    afficher(r.compresse ? 'Vidéo compressée : ' + mo(r.avant) + ' → ' + mo(r.apres) + '. Envoi en cours…' : 'Vidéo envoyée sans compression (déjà légère).');
    return r.file;
  } catch {
    afficher('Compression impossible dans ce navigateur : la vidéo d’origine est envoyée.');
    return file;
  }
}
