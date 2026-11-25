'use strict';
/** Fixed-capacity ring buffer: console memory per bot is bounded no matter how long a bot runs. */
class LogBuffer {
  constructor(capacity = 500) { this.cap = capacity; this.items = new Array(capacity); this.start = 0; this.size = 0; }
  push(entry) {
    if (this.size < this.cap) { this.items[(this.start + this.size) % this.cap] = entry; this.size++; }
    else { this.items[this.start] = entry; this.start = (this.start + 1) % this.cap; }
  }
  last(n = this.size) {
    const count = Math.min(n, this.size); const out = new Array(count);
    for (let i = 0; i < count; i++) out[i] = this.items[(this.start + this.size - count + i) % this.cap];
    return out;
  }
  clear() { this.items = new Array(this.cap); this.start = 0; this.size = 0; }
}
module.exports = { LogBuffer };
