// Claude Severance manager: edit accounts and their launchers, then save through the same install steps as the CLI.
'use strict';

const $ = (sel, root = document) => root.querySelector(sel);
const el = {
  list: $('#accounts'), add: $('#add'), save: $('#save'), close: $('#close'), steps: $('#steps'), notes: $('#notes'),
  meta: $('#meta'), bar: $('#progress-bar'), toast: $('#toast'), eyebrow: $('#eyebrow'), title: $('#title'), lede: $('#lede'),
};

const S = {
  info: null,          // what the backend said at load
  accounts: [],        // working copy, in order
  original: '',        // JSON of the accounts as loaded, to know when something changed
  removed: [],         // ids to back up and delete on save
  logoSources: {},     // id -> image file chosen this session
  logoData: {},        // id -> data URL for the tile
  aliasError: {},      // id -> sentence, while a command name can't be used
  aliasPending: {},    // id -> timer
  signIn: {},          // id -> { email, org, check }
  openId: null,
  busy: false,
};

const DEFAULT_LAUNCHERS = () => ({ app: { desktop: true, startMenu: true }, terminal: { desktop: false, startMenu: true } });
const aliasOf = (a) => (a.alias && a.alias.trim() ? a.alias.trim().toLowerCase() : `claude-${a.id}`);
const firstLetter = (name) => ((name.match(/[A-Za-z0-9]/) || ['?'])[0]).toUpperCase();
const isDark = (hex) => {
  const h = (hex || '#888888').replace('#', '');
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) || 136);
  return 0.299 * r + 0.587 * g + 0.114 * b < 150;
};
const slug = (name, taken) => {
  let base = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  if (!base || base === 'auto') base = 'account';
  let id = base, n = 2;
  while (taken.includes(id)) id = `${base}${n++}`;
  return id;
};

// ---------------- loading ----------------
async function load() {
  const info = await api.state();
  S.info = info;
  S.accounts = info.accounts.map((v) => ({ ...v.account, launchers: v.account.launchers || DEFAULT_LAUNCHERS() }));
  S.signIn = Object.fromEntries(info.accounts.map((v) => [v.account.id, { ...v.signIn, check: v.check }]));
  S.logoData = Object.fromEntries(info.accounts.filter((v) => v.logoData).map((v) => [v.account.id, v.logoData]));
  S.original = snapshot();
  S.removed = []; S.logoSources = {}; S.aliasError = {};
  $('#sandbox-tag').hidden = !info.sandbox;
  setMoment('waiting');
  render();
}

const snapshot = () => JSON.stringify({ a: S.accounts, r: S.removed, l: Object.keys(S.logoSources) });
const dirty = () => snapshot() !== S.original;

// ---------------- rendering ----------------
function render() {
  el.list.replaceChildren(...S.accounts.map(rowFor));
  refresh();
}

function rowFor(a) {
  const node = $('#row').content.firstElementChild.cloneNode(true);
  node.dataset.id = a.id;
  const summary = $('.summary', node);
  summary.addEventListener('click', () => toggle(a.id));
  fillSummary(node, a);

  const removed = S.removed.includes(a.id);
  node.classList.toggle('removed', removed);
  const open = S.openId === a.id && !removed;
  node.classList.toggle('open', open);
  summary.setAttribute('aria-expanded', String(open));
  $('.detail', node).hidden = !open;
  if (open) fillDetail(node, a);
  return node;
}

function fillSummary(node, a) {
  paintTile($('.tile', node), a);
  $('.name', node).textContent = a.name || 'New account';
  const si = S.signIn[a.id] || {};
  const email = $('.email', node);
  email.classList.remove('warn');
  if (a.isNew) email.textContent = 'Not saved yet';
  else if (si.check === 'WRONG ACCOUNT') { email.textContent = `Signed in as ${si.email}, not ${a.email}`; email.classList.add('warn'); }
  else email.textContent = si.email ? `${si.email}${si.org ? ' · ' + si.org : ''}` : 'Not signed in yet';
  $('.cmd', node).textContent = aliasOf(a);
  const badge = $('.badge', node);
  badge.textContent = a.main ? 'main' : (S.removed.includes(a.id) ? 'removed' : '');
  badge.classList.toggle('main', !!a.main);
}

function paintTile(tile, a) {
  const logo = S.logoData[a.id];
  tile.classList.toggle('logo', !!logo);
  tile.style.backgroundImage = logo ? `url("${logo}")` : '';
  tile.style.backgroundColor = a.color;
  tile.style.color = isDark(a.color) ? '#fff' : '#000';
  tile.textContent = logo ? '' : firstLetter(a.name || '?');
}

