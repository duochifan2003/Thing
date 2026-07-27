import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { createSaveQueue } from "../app/save-queue.mjs";

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
  assert.match(page, /serviceWorker\?\.getRegistrations/);
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
