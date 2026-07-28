const settingsKey = "person-event-webdav";
const text = new TextEncoder();

function encode(value) {
  let binary = "";
  new Uint8Array(value).forEach((byte) => { binary += String.fromCharCode(byte); });
  return btoa(binary);
}

function decode(value) {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

async function keyFor(passphrase, salt) {
  const material = await crypto.subtle.importKey("raw", text.encode(passphrase), "PBKDF2", false, ["deriveKey"]);
  return crypto.subtle.deriveKey({ name: "PBKDF2", hash: "SHA-256", iterations: 210000, salt }, material, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}

function basicAuth(username, password) {
  const bytes = new TextEncoder().encode(`${username}:${password}`);
  let value = "";
  bytes.forEach((byte) => { value += String.fromCharCode(byte); });
  return `Basic ${btoa(value)}`;
}

function headers(settings, password, extra = {}) {
  return { Authorization: basicAuth(settings.username, password), ...extra };
}

export function loadWebDavSettings(storage = localStorage) {
  try {
    const value = JSON.parse(storage.getItem(settingsKey) || "{}");
    return { url: typeof value.url === "string" ? value.url : "", username: typeof value.username === "string" ? value.username : "" };
  } catch {
    return { url: "", username: "" };
  }
}

export function saveWebDavSettings(settings, storage = localStorage) {
  storage.setItem(settingsKey, JSON.stringify({ url: settings.url.trim(), username: settings.username.trim() }));
}

export function isEncryptedArchive(value) {
  return Boolean(value && typeof value === "object" && value.format === "person-event-atlas-encrypted" && value.version === 1 && value.kdf?.salt && value.cipher?.iv && value.cipher?.data);
}

export async function encryptArchive(value, passphrase) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await keyFor(passphrase, salt), text.encode(JSON.stringify(value)));
  return { format: "person-event-atlas-encrypted", version: 1, kdf: { name: "PBKDF2", hash: "SHA-256", iterations: 210000, salt: encode(salt) }, cipher: { name: "AES-GCM", iv: encode(iv), data: encode(encrypted) } };
}

export async function decryptArchive(value, passphrase) {
  if (!isEncryptedArchive(value)) throw new Error("远端文件不是加密档案包");
  try {
    const salt = decode(value.kdf.salt); const iv = decode(value.cipher.iv); const encrypted = decode(value.cipher.data);
    const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, await keyFor(passphrase, salt), encrypted);
    return JSON.parse(new TextDecoder().decode(plain));
  } catch {
    throw new Error("同步加密口令不正确，或远端档案已损坏。");
  }
}

export async function readWebDavArchive(settings, password, request = fetch) {
  const response = await request(settings.url.trim(), { headers: headers(settings, password, { Accept: "application/json" }) });
  if (response.status === 404) return { found: false };
  if (!response.ok) throw new Error(`WebDAV 读取失败（${response.status}）`);
  return { found: true, value: await response.json() };
}

export async function writeWebDavArchive(settings, password, value, request = fetch) {
  const response = await request(settings.url.trim(), { method: "PUT", headers: headers(settings, password, { "Content-Type": "application/json" }), body: JSON.stringify(value, null, 2) });
  if (!response.ok) throw new Error(`WebDAV 写入失败（${response.status}）`);
}
