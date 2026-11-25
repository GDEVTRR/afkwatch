'use strict';
const { contextBridge, ipcRenderer } = require('electron');

const INVOKE = new Set([
  'state:get', 'bot:save', 'bot:remove', 'bot:start', 'bot:stop', 'bots:startAll', 'bots:stopAll',
  'bot:chat', 'bot:logs', 'bot:clearLogs', 'settings:set', 'cloud:connect', 'cloud:disconnect',
  'cloud:reset', 'pair:create', 'phones:list', 'phones:revoke',
]);
const ON = new Set(['evt:snapshot', 'evt:status', 'evt:log', 'evt:cloud', 'evt:phones', 'evt:paired']);

contextBridge.exposeInMainWorld('api', {
  invoke: (channel, payload) => (INVOKE.has(channel) ? ipcRenderer.invoke(channel, payload) : Promise.reject(new Error('Blocked channel'))),
  on: (channel, cb) => {
    if (!ON.has(channel)) return () => {};
    const h = (_e, data) => cb(data);
    ipcRenderer.on(channel, h);
    return () => ipcRenderer.removeListener(channel, h);
  },
});
