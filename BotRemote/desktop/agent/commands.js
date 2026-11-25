'use strict';
const { validateCommand, fail } = require('./protocol');

/**
 * Executes a remote command. ONLY the whitelisted bot-management actions below exist;
 * there is deliberately no code path to a shell, the filesystem or arbitrary processes.
 */
function createCommandHandler(manager) {
  return async function handle(raw) {
    const v = validateCommand(raw);               // second validation: never trust the relay
    if (!v.ok) return v;
    const c = v.value;
    try {
      switch (c.action) {
        case 'bot.start': return { ok: true, data: manager.start(c.botId) };
        case 'bot.stop': return { ok: true, data: manager.stop(c.botId) };
        case 'bots.startAll': return { ok: true, data: manager.startAll() };
        case 'bots.stopAll': return { ok: true, data: manager.stopAll() };
        case 'bot.chat': return { ok: true, data: manager.chat(c.botId, c.message) };
        case 'bot.logs': return { ok: true, data: { botId: c.botId, logs: manager.logs(c.botId, c.limit) } };
        case 'snapshot': return { ok: true, data: manager.snapshot() };
        default: return fail('UNSUPPORTED_ACTION', 'Unsupported action');
      }
    } catch (e) {
      return fail(e.code || 'ERROR', e.message || 'Command failed');
    }
  };
}
module.exports = { createCommandHandler };
