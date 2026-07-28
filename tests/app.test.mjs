import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { createSaveQueue } from "../app/save-queue.mjs";
import { decryptArchive, encryptArchive, isEncryptedArchive, readWebDavArchive, writeWebDavArchive } from "../app/webdav-sync.mjs";

const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");
const archiveStore = await readFile(new URL("../app/archive-store.mjs", import.meta.url), "utf8");
const desktopApp = await readFile(new URL("../desktop/PersonEventApp.swift", import.meta.url), "utf8");
const widget = await readFile(new URL("../desktop/Widget/PersonEventWidget.swift", import.meta.url), "utf8");

test("implements the local-first person and event archive flows", () => {
  assert.match(page, /archiveStore\.read\(\)/);
  assert.match(page, /导出 JSON/);
  assert.match(page, /导入预检/);
  assert.match(page, /修订历史/);
  assert.match(page, /时间精度/);
  assert.match(page, /关联人物/);
  assert.match(page, /serviceWorker\?\.register\("\/sw\.js"\)/);
});

test("migrates browser storage into the native shared archive bridge", () => {
  assert.match(archiveStore, /indexedDB\.open\(databaseName, 1\)/);
  assert.match(archiveStore, /nativeRequest\("migrate", legacy\)/);
  assert.match(archiveStore, /nativeRequest\("write", value\)/);
  assert.match(desktopApp, /addScriptMessageHandler\(bridge, contentWorld: \.page, name: "archiveStore"\)/);
  assert.match(desktopApp, /WidgetCenter\.shared\.reloadTimelines/);
});

test("defines the macOS widget families and event deep links", () => {
  assert.match(widget, /\.supportedFamilies\(\[\.systemSmall, \.systemMedium\]\)/);
  assert.match(widget, /person-event-atlas:\/\/event\//);
  assert.match(widget, /events\.prefix\(3\)/);
  assert.match(widget, /未记录地点/);
  assert.match(desktopApp, /desktop-open-event/);
});

test("keeps example data fictional and supports date ranges", () => {
  assert.match(page, /虚构示例人物/);
  assert.match(page, /precision: "range"/);
  assert.match(page, /rangeEnd >= from/);
});

test("serializes saves and continues after a failed write", async () => {
  const calls = [];
  const save = createSaveQueue((value) => new Promise((resolve, reject) => calls.push({ value, resolve, reject })));
  const first = save("first"); const second = save("second");
  await new Promise(setImmediate); assert.deepEqual(calls.map((call) => call.value), ["first"]);
  calls[0].reject(new Error("disk full")); await assert.rejects(first); await new Promise(setImmediate);
  assert.deepEqual(calls.map((call) => call.value), ["first", "second"]);
  calls[1].resolve(); await second;
});

test("reads and writes a WebDAV archive without persisting credentials", async () => {
  const calls = [];
  const request = async (url, options = {}) => { calls.push({ url, options }); return new Response(options.method === "PUT" ? null : JSON.stringify({ version: 1 }), { status: 200 }); };
  const settings = { url: "https://dav.example/archive.json", username: "owner" };
  assert.deepEqual(await readWebDavArchive(settings, "secret", request), { found: true, value: { version: 1 } });
  await writeWebDavArchive(settings, "secret", { version: 1 }, request);
  assert.equal(calls[1].options.method, "PUT");
  assert.equal(calls[1].options.body, '{\n  "version": 1\n}');
  assert.match(calls[0].options.headers.Authorization, /^Basic /);
});

test("encrypts a remote archive with a separate sync passphrase", async () => {
  const archive = { version: 1, people: [{ name: "林岚" }] };
  const encrypted = await encryptArchive(archive, "a long separate passphrase");
  assert.equal(isEncryptedArchive(encrypted), true);
  assert.notEqual(encrypted.cipher.data, JSON.stringify(archive));
  assert.deepEqual(await decryptArchive(encrypted, "a long separate passphrase"), archive);
  await assert.rejects(() => decryptArchive(encrypted, "wrong passphrase"));
});
