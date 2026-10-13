import '../src/styles.css';
import {saveImageRecord,imagePreview} from '../src/images.js';
// Isolated persistence fixture, never included in the application build.
if(!sessionStorage.getItem('TEST-image-row'))await saveImageRecord({data:{},file:{},content:true,upload:async()=> 'TEST/image.png',persist:async row=>sessionStorage.setItem('TEST-image-row',JSON.stringify(row)),cleanup:async()=>{}});
const row=JSON.parse(sessionStorage.getItem('TEST-image-row'));
imagePreview(document.querySelector('main'),row.image_path,async()=> '/icon-192.png');
