const databaseName = "person-event-atlas";

function nativeBridge() {
  return globalThis.webkit?.messageHandlers?.archiveStore;
}

async function nativeRequest(action, value) {
  const result = await nativeBridge().postMessage({ action, value });
  if (!result?.ok) throw new Error(result?.error || "无法访问共享档案库");
  return result;
}

async function openDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(databaseName, 1);
    request.onupgradeneeded = () => request.result.createObjectStore("store");
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function readIndexedDb() {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const request = db.transaction("store", "readonly").objectStore("store").get("data");
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function writeIndexedDb(value) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction("store", "readwrite");
    const request = transaction.objectStore("store").put(value, "data");
    transaction.oncomplete = () => resolve();
    transaction.onerror = transaction.onabort = () => reject(transaction.error || request.error);
  });
}

export const archiveStore = {
  isNative: () => Boolean(nativeBridge()),

  async read() {
    if (!nativeBridge()) return readIndexedDb();
    const shared = await nativeRequest("read");
    if (shared.exists) return shared.value;

    // Preserve existing browser data by importing it once before the native store becomes authoritative.
    const legacy = await readIndexedDb();
    if (legacy !== undefined) await nativeRequest("migrate", legacy);
    return legacy;
  },

  async write(value) {
    if (nativeBridge()) {
      await nativeRequest("write", value);
      return;
    }
    await writeIndexedDb(value);
  },
};
