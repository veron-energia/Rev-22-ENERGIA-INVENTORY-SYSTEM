// L13 (security audit of 17 Nov 2026): what a survey attachment and a store
// image may be. SVG is refused in both; a store image is PNG, JPEG or WebP up
// to 5 MB; survey documents and the 10 MB limit are as before.
//
// Run: node --test scripts/survey/tests/upload-rules-l13.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { ACCEPT, MAX_BYTES, attachmentType, isImage } from '../../../src/lib/survey/attachmentRules.mjs';
import {
  STORE_ASSET_ACCEPT, STORE_ASSET_MAX_BYTES, storeAssetType, storeAssetExtension, storeAssetRefusal,
} from '../../../src/lib/storeAssetRules.mjs';

test('survey attachments: the picker lists explicit image types, not image/*', () => {
  assert.ok(!ACCEPT.split(',').includes('image/*'));
  for (const t of ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif', '.jpg', '.jpeg', '.heif']) {
    assert.ok(ACCEPT.split(',').includes(t), t);
  }
  assert.ok(!ACCEPT.includes('svg'));
  assert.equal(MAX_BYTES, 10 * 1024 * 1024);
});

test('survey attachments: listed images and the documents are taken', () => {
  for (const [name, type] of [['a.jpg', 'image/jpeg'], ['a.png', 'image/png'], ['a.gif', 'image/gif'], ['a.webp', 'image/webp'], ['a.heic', 'image/heic'], ['a.heif', 'image/heif'],
    ['a.pdf', 'application/pdf'], ['a.csv', 'text/csv'], ['a.txt', 'text/plain'], ['a.doc', 'application/msword']]) {
    assert.equal(attachmentType({ name, type }), type, name);
  }
  // A phone that gives no type: the name decides.
  assert.equal(attachmentType({ name: 'IMG_0001.HEIC', type: '' }), 'image/heic');
  assert.equal(attachmentType({ name: 'photo.jpeg' }), 'image/jpeg');
  assert.equal(isImage('image/png'), true);
});

test('survey attachments: SVG and any image type not listed are refused', () => {
  assert.equal(attachmentType({ name: 'a.svg', type: 'image/svg+xml' }), null);
  assert.equal(attachmentType({ name: 'a.svg', type: '' }), null);
  assert.equal(attachmentType({ name: 'a.png', type: 'image/svg+xml' }), null);
  for (const type of ['image/bmp', 'image/tiff', 'image/x-icon', 'image/avif']) {
    assert.equal(attachmentType({ name: 'a.img', type }), null, type);
  }
  assert.equal(attachmentType({ name: 'a.exe', type: 'application/octet-stream' }), null);
  assert.equal(attachmentType({ name: 'noext', type: '' }), null);
});

test('store images: only PNG, JPEG or WebP, up to 5 MB', () => {
  assert.equal(STORE_ASSET_MAX_BYTES, 5 * 1024 * 1024);
  assert.ok(!STORE_ASSET_ACCEPT.includes('image/*') && !STORE_ASSET_ACCEPT.includes('svg'));
  for (const [name, type, ext] of [['logo.png', 'image/png', 'png'], ['logo.jpg', 'image/jpeg', 'jpg'], ['logo.webp', 'image/webp', 'webp']]) {
    assert.equal(storeAssetType({ name, type }), type);
    assert.equal(storeAssetExtension(type), ext);
    assert.equal(storeAssetRefusal({ name, type, size: STORE_ASSET_MAX_BYTES }), null);
  }
  assert.equal(storeAssetType({ name: 'qr.PNG', type: '' }), 'image/png');
});

test('store images: SVG, other types and big files are refused with a plain sentence', () => {
  const svg = storeAssetRefusal({ name: 'logo.svg', type: 'image/svg+xml', size: 100 });
  assert.match(svg, /Only PNG, JPEG or WebP/);
  assert.match(storeAssetRefusal({ name: 'a.gif', type: 'image/gif', size: 100 }), /Only PNG, JPEG or WebP/);
  assert.match(storeAssetRefusal({ name: 'a.pdf', type: 'application/pdf', size: 100 }), /Only PNG, JPEG or WebP/);
  assert.match(storeAssetRefusal({ name: 'a.png', type: 'image/png', size: STORE_ASSET_MAX_BYTES + 1 }), /larger than 5 MB/);
  assert.equal(storeAssetType({ name: 'a.png', type: 'image/svg+xml' }), null);
});
