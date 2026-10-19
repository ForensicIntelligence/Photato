import Foundation

/// A same-origin demonstration client. All image operations execute in the Swift application.
enum AutomationBrowser {
  static func asset(_ path: String) -> AutomationResponse? {
    let asset: (String, String)
    switch path {
    case "/": asset = ("text/html; charset=utf-8", html)
    case "/client.js": asset = ("text/javascript; charset=utf-8", javascript)
    case "/style.css": asset = ("text/css; charset=utf-8", css)
    default: return nil
    }
    return .init(status: 200, contentType: asset.0, body: Data(asset.1.utf8))
  }
  static let html = #"""
    <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Photato · Local Studio</title><link rel="stylesheet" href="/style.css"><script src="/client.js" defer></script></head>
    <body><header><span class="logo">P</span><div><h1>Photato <small>Local Studio</small></h1><p>A browser window into your native editor · API v1 preview</p></div></header>
    <section class="connect"><label>Session token <input id="token" type="password" autocomplete="off" placeholder="Paste from Photato’s API window" size="40"></label><button id="connect">Connect</button><button id="disconnect">Disconnect</button><span id="status" role="status" aria-live="polite">Start the API in Photato, share a document, then paste its token here.</span></section>
    <main><aside><h2>Shared document</h2><select id="documents" aria-label="Shared document"></select><button id="refresh">Refresh from Photato</button><p class="hint">Desktop and browser edits share one history. Refresh after editing on the desktop.</p><div id="editor"><h2>Layers</h2><select id="layers" aria-label="Layer"></select><label>Name <input id="name" maxlength="256"></label><button id="rename">Rename layer</button><label>Opacity <input id="opacity" type="number" min="0" max="100" step="1"></label><button id="applyOpacity">Apply opacity</button><label class="check"><input id="visible" type="checkbox"> Visible</label><div class="row"><label>X <input id="x" type="number" step="1"></label><label>Y <input id="y" type="number" step="1"></label></div><button id="move">Move layer</button><div class="row"><input id="color" aria-label="Fill color" type="color" value="#eaa84a"><button id="fill">Fill pixel layer</button></div><button id="new">New pixel layer</button><div class="row"><button id="undo">Undo</button><button id="redo">Redo</button></div></div></aside><section class="stage"><div id="info">No shared document selected</div><div class="canvas"><img id="preview" alt="Shared document composite" hidden></div><p>Rendered by Swift on your Mac. This client demonstrates ten API commands; it is not the complete Photoshop workspace.</p></section></main>
    <details><summary>API command catalogue</summary><pre id="catalogue">Connect to discover available commands.</pre></details><footer>Local access only · Tokens stay in this page’s memory · Closing Photato or stopping its API disconnects clients</footer></body></html>
    """#
  static let css = #"""
    :root{color-scheme:dark;font:13px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#202124;color:#ececef}*{box-sizing:border-box}body{margin:0}header{display:flex;align-items:center;gap:14px;padding:22px 28px;background:#292a2e;border-bottom:1px solid #444}h1{font-size:22px;margin:0;font-weight:650}h1 small{font-size:17px;color:#abaeb7;font-weight:400;margin-left:10px}p{color:#b8bac2;line-height:1.5}header p{margin:5px 0 0}.logo{display:grid;place-items:center;width:42px;height:42px;background:#dcac70;color:#302315;border-radius:12px;font-size:28px;font-weight:700}.connect{padding:16px 28px;display:flex;align-items:end;gap:12px;flex-wrap:wrap;border-bottom:1px solid #414247}label{display:flex;flex-direction:column;gap:6px;color:#cfd0d7}input,select,button{font:inherit;border:1px solid #55575d;border-radius:5px;background:#303137;color:#eee;padding:8px;min-width:0}button{cursor:pointer;background:#3d4049}button:hover{background:#515663}button:disabled{opacity:.45;cursor:default}#connect{background:#a97c42;color:white}#status{flex:1;min-width:210px;line-height:1.5;padding:5px 0}main{display:grid;grid-template-columns:270px 1fr;min-height:550px}aside{display:flex;flex-direction:column;gap:9px;padding:20px;border-right:1px solid #444}h2{font-size:12px;text-transform:uppercase;letter-spacing:1px;color:#babcc7;margin:4px 0 8px}.hint{font-size:11px;margin:2px 0 12px}#editor{display:flex;flex-direction:column;gap:9px}.row{display:flex;gap:8px}.row>*{flex:1;width:50%}.check{flex-direction:row;align-items:center}.stage{padding:20px;display:flex;flex-direction:column;gap:16px;min-width:0}#info{color:#d0d2d8}.canvas{background:#161719;min-height:400px;flex:1;display:flex;align-items:center;justify-content:center;padding:28px;border-radius:6px;overflow:auto}#preview{max-width:100%;max-height:70vh;object-fit:contain;box-shadow:0 6px 28px #0008;background:repeating-conic-gradient(#bbb 0% 25%,white 0% 50%) 50%/16px 16px}.stage p{font-size:11px;margin:0}details{margin:0 28px 22px;border-top:1px solid #444;padding-top:15px}summary{cursor:pointer}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#161719;padding:20px;border-radius:6px;line-height:1.5}footer{padding:16px 28px;color:#90939e;border-top:1px solid #444;font-size:11px}@media(max-width:680px){main{grid-template-columns:1fr}aside{border-right:0}.canvas{min-height:220px}.connect label{width:100%}.connect input{width:100%}}
    """#
  static let javascript = #"""
    'use strict';
    const $ = id => document.getElementById(id);
    let token = '', current = null, busy = false, imageURL = null;
    function status(text) { $('status').textContent = text; }
    function controls() {
      document.querySelectorAll('#editor input,#editor button,#editor select').forEach(el => el.disabled = busy || !current);
      $('undo').disabled = busy || !current?.canUndo; $('redo').disabled = busy || !current?.canRedo;
      ['connect','disconnect','documents','refresh'].forEach(id => $(id).disabled = busy);
    }
    async function run(action) { if (busy) return; busy = true; controls(); try { await action(); } catch (error) { status(error.message); } finally { busy = false; controls(); } }
    async function api(path, body) {
      const response = await fetch(path, {method: body ? 'POST' : 'GET', headers: {'Authorization': 'Bearer ' + token, ...(body ? {'Content-Type':'application/json'} : {})}, body: body ? JSON.stringify(body) : undefined, cache:'no-store'});
      if (!response.ok) { const error = await response.json(); throw new Error(error.error || 'Request failed'); }
      return response;
    }
    function options(id, values, selected) { const list = $(id); list.replaceChildren(); for(const value of values) { const option=document.createElement('option');option.value=value.id;option.textContent=value.name;list.append(option); } if (values.some(v=>v.id===selected)) list.value=selected; }
    function layer() { const item=current?.layers.find(l=>l.id===$('layers').value);if(!item)return; $('name').value=item.name;$('opacity').value=Math.round(item.opacity*100);$('visible').checked=item.visible;$('x').value=item.x;$('y').value=item.y; }
    async function show(state) { current=state; options('layers',state.layers,$('layers').value || state.activeLayerID);layer();$('info').textContent=state.name+' · '+state.width+' × '+state.height+' · '+state.depth; const response=await api('/v1/documents/'+state.id+'/preview.png');const blob=await response.blob();if(imageURL)URL.revokeObjectURL(imageURL);imageURL=URL.createObjectURL(blob);$('preview').src=imageURL;$('preview').hidden=false;status('Connected · document refreshed'); }
    async function refresh() { const response=await api('/v1/documents');const data=await response.json();options('documents',data.documents,$('documents').value);const selected=data.documents.find(d=>d.id===$('documents').value);if(selected)await show(selected);else { current=null;$('preview').hidden=true;$('info').textContent='No documents shared';status('In Photato, select a document and click Share Current Document.'); } }
    async function command(name,parameters={}) { if(!current)return;const response=await api('/v1/documents/'+current.id+'/commands',{command:name,revision:current.revision,parameters});await show(await response.json()); }
    $('connect').onclick=()=>run(async()=>{token=$('token').value.trim();$('token').value='';const response=await api('/v1/capabilities');const capabilities=await response.json();$('catalogue').textContent=JSON.stringify(capabilities.commands,null,2);await refresh();});
    $('disconnect').onclick=()=>{token='';current=null;$('token').value='';options('documents',[]);options('layers',[]);$('preview').hidden=true;if(imageURL)URL.revokeObjectURL(imageURL);imageURL=null;$('catalogue').textContent='Connect to discover available commands.';$('info').textContent='Disconnected';status('Disconnected');controls();};
    $('refresh').onclick=()=>run(refresh);$('documents').onchange=()=>run(async()=>{const response=await api('/v1/documents/'+$('documents').value);await show(await response.json());});$('layers').onchange=layer;
    const target=()=>({layerID:$('layers').value});
    $('rename').onclick=()=>run(()=>command('layer.rename',{...target(),name:$('name').value}));
    $('applyOpacity').onclick=()=>run(()=>command('layer.opacity',{...target(),opacity:Number($('opacity').value)/100}));
    $('visible').onchange=()=>run(()=>command('layer.visibility',{...target(),visible:$('visible').checked}));
    $('move').onclick=()=>run(()=>command('layer.move',{...target(),x:Number($('x').value),y:Number($('y').value)}));
    $('fill').onclick=()=>run(()=>{const hex=$('color').value;return command('layer.fill',{...target(),r:parseInt(hex.slice(1,3),16)/255,g:parseInt(hex.slice(3,5),16)/255,b:parseInt(hex.slice(5,7),16)/255,a:1});});
    $('new').onclick=()=>run(()=>command('layer.new',{name:'Web layer'}));$('undo').onclick=()=>run(()=>command('history.undo'));$('redo').onclick=()=>run(()=>command('history.redo'));
    controls();
    """#
}