function fillDetail(node, a) {
  const name = $('.f-name', node), email = $('.f-email', node), alias = $('.f-alias', node);
  name.value = a.name; email.value = a.email || ''; alias.value = aliasOf(a);
  name.addEventListener('input', () => {
    a.name = name.value;
    if (a.isNew) {
      const was = a.id;
      a.id = slug(a.name, S.accounts.filter((o) => o !== a).map((o) => o.id));
      if (was !== a.id) { remap(was, a.id); node.dataset.id = a.id; if (!a.aliasTouched) { alias.value = aliasOf(a); checkAlias(a, node); } }
    }
    fillSummary(node, a); refresh();
  });
  email.addEventListener('input', () => { a.email = email.value.trim(); refresh(); });
  alias.addEventListener('input', () => { a.alias = alias.value.trim().toLowerCase(); a.aliasTouched = true; fillSummary(node, a); checkAlias(a, node); refresh(); });
  showAliasHint(node, a);

  // launchers
  for (const box of node.querySelectorAll('.launcher')) {
    const kind = box.dataset.kind;
    // Linux may have no Claude Desktop: then there's no app to launch
    const noApp = kind === 'app' && S.info.hasDesktop === false;
    box.classList.toggle('unavailable', noApp);
    if (noApp) box.title = "Claude Desktop isn't installed on this computer";
    for (const chip of box.querySelectorAll('.chip')) {
      const place = chip.dataset.place;
      if (place === 'startMenu' && S.info.menuName) {
        chip.textContent = S.info.menuName.charAt(0).toUpperCase() + S.info.menuName.slice(1);
      }
      chip.disabled = noApp;
      chip.setAttribute('aria-pressed', String(!noApp && !!a.launchers[kind][place]));
      chip.addEventListener('click', () => {
        a.launchers[kind][place] = !a.launchers[kind][place];
        chip.setAttribute('aria-pressed', String(a.launchers[kind][place]));
        refresh();
      });
    }
    const open = $('.open-now', box);
    open.disabled = !!a.isNew || noApp || !S.info.platformLaunchers;
    open.title = a.isNew ? 'Save first' : '';
    open.addEventListener('click', async () => {
      try { const msg = await api.open(kind, a.id); if (msg) toast(msg); } catch (e) { toast(String(e)); }
    });
  }
  $('.t-desc', node).textContent = `Claude Code, starting in ${a.paths && a.paths[0] ? a.paths[0] : 'your home folder'}`;

  // folders
  const ul = $('.folders', node);
  const drawFolders = () => {
    ul.replaceChildren();
    if (!a.paths.length) { const li = document.createElement('li'); li.className = 'none'; li.textContent = 'None: Claude Code asks which account to use in other folders.'; ul.append(li); }
    a.paths.forEach((p, i) => {
      const li = document.createElement('li');
      const span = document.createElement('span'); span.textContent = p; span.title = p;
      const x = document.createElement('button'); x.textContent = '×'; x.setAttribute('aria-label', `Remove ${p}`);
      x.addEventListener('click', () => { a.paths.splice(i, 1); drawFolders(); $('.t-desc', node).textContent = `Claude Code, starting in ${a.paths[0] || 'your home folder'}`; refresh(); });
      li.append(span, x); ul.append(li);
    });
  };
  drawFolders();
  $('.add-folder', node).addEventListener('click', async () => {
    const p = await api.pickFolder();
    if (p && !a.paths.includes(p)) { a.paths.push(p); drawFolders(); $('.t-desc', node).textContent = `Claude Code, starting in ${a.paths[0]}`; refresh(); }
  });

  // tile
  const sw = $('.swatches', node);
  for (const c of S.info.palette) {
    const b = document.createElement('button');
    b.className = 'swatch'; b.style.background = c; b.setAttribute('aria-label', `Colour ${c}`);
    b.setAttribute('aria-pressed', String(a.color.toLowerCase() === c.toLowerCase()));
    b.addEventListener('click', () => {
      a.color = c;
      sw.querySelectorAll('.swatch').forEach((s) => s.setAttribute('aria-pressed', String(s === b)));
      fillSummary(node, a); refresh();
    });
    sw.append(b);
  }
  const clear = $('.clear-logo', node);
  clear.hidden = !S.logoData[a.id];
  $('.pick-logo', node).addEventListener('click', async () => {
    try {
      const picked = await api.pickLogo();
      if (!picked) return;
      S.logoSources[a.id] = picked.path; S.logoData[a.id] = picked.dataUrl; a.logo = '';
      clear.hidden = false; fillSummary(node, a); refresh();
    } catch (e) { toast(String(e)); }
  });
  clear.addEventListener('click', () => {
    delete S.logoSources[a.id]; delete S.logoData[a.id]; a.logo = '';
    clear.hidden = true; fillSummary(node, a); refresh();
  });

  // remove
  const remove = $('.remove', node);
  remove.hidden = !!a.main;
  $('.main-note', node).hidden = !a.main;
  remove.addEventListener('click', () => removeAccount(a));
  setTimeout(() => (a.isNew ? name : null)?.focus(), 0);
}

