// The window's link to Claude Severance. Inside the app it calls Rust through Tauri; opened as a plain page (for
// design work) it uses sample accounts and changes nothing.
'use strict';

const api = (() => {
  const T = window.__TAURI__;
  if (T) {
    const invoke = T.core.invoke;
    const win = () => T.window.getCurrentWindow();
    return {
      live: true,
      state: () => invoke('state'),
      checkAlias: (alias, id, accounts) => invoke('check_alias', { alias, id, accounts }),
      pickLogo: () => invoke('pick_logo'),
      pickFolder: () => invoke('pick_folder'),
      save: (req) => invoke('save', { req }),
      open: (kind, id) => invoke('open_launcher', { kind, id }),
      onStep: (cb) => T.event.listen('step', (e) => cb(e.payload)),
      minimize: () => win().minimize(),
      close: () => win().close(),
    };
  }

  // ---- sample data for a plain browser ----
  const palette = ['#3E6FA3', '#C08A2E', '#3E7A5A', '#B4442E', '#6C5B9E', '#B5577A', '#2F8A86', '#C46A2B'];
  const L = (appD, appS, tD, tS) => ({ app: { desktop: appD, startMenu: appS }, terminal: { desktop: tD, startMenu: tS } });
  const acct = (id, name, color, alias, email, main, paths, launchers) =>
    ({ id, name, label: name[0], color, logo: '', alias, email, main, paths, launchers });
  let stepCb = () => {};
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  return {
    live: false,
    state: async () => ({
      version: '2.0.0-preview.1',
      sandbox: true,
      palette,
      platformLaunchers: true,
      autoSwitch: true,
      accounts: [
        { account: acct('personal', 'Personal', palette[0], 'claude-personal', 'me@example.com', true, [], L(true, true, false, true)), signIn: { email: 'me@example.com', org: '' }, check: 'ok', logoData: null },
        { account: acct('acme', 'Acme', palette[1], 'acme-cc', 'me@acme.example', false, ['D:\\work\\acme'], L(true, true, true, true)), signIn: { email: 'me@acme.example', org: 'Acme' }, check: 'ok', logoData: null },
        { account: acct('globex', 'Globex', palette[2], 'gx', 'me@globex.example', false, [], L(false, true, false, true)), signIn: { email: 'other@globex.example', org: 'Globex' }, check: 'WRONG ACCOUNT', logoData: null },
        { account: acct('initech', 'Initech', palette[3], '', '', false, ['D:\\work\\initech', 'D:\\clients\\initech-tps'], null), signIn: { email: '', org: '' }, check: '', logoData: null },
      ],
    }),
    checkAlias: async (alias, id, accounts) => {
      const a = alias.trim().toLowerCase();
      if (!a) return 'Give it a command name.';
      if (!/^[a-z0-9][a-z0-9._-]{0,39}$/.test(a)) return `${alias} can't be a command: use letters, digits, dots, dashes or underscores, starting with a letter or digit.`;
      if (['claude', 'dir', 'cd', 'git'].includes(a)) return `${a} is taken by Windows or Claude itself. Pick another name.`;
      if (['ls', 'ac'].includes(a)) return `${a} is already a command on this PC (a PowerShell alias). Pick another name.`;
      const other = accounts.find((o) => o.id !== id && (o.alias || 'claude-' + o.id).toLowerCase() === a);
      return other ? `${a} is already the command for ${other.name}.` : null;
    },
    pickLogo: async () => null,
    pickFolder: async () => 'D:\\work\\new-folder',
    save: async (req) => {
      const steps = ['Copied Claude Severance to your PC', ...req.accounts.map((a) => `Set up ${a.name}`), 'Added the launchers',
        "Added each account's command, and severance", 'Matched Claude Code update settings across accounts', 'Turned on auto-switch for claude',
        'Added Claude Severance to Settings > Apps'];
      for (const s of steps) { await sleep(260); stepCb(s); }
      return { accounts: req.accounts, notes: [] };
    },
    open: async (kind, id) => `Preview: would open the ${kind === 'app' ? 'desktop app' : 'terminal'} for ${id}.`,
    onStep: async (cb) => { stepCb = cb; },
    minimize: () => {},
    close: () => {},
  };
})();
