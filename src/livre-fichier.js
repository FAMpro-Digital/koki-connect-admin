// Fichiers de la Bibliothèque : vérification du vrai format (octets de début), pas seulement du nom.
export const LIVRE_MAX_OCTETS=50*1024*1024;
export const extensions=Object.freeze({'application/pdf':'pdf','application/epub+zip':'epub','audio/mpeg':'mp3','audio/mp4':'m4a'});
export async function formatLivre(file){
 const h=new Uint8Array(await file.slice(0,64).arrayBuffer()),txt=String.fromCharCode(...h);
 if(txt.startsWith('%PDF-'))return 'application/pdf';
 if(h[0]===0x50&&h[1]===0x4b&&h[2]===0x03&&h[3]===0x04&&txt.includes('mimetypeapplication/epub+zip'))return 'application/epub+zip';
 if(txt.startsWith('ID3')||(h[0]===0xff&&(h[1]&0xe0)===0xe0))return 'audio/mpeg';
 if(txt.slice(4,8)==='ftyp'&&/^(M4A |M4B |mp42|isom)/.test(txt.slice(8,12)))return 'audio/mp4';
 return null;
}
export async function verifierLivre(file){
 if(!file||!file.size)throw Error('Fichier vide.');
 if(file.size>LIVRE_MAX_OCTETS)throw Error('Fichier trop lourd (50 Mo maximum).');
 const type=await formatLivre(file);if(!type)throw Error('Format refusé : PDF, EPUB, MP3 ou M4A uniquement.');
 return {type,ext:extensions[type],taille_mo:Math.max(0.1,Math.round(file.size/1048576*10)/10)};
}
// Format du contrat déduit du fichier envoyé.
export function formatContrat(type,actuel){if(type==='application/pdf')return actuel==='Audio + PDF'?actuel:'PDF';if(type==='application/epub+zip')return 'EPUB';return actuel==='Audio + PDF'?actuel:'Audio';}