function remap(from, to) {
  for (const m of [S.logoSources, S.logoData, S.aliasError, S.signIn]) if (from in m) { m[to] = m[from]; delete m[from]; }
  if (S.openId === from) S.openId = to;
}

function toggle(id) {
  if (S.busy) return;
  if (S.removed.includes(id)) { undoRemove(id); return; }
  S.openId = S.openId === id ? null : id;
  render();
  if (S.openId) $(`.account[data-id="${S.openId}"]`)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}

// ---------------- command names ----------------
function checkAlias(a, node) {
  clearTimeout(S.aliasPending[a.id]);
  S.aliasPending[a.id] = setTimeout(async () => {
    const id = a.id;
    const why = await api.checkAlias(aliasOf(a), id, S.accounts.filter((o) => !S.removed.includes(o.id)).map(plain));
    delete S.aliasPending[id];
    if (why) S.aliasError[id] = why; else delete S.aliasError[id];
    showAliasHint(node, a); refresh();
  }, 320);
}

function showAliasHint(node, a) {
  const hint = $('.f-alias-hint', node), input = $('.f-alias', node);
  if (!hint) return;
  const why = S.aliasError[a.id];
  hint.className = 'hint f-alias-hint' + (why ? ' error' : '');
  hint.textContent = why || `Type ${aliasOf(a)} in any terminal to use Claude Code as ${a.name || 'this account'}.`;
  if (why) input.dataset.error = ''; else delete input.dataset.error;
}

// ---------------- add and remove ----------------
el.add.addEventListener('click', () => {
  if (S.busy) return;
  const used = S.accounts.map((a) => a.color.toLowerCase());
  const color = S.info.palette.find((c) => !used.includes(c.toLowerCase())) || S.info.palette[S.accounts.length % S.info.palette.length];
  const id = slug('New account', S.accounts.map((a) => a.id));
  const a = { id, name: '', label: '', color, logo: '', alias: '', email: '', main: false, paths: [], launchers: DEFAULT_LAUNCHERS(), isNew: true };
  S.accounts.push(a);
  S.openId = id;
  render();
  $(`.account[data-id="${id}"]`)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
});

function removeAccount(a) {
  if (a.isNew) {
    S.accounts = S.accounts.filter((o) => o !== a);
    S.openId = null; render(); return;
  }
  S.removed.push(a.id);
  S.openId = null;
  render();
  toast(`${a.name} will be removed when you save. Its memory and history are zipped first, without its login.`, 'Undo', () => undoRemove(a.id));
}

function undoRemove(id) {
  S.removed = S.removed.filter((r) => r !== id);
  render(); hideToast();
}

// ---------------- footer ----------------
function problems() {
  const live = S.accounts.filter((a) => !S.removed.includes(a.id));
  const out = [];
  const names = live.map((a) => a.name.trim().toLowerCase());
  live.forEach((a, i) => {
    if (!a.name.trim()) out.push('Every account needs a name.');
    else if (names.indexOf(names[i]) !== i) out.push(`Two accounts are called ${a.name}.`);
  });
  if (Object.keys(S.aliasError).some((id) => live.some((a) => a.id === id))) out.push('A command name needs changing.');
  return [...new Set(out)];
}

function refresh() {
  const live = S.accounts.filter((a) => !S.removed.includes(a.id));
  const pending = Object.keys(S.aliasPending).length > 0;
  const issues = problems();
  el.save.disabled = S.busy || !dirty() || issues.length > 0 || pending;
  el.save.title = issues.join(' ');
  const facts = [S.info.version, `${live.length} account${live.length === 1 ? '' : 's'}`, S.info.autoSwitch ? 'auto-switch on' : 'auto-switch off'];
  if (dirty()) facts.push(issues.length ? issues[0] : 'unsaved changes');
  el.meta.textContent = facts.join('  ·  ');
}

