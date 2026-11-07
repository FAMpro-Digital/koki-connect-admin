export const VIDEO_MAX_BYTES = 30 * 1024 * 1024;
export const VIDEO_TYPES = new Set(['video/mp4', 'video/webm']);
const HOSTS = new Set(['youtube.com', 'www.youtube.com', 'youtu.be', 'm.youtube.com']);

export function youtubeId(value) {
  let url;
  try { url = new URL(String(value).trim()); } catch { return null; }
  if (!HOSTS.has(url.hostname.toLowerCase())) return null;
  if (url.hostname === 'youtu.be') return /^[A-Za-z0-9_-]{11}$/.test(url.pathname.slice(1)) ? url.pathname.slice(1) : null;
  if (url.pathname === '/watch') return /^[A-Za-z0-9_-]{11}$/.test(url.searchParams.get('v') || '') ? url.searchParams.get('v') : null;
  const match = url.pathname.match(/^\/(?:embed|shorts)\/([A-Za-z0-9_-]{11})$/);
  return match ? match[1] : null;
}

export function validateVideo({source, file, youtubeUrl}) {
  if (source === 'youtube') {
    const id = youtubeId(youtubeUrl);
    if (!id) throw Error('Lien YouTube invalide.');
    return {source, youtube_video_id: id};
  }
  if (source !== 'upload' || !file) throw Error('Une vidéo est requise.');
  if (!VIDEO_TYPES.has(file.type)) throw Error('Format accepté : MP4 ou WebM.');
  if (file.size > VIDEO_MAX_BYTES) throw Error('La vidéo ne doit pas dépasser 30 Mo.');
  return {source, mime_type: file.type, file_size_bytes: file.size};
}
