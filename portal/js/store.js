/* Client storage: IndexedDB in the coach's browser only. Nothing is uploaded anywhere. */
const Store = (() => {
  const DB = 'vigor-portal', TABLE = 'clients';
  let memory = new Map();
  let dbPromise = null;

  function open() {
    if (dbPromise) return dbPromise;
    dbPromise = new Promise((resolve) => {
      try {
        const req = indexedDB.open(DB, 1);
        req.onupgradeneeded = () => req.result.createObjectStore(TABLE, { keyPath: 'id' });
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => resolve(null);
      } catch { resolve(null); }
    });
    return dbPromise;
  }

  function run(mode, fn) {
    return open().then(db => new Promise((resolve, reject) => {
      const tx = db.transaction(TABLE, mode);
      const req = fn(tx.objectStore(TABLE));
      tx.oncomplete = () => resolve(req && req.result);
      tx.onerror = () => reject(tx.error);
    }));
  }

  return {
    async list() {
      const db = await open();
      if (!db) return [...memory.values()];
      return run('readonly', s => s.getAll());
    },
    async save(client) {
      const db = await open();
      if (!db) { memory.set(client.id, client); return; }
      await run('readwrite', s => s.put(client));
    },
    async remove(id) {
      const db = await open();
      if (!db) { memory.delete(id); return; }
      await run('readwrite', s => s.delete(id));
    },
  };
})();