// ---------------- saving ----------------
const plain = (a) => {
  const { isNew, aliasTouched, ...rest } = a;
  return { ...rest, alias: aliasOf(a), label: firstLetter(a.name) };
};

el.save.addEventListener('click', async () => {
  if (el.save.disabled) return;
  S.busy = true;
  hideToast();
  const live = S.accounts.filter((a) => !S.removed.includes(a.id));
  const req = {
    accounts: live.map(plain),
    removedIds: S.removed.slice(),
    logoSources: Object.entries(S.logoSources).filter(([id]) => live.some((a) => a.id === id)),
  };
  setMoment(S.removed.length ? 'removing' : 'working');
  copy('Procedure in progress', 'Setting the floors', 'up as you asked.', '');
  el.list.hidden = true; el.add.hidden = true; el.notes.hidden = true;
  el.steps.replaceChildren(); el.steps.hidden = false;
  const total = live.length + 6 + (S.removed.length ? 1 : 0);
  let n = 0;
  await api.onStep((text) => {
    n += 1;
    const row = document.createElement('div');
    const num = document.createElement('span'); num.className = 'n'; num.textContent = String(n).padStart(2, '0');
    const t = document.createElement('span'); t.textContent = text;
    row.append(num, t); el.steps.append(row);
    el.bar.style.width = `${Math.min(96, (n / total) * 100)}%`;
    row.scrollIntoView({ block: 'nearest' });
  });
  refresh();
  try {
    const report = await api.save(req);
    S.original = snapshot();
    el.bar.style.width = '100%';
    setMoment('done');
    copy('Procedure complete', 'Saved.', 'Each account is on its own floor.', 'Open a new terminal to use changed commands.');
    if (report.notes && report.notes.length) { el.notes.textContent = report.notes.join('\n'); el.notes.hidden = false; }
    el.save.textContent = 'Done';
    el.save.disabled = false;
    el.save.onclick = async (e) => {
      e.stopImmediatePropagation();
      el.save.onclick = null; el.save.textContent = 'Save changes';
      await finishBack();
    };
  } catch (e) {
    setMoment('removing');
    copy('Procedure stopped', 'Nothing more', 'was changed.', '');
    el.notes.textContent = String(e); el.notes.hidden = false;
    el.save.textContent = 'Back';
    el.save.disabled = false;
    el.save.onclick = (ev) => {
      ev.stopImmediatePropagation();
      el.save.onclick = null; el.save.textContent = 'Save changes';
      S.busy = false; showEditor(); refresh();
    };
  }
});

async function finishBack() {
  S.busy = false;
  el.bar.style.width = '0';
  await load();
  showEditor();
}

function showEditor() {
  el.steps.hidden = true; el.notes.hidden = true; el.list.hidden = false; el.add.hidden = false;
  el.bar.style.width = '0';
  setMoment('waiting');
  copy('Assignments', 'Each account', 'on its own floor.', "Add, rename or remove accounts, and choose where each one's launchers go: one opens Claude Desktop, the other a terminal with its Claude Code.");
}

function copy(eyebrow, one, two, lede) {
  el.eyebrow.textContent = eyebrow;
  el.title.children[0].textContent = one;
  el.title.children[1].textContent = two;
  el.lede.textContent = lede;
  el.lede.hidden = !lede;
}

function setMoment(m) { document.body.dataset.moment = m; }

// ---------------- toast, window ----------------
let toastTimer;
function toast(text, action, fn) {
  el.toast.replaceChildren(document.createTextNode(text));
  if (action) {
    const b = document.createElement('button'); b.textContent = action;
    b.addEventListener('click', () => { fn(); hideToast(); });
    el.toast.append(b);
  }
  el.toast.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(hideToast, action ? 9000 : 4500);
}
function hideToast() { el.toast.hidden = true; }

function tryClose() {
  if (S.busy && el.save.textContent !== 'Done') return;
  if (dirty() && !S.busy) {
    toast('You have unsaved changes.', 'Close anyway', () => api.close());
    return;
  }
  api.close();
}
el.close.addEventListener('click', tryClose);
$('#win-close').addEventListener('click', tryClose);
$('#win-min').addEventListener('click', () => api.minimize());
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (!el.toast.hidden) hideToast();
    else if (S.openId && !S.busy) { S.openId = null; render(); }
  }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') { e.preventDefault(); el.save.click(); }
});

load().catch((e) => {
  setMoment('removing');
  copy('Out of order', "Claude Severance", "couldn't read your accounts.", String(e));
  el.add.hidden = true;
});
