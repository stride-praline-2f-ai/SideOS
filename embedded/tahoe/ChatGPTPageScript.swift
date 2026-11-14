import Foundation

/// Isolated-world DOM adapter: no cookies, tokens, message text or draft text
/// cross the native bridge. The website continues to own every conversation.
enum TahoeChatGPTPageScript {
    static let source = #"""
(() => {
  'use strict';
  if (window.top !== window || location.protocol !== 'https:' || location.hostname !== 'chatgpt.com' || window.__sideosChat) return;
  const owned = 'data-sideos-chat-owned';
  const documentToken = crypto.randomUUID ? crypto.randomUUID() : String(Math.random());
  let config = { enabled: true, items: [], role: 'primary', revealed: false };
  let row, menu, mount, headerBranch, composer, observer, timer, discovery;
  let layoutMode = '', layoutMount = null, geometryFrame = null;
  let modified = new Map(), lastStatus = '', lastLayout = '', lastWidth = 0;
  let disposed = false, lastFocus = null;
  const send = (type, extra = {}) => {
    try { window.webkit.messageHandlers.sideosChat.postMessage({ type, ...extra }); } catch (_) {}
  };
  const route = value => {
    try {
      const u = new URL(value, location.href);
      if (u.protocol !== 'https:' || u.hostname !== 'chatgpt.com' || (u.port && u.port !== '443') || u.username || u.password) return null;
      return /^\/(?:c\/[\w-]+|g\/[\w-]+(?:\/c\/[\w-]+)?)?\/?$/.test(u.pathname) ? u : null;
    } catch (_) { return null; }
  };
  const visible = el => !!el && el.getBoundingClientRect().width > 0 && el.getBoundingClientRect().height > 0;
  const own = el => { el.setAttribute(owned, ''); return el; };
  const button = (label, text, action) => {
    const b = own(document.createElement('button'));
    b.type = 'button'; b.title = label; b.setAttribute('aria-label', label); b.textContent = text;
    b.addEventListener('click', e => { e.stopPropagation(); action(e); }); return b;
  };
  const preserve = (el, prop, value) => {
    if (!modified.has(el)) modified.set(el, new Map());
    if (!modified.get(el).has(prop)) modified.get(el).set(prop, [el.style.getPropertyValue(prop), el.style.getPropertyPriority(prop)]);
    if (el.style.getPropertyValue(prop) !== value) el.style.setProperty(prop, value, 'important');
  };
  function restore() {
    for (const [el, props] of modified) for (const [prop, [value, priority]] of props) {
      if (value) el.style.setProperty(prop, value, priority); else el.style.removeProperty(prop);
    }
    modified.clear();
  }
  function landmarks() {
    composer = document.querySelector('#prompt-textarea, [data-testid="composer-text-input"], main [contenteditable="true"][role="textbox"], main textarea');
    const main = document.querySelector('main');
    const header = main?.querySelector('header, [data-testid="conversation-header"], #page-header') || document.querySelector('#page-header, header');
    const headerVisible=visible(header) || (headerBranch && modified.has(headerBranch) && headerBranch.contains(header));
    if (!main || !composer || !header || !visible(main) || !headerVisible) return false;
    let common = header.parentElement;
    while (common && common !== document.body && !common.contains(composer)) common = common.parentElement;
    if (!common || common === document.body) return false;
    let branch = header;
    while (branch.parentElement !== common) branch = branch.parentElement;
    if (branch.contains(composer)) return false;
    mount = common; headerBranch = branch; return true;
  }
  const css = `
  [data-sideos-chat-row] { display:flex; align-items:center; gap:2px; flex:0 0 38px; height:38px; min-height:38px; width:100%; box-sizing:border-box; padding:0 10px; color:inherit; background:var(--main-surface-primary,inherit); border-bottom:1px solid var(--border-light,rgba(127,127,127,.18)); font:inherit; position:sticky; top:0; z-index:30; }
  [data-sideos-chat-list] { display:flex; align-self:stretch; overflow:auto; scrollbar-width:none; flex:1 1 auto; min-width:0; gap:2px; }
  [data-sideos-chat-item] { position:relative; flex:1 1 190px; max-width:280px; min-width:120px; display:flex; align-items:center; border-radius:7px 7px 0 0; }
  [data-sideos-chat-discovery] { appearance:none; font:inherit; font-size:13px; padding:6px 10px; margin-inline:6px; border:1px solid var(--border-light,#8884); border-radius:8px; background:var(--main-surface-secondary,transparent); color:inherit; cursor:pointer; }
  [data-sideos-chat-item][data-visible="true"] { background:var(--main-surface-secondary,rgba(127,127,127,.06)); }
  [data-sideos-chat-item][data-focused="true"]::after { content:""; position:absolute; left:10px; right:10px; bottom:0; height:2px; border-radius:2px; background:currentColor; opacity:.8; pointer-events:none; }
  [data-sideos-chat-row] button { appearance:none; border:0; background:transparent; color:inherit; font:inherit; cursor:pointer; border-radius:6px; line-height:1.2; }
  [data-sideos-chat-tab] { text-align:start; flex:1; min-width:0; height:100%; padding:0 8px 0 10px; font-size:13px!important; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; opacity:.7; }
  [data-sideos-chat-tab][aria-selected="true"] { opacity:1; }
  [data-sideos-chat-controls] { display:flex; opacity:0; }
  [data-sideos-chat-item]:hover [data-sideos-chat-controls], [data-sideos-chat-item]:focus-within [data-sideos-chat-controls], [data-sideos-chat-item][data-focused="true"] [data-sideos-chat-controls] { opacity:1; }
  [data-sideos-chat-controls] button { width:24px; height:30px; padding:0; }
  [data-sideos-chat-row]>button { flex:0 0 30px; height:30px; font-size:17px; }
  [data-sideos-chat-row] button:hover, [data-sideos-chat-menu] button:hover { background:var(--main-surface-tertiary,rgba(127,127,127,.12)); }
  [data-sideos-chat-row] button:focus-visible, [data-sideos-chat-menu] button:focus-visible { outline:2px solid currentColor; outline-offset:-2px; }
  [data-sideos-chat-menu] { position:fixed; z-index:2147483646; min-width:220px; max-width:min(340px,calc(100vw - 24px)); max-height:50vh; overflow:auto; padding:5px; border-radius:12px; font:inherit; font-size:13px; color:var(--text-primary,inherit); background:var(--main-surface-primary,#fff); border:1px solid var(--border-light,rgba(127,127,127,.25)); box-shadow:0 8px 24px #0002; }
  [data-sideos-chat-menu] button { display:block; text-align:start; width:100%; padding:9px 10px; color:inherit; background:transparent; border:0; border-radius:7px; font:inherit; cursor:pointer; }
  [data-sideos-chat-menu] input { box-sizing:border-box; width:100%; padding:8px; margin-bottom:4px; color:inherit; background:transparent; border:1px solid var(--border-light,#8885); border-radius:7px; font:inherit; }
  [data-sideos-chat-item][data-generating="true"] [data-sideos-chat-tab]::before { content:'• '; }
  [data-sideos-chat-divider] { position:fixed; width:6px; z-index:40; cursor:col-resize; touch-action:none; background:var(--border-light,rgba(127,127,127,.15)); }
  @media (prefers-color-scheme:dark) { [data-sideos-chat-menu] { background:var(--main-surface-primary,#212121); color:var(--text-primary,#ececec); } }
  @media (pointer:coarse) { [data-sideos-chat-row] { flex-basis:44px; height:44px; min-height:44px; } [data-sideos-chat-controls] button { height:44px; width:44px; } [data-sideos-chat-row]>button { flex-basis:44px; height:44px; width:44px; } }
  @media (prefers-reduced-motion:no-preference) { [data-sideos-chat-item] { transition:background-color .12s ease; } }
  `;
  let style = own(document.createElement('style')); style.textContent = css;
  (document.head || document.documentElement).append(style);
  function closeMenu() { if (menu) { menu.remove(); menu = null; lastFocus?.focus(); } }
  function openMenu(anchor, item, all = false) {
    closeMenu(); lastFocus = anchor;
    menu = own(document.createElement('div')); menu.setAttribute('data-sideos-chat-menu',''); menu.setAttribute('role','menu');
    const add = (label, action) => { const b=button(label,label,()=>{closeMenu();action();}); b.setAttribute('role','menuitem'); menu.append(b); };
    if (all) {
      const input=own(document.createElement('input')); input.type='search'; input.placeholder='Find an open chat'; input.setAttribute('aria-label','Find an open chat'); menu.append(input);
      for (const chat of config.items) add(chat.title,()=>send('select',{id:chat.id}));
      input.addEventListener('input',()=>{for (const b of menu.querySelectorAll('button')) b.hidden=!b.textContent.toLowerCase().includes(input.value.toLowerCase());});
      if (config.canReopen) add('Reopen closed chat',()=>send('reopen'));
    } else {
      if (item.id!==config.focused && lastWidth>=760) add('View beside current chat',()=>send('split',{id:item.id}));
      add('Move to new window',()=>send('detach',{id:item.id}));
      add('Close tab',()=>send('close',{id:item.id}));
    }
    menu.addEventListener('keydown',e=>{if(!['ArrowDown','ArrowUp'].includes(e.key))return;e.preventDefault();const buttons=[...menu.querySelectorAll('button')].filter(b=>!b.hidden);if(!buttons.length)return;const i=buttons.indexOf(document.activeElement);buttons[(i+(e.key==='ArrowDown'?1:-1)+buttons.length)%buttons.length].focus();});
    document.body.append(menu);
    const r=anchor.getBoundingClientRect(); menu.style.left=Math.max(8,Math.min(r.left,window.innerWidth-menu.offsetWidth-8))+'px'; menu.style.top=Math.max(8,Math.min(r.bottom+4,window.innerHeight-menu.offsetHeight-8))+'px';
    (menu.querySelector('input,button'))?.focus();
  }
  function render() {
    if (disposed || !config.enabled || config.role==='secondary') { row?.remove(); row=null; discovery?.remove();discovery=null;return; }
    if (!config.revealed) {
      row?.remove();row=null;
      if(!discovery?.isConnected){discovery=button('Open ChatGPT chat tabs','Chats',()=>send('reveal'));discovery.setAttribute('data-sideos-chat-discovery','');headerBranch.append(discovery);}
      discovery.textContent='Chats '+Math.max(1,config.items.length);return;
    }
    discovery?.remove();discovery=null;
    const key=JSON.stringify([config.items,config.left,config.right,config.focused,config.canReopen]);
    if (row?.isConnected && row.dataset.render===key) return;
    const oldFocus=document.activeElement?.dataset?.chatFocus;
    closeMenu(); row?.remove();
    row=own(document.createElement('div')); row.setAttribute('data-sideos-chat-row',''); row.dataset.render=key; row.setAttribute('aria-label','Chat workspace');
    const list=own(document.createElement('div')); list.setAttribute('data-sideos-chat-list',''); list.setAttribute('role','tablist'); list.setAttribute('aria-label','Open ChatGPT conversations'); list.addEventListener('scroll',schedule,{passive:true}); row.append(list);
    for (const chat of config.items) {
      const item=own(document.createElement('div')); item.setAttribute('data-sideos-chat-item',''); item.dataset.chatId=chat.id; item.dataset.visible=String(chat.id===config.left || chat.id===config.right); item.dataset.focused=String(chat.id===config.focused); item.dataset.generating=String(chat.generating);
      const tab=button(chat.title,chat.title,()=>send('select',{id:chat.id})); tab.setAttribute('data-sideos-chat-tab',''); tab.setAttribute('role','tab'); tab.setAttribute('aria-selected',String(chat.id===config.focused)); tab.tabIndex=chat.id===config.focused?0:-1; tab.dataset.chatFocus=chat.id;
      if (chat.id===config.left || chat.id===config.right) tab.setAttribute('aria-description',chat.id===config.right?'Visible in right pane':'Visible in left pane');
      tab.addEventListener('keydown',e=>{
        const tabs=[...list.querySelectorAll('[role=tab]')]; const i=tabs.indexOf(tab); let n;
        const rtl=getComputedStyle(list).direction==='rtl';
        if(e.key==='ArrowRight')n=(i+(rtl?-1:1)+tabs.length)%tabs.length;else if(e.key==='ArrowLeft')n=(i+(rtl?1:-1)+tabs.length)%tabs.length;else if(e.key==='Home')n=0;else if(e.key==='End')n=tabs.length-1;else return;
        e.preventDefault(); tabs[n].focus(); send('select',{id:tabs[n].dataset.chatFocus});
      });
      item.addEventListener('contextmenu',e=>{e.preventDefault();openMenu(tab,chat);});
      const controls=own(document.createElement('span')); controls.setAttribute('data-sideos-chat-controls','');
      controls.append(button('Options for '+chat.title,'⋯',e=>openMenu(e.currentTarget,chat)),button('Close '+chat.title,'×',()=>send('close',{id:chat.id})));
      item.append(tab,controls); list.append(item);
    }
    row.append(button('New chat tab','+',()=>send('new')));
    const overflow=button('Open chats','⌄',e=>openMenu(e.currentTarget,null,true));overflow.style.marginInlineStart='auto';row.append(overflow);
    if(config.right){row.append(button('Swap chat panes','⇄',()=>send('swap')));row.append(button('Exit split view','▣',()=>send('collapse')));}
    headerBranch.insertAdjacentElement('afterend',row);
    if(oldFocus) [...row.querySelectorAll('[data-chat-focus]')].find(el=>el.dataset.chatFocus===oldFocus)?.focus();
    if(config.focused!==config.right) [...row.querySelectorAll('[data-chat-focus]')].find(el=>el.dataset.chatFocus===config.focused)?.scrollIntoView?.({block:'nearest',inline:'nearest'});
  }
  let divider;
  function layout() {
    const mode=!config.enabled||!mount?'off':config.role==='secondary'?'secondary':config.right?'split':'single';
    if(mode!==layoutMode || mount!==layoutMount){restore();layoutMode=mode;layoutMount=mount;}
    if(mode==='off') { divider?.remove(); divider=null; return; }
    if(config.role==='secondary') {
      // Keep the secondary document's own composer and message scrolling.
      divider?.remove(); divider=null;
      preserve(headerBranch,'display','none');
      const main=document.querySelector('main');
      for(const el of document.querySelectorAll('[data-testid="sidebar"], #stage-slideover-sidebar, #stage-sidebar, aside')) if(!el.contains(main)&&!el.contains(composer)) preserve(el,'display','none');
      return;
    }
    const rect=mount.getBoundingClientRect(); lastWidth=rect.width;
    const frame=(el,clip)=>{const r=el.getBoundingClientRect();const left=Math.max(r.left,clip?.left??r.left),top=Math.max(r.top,clip?.top??r.top);return {x:left,y:top,width:Math.max(0,Math.min(r.right,clip?.right??r.right)-left),height:Math.max(0,Math.min(r.bottom,clip?.bottom??r.bottom)-top)};};
    const clip=row?.querySelector('[data-sideos-chat-list]').getBoundingClientRect();
    const report={width:rect.width,viewportWidth:innerWidth,rect:null,strip:row?frame(row):null,
      tabs:row?[...row.querySelectorAll('[data-sideos-chat-item]')].map(el=>({id:el.dataset.chatId,...frame(el.querySelector('[role=tab]'),clip)})).filter(r=>r.width>0&&r.height>0):[]};
    if(config.right && row && rect.width>=760) {
      const width=(rect.width-6)*Math.min(.8,Math.max(.2,config.ratio||.5));
      const rtl=getComputedStyle(mount).direction==='rtl';
      const viewport=window.visualViewport;
      const bottom=(viewport?.offsetTop||0)+(viewport?.height||innerHeight);
      const available=Math.max(200,bottom-Math.max(rect.top,viewport?.offsetTop||0));
      // clip bounds painting without creating a second scroll container;
      // overflow:hidden would prevent the sticky row following root scroll.
      preserve(mount,'height',available+'px');preserve(mount,'min-height','0px');preserve(mount,'overflow','clip');
      const roots=[...mount.children].filter(el=>el!==headerBranch&&!el.hasAttribute(owned));
      // No broad selectors into React internals: resize only the already
      // validated layout branches, leaving the header and shared tabs full width.
      for(const el of roots) {preserve(el,'width',width+'px');preserve(el,'max-width',width+'px');preserve(el,'min-height','0px');preserve(el,'margin-inline','0px auto');preserve(el,'align-self','flex-start');}
      const top=row.getBoundingClientRect().bottom;
      report.rect={x:rtl?rect.left:rect.left+width+6,y:top,width:Math.max(0,rect.width-width-6),height:Math.max(0,Math.min(rect.top+available,bottom)-top)};
      if(!divider)divider=own(document.createElement('div'));divider.setAttribute('data-sideos-chat-divider','');divider.setAttribute('role','separator');divider.setAttribute('aria-orientation','vertical');divider.setAttribute('aria-label','Resize chat panes');divider.tabIndex=0;
      for(const [key,value] of Object.entries({left:(rtl?rect.right-width-6:rect.left+width)+'px',top:top+'px',height:report.rect.height+'px'}))if(divider.style[key]!==value)divider.style[key]=value;
      divider.onpointerdown=e=>{divider.setPointerCapture(e.pointerId);};
      divider.onpointermove=e=>{if(e.buttons)send('resize',{ratio:(rtl?rect.right-e.clientX:e.clientX-rect.left)/(rect.width-6),width:rect.width});};
      divider.onkeydown=e=>{if(!['ArrowLeft','ArrowRight'].includes(e.key))return;e.preventDefault();send('resize',{ratio:config.ratio+(e.key==='ArrowRight'?.03:-.03)*(rtl?-1:1),width:rect.width});};
      if(!divider.isConnected)document.body.append(divider);
    } else { divider?.remove(); divider=null; }
    const key=JSON.stringify(report); if(key!==lastLayout){lastLayout=key;send('layout',report);}
  }
  function status(updateLayout=true) {
    const supported=!!route(location.href) && config.enabled && landmarks();
    const draft=composer && ((composer.value||composer.textContent||'').trim().length>0 || !!document.querySelector('[data-testid="composer"] [data-testid*="attachment"], [data-testid="attachment-thumbnail"]'));
    const data={document:documentToken,ready:supported,url:location.href,title:document.title,hasDraft:!!draft,hasContent:!!document.querySelector('main [data-message-author-role], main [data-testid^="conversation-turn-"]'),generating:!!document.querySelector('[data-testid="stop-button"], [data-testid="stop-generation-button"], button[aria-label="Stop generating"]')};
    const key=JSON.stringify(data); if(key!==lastStatus){lastStatus=key;send('status',data);}
    if(!supported){row?.remove();row=null;discovery?.remove();discovery=null;closeMenu();restore();divider?.remove();divider=null;return;}
    if(updateLayout){render();layout();}
  }
  function schedule(){if(timer||disposed)return;timer=setTimeout(()=>{timer=null;status();},120);}
  function geometry(){if(geometryFrame||disposed)return;geometryFrame=requestAnimationFrame(()=>{geometryFrame=null;if(config.enabled&&landmarks())layout();});}
  function intercept(e) {
    if(!config.enabled || !landmarks() || !route(location.href) || e.defaultPrevented || e.button>0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.target.closest('['+owned+']'))return;
    const create=e.target.closest('[data-testid="create-new-chat-button"], [data-testid="new-chat-button"]');
    if(create){e.preventDefault();e.stopImmediatePropagation();send('new');return;}
    const a=e.target.closest('a[href]');if(!a)return;
    const u=route(a.href);if(!u)return;
    const sidebar=a.closest('aside,nav,[data-testid="sidebar"],#stage-slideover-sidebar');
    const isNew=a.getAttribute('data-testid')==='create-new-chat-button' || a.getAttribute('data-testid')==='new-chat-button' || (sidebar && u.pathname==='/');
    if(!isNew && !(sidebar && /\/c\//.test(u.pathname))) return;
    e.preventDefault();e.stopImmediatePropagation();send(isNew?'new':'open',{url:u.href});
  }
  document.addEventListener('click',intercept,true);
  document.addEventListener('click',e=>{if(menu&&!menu.contains(e.target)&&!row?.contains(e.target))closeMenu();},true);
  document.addEventListener('keydown',e=>{if(e.key==='Escape'&&menu){e.preventDefault();e.stopPropagation();closeMenu();}},true);
  const focusPane=e=>{if(!e.target.closest?.('['+owned+'], aside, nav, [data-testid=sidebar], #stage-slideover-sidebar'))send('focus');};
  document.addEventListener('focusin',focusPane);
  document.addEventListener('pointerdown',focusPane,{passive:true});
  const inputStatus=()=>status(false);
  document.addEventListener('input',inputStatus,true);
  window.addEventListener('resize',schedule);window.addEventListener('popstate',schedule);
  window.visualViewport?.addEventListener('resize',schedule);
  window.addEventListener('scroll',geometry,{passive:true});
  document.addEventListener('scroll',geometry,{capture:true,passive:true});
  window.visualViewport?.addEventListener('scroll',geometry,{passive:true});
  observer=new MutationObserver(records=>{if(records.some(r=>!r.target.parentElement?.closest('['+owned+']')&&!r.target.closest?.('['+owned+']')))schedule();});
  observer.observe(document.documentElement,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['class','data-theme']});
  window.__sideosChat={
    configure(next){const previous=JSON.stringify(config);config={...config,...next};if(JSON.stringify(config)===previous)return;lastLayout='';status();},
    inspect(){status();},
    dispose(){disposed=true;clearTimeout(timer);if(geometryFrame)cancelAnimationFrame(geometryFrame);observer.disconnect();row?.remove();discovery?.remove();closeMenu();divider?.remove();restore();style.remove();document.removeEventListener('click',intercept,true);document.removeEventListener('input',inputStatus,true);document.removeEventListener('scroll',geometry,true);window.removeEventListener('scroll',geometry);window.removeEventListener('resize',schedule);window.removeEventListener('popstate',schedule);window.visualViewport?.removeEventListener('resize',schedule);window.visualViewport?.removeEventListener('scroll',geometry);delete window.__sideosChat;}
  };
  status();
})();
"""#
}
