import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createCanvas } from "@napi-rs/canvas";
import { layoutWithLines, measureNaturalWidth, prepareWithSegments } from "@chenglou/pretext";

const fixturesDir = new URL("../../../Sources/SiriusMarkdownPretextSupport/Fixtures/", import.meta.url);
const mirrorFixturesDir = new URL("../fixtures/", import.meta.url);
const defaultFont = "16px Helvetica";
const defaultLineHeight = 18;
const tolerance = 0.5;
const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });

if (typeof globalThis.OffscreenCanvas === "undefined") {
  globalThis.OffscreenCanvas = class NodeOffscreenCanvas {
    constructor(width, height) {
      this.canvas = createCanvas(width, height);
    }

    getContext(kind) {
      return this.canvas.getContext(kind);
    }
  };
}

function loadFixtures() {
  return readdirSync(fixturesDir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => {
      const file = join(fixturesDir.pathname, name);
      return { name, fixture: JSON.parse(readFileSync(file, "utf8")) };
    });
}

function main() {
  const entries = loadFixtures();
  const shouldCheck = process.argv.includes("--check");
  const shouldUpdate = process.argv.includes("--update");

  if (shouldCheck && entries.length === 0) {
    throw new Error("No Pretext fixtures found.");
  }

  for (const entry of entries) {
    const fixture = entry.fixture;
    const expected = expectedLayout(fixture);

    if (shouldUpdate) {
      fixture.expected = expected;
      writeFixture(entry.name, fixture, fixturesDir);
      writeFixture(entry.name, fixture, mirrorFixturesDir);
    }

    if (shouldCheck) {
      assertExpectedMatches(fixture.name, fixture.expected, expected);
      assertMirrorMatches(entry.name, fixture);
    }

    console.log(`${fixture.name}: ${expected.lineCount} lines, ${expected.naturalWidth.toFixed(2)}px natural`);
  }
}

function expectedLayout(fixture) {
  const oracleText = fixture.oracleText ?? fixture.markdown;
  const prepared = prepareWithSegments(oracleText, fixture.font ?? defaultFont, {
      whiteSpace: fixture.whiteSpace ?? "pre-wrap",
      wordBreak: fixture.wordBreak ?? "normal",
      letterSpacing: fixture.letterSpacing ?? 0
  });
  const laidOut = layoutWithLines(
    prepared,
    fixture.containerWidth,
    fixture.lineHeight ?? defaultLineHeight
  );
  const offsets = segmentByteOffsets(prepared.segments);

  return {
    lineCount: laidOut.lineCount,
    naturalWidth: round(measureNaturalWidth(prepared)),
    height: round(laidOut.height),
    segments: prepared.segments.map((segment, index) => ({
      text: segment,
      kind: prepared.kinds[index],
      width: round(prepared.widths[index]),
      byteRange: {
        lowerBound: offsets[index],
        upperBound: offsets[index + 1]
      }
    })),
    lines: laidOut.lines.map((line) => ({
      text: line.text,
      width: round(line.width),
      byteRange: {
        lowerBound: cursorByteOffset(prepared.segments, offsets, line.start),
        upperBound: cursorByteOffset(prepared.segments, offsets, line.end)
      },
      start: line.start,
      end: line.end
    }))
  };
}

function writeFixture(name, fixture, directory) {
  const file = join(directory.pathname, name);
  writeFileSync(file, `${JSON.stringify(fixture, null, 2)}\n`);
}

function assertExpectedMatches(name, expected, actual) {
  assertClose(name, "lineCount", expected.lineCount, actual.lineCount, 0);
  assertClose(name, "naturalWidth", expected.naturalWidth, actual.naturalWidth, tolerance);
  assertClose(name, "height", expected.height, actual.height, tolerance);
  assertArrayLength(name, "segments", expected.segments, actual.segments);
  assertArrayLength(name, "lines", expected.lines, actual.lines);

  for (let index = 0; index < actual.segments.length; index++) {
    assertEqual(name, `segments[${index}].text`, expected.segments[index].text, actual.segments[index].text);
    assertEqual(name, `segments[${index}].kind`, expected.segments[index].kind, actual.segments[index].kind);
    assertClose(name, `segments[${index}].width`, expected.segments[index].width, actual.segments[index].width, tolerance);
    assertEqual(name, `segments[${index}].byteRange.lowerBound`, expected.segments[index].byteRange.lowerBound, actual.segments[index].byteRange.lowerBound);
    assertEqual(name, `segments[${index}].byteRange.upperBound`, expected.segments[index].byteRange.upperBound, actual.segments[index].byteRange.upperBound);
  }

  for (let index = 0; index < actual.lines.length; index++) {
    assertEqual(name, `lines[${index}].text`, expected.lines[index].text, actual.lines[index].text);
    assertClose(name, `lines[${index}].width`, expected.lines[index].width, actual.lines[index].width, tolerance);
    assertEqual(name, `lines[${index}].byteRange.lowerBound`, expected.lines[index].byteRange.lowerBound, actual.lines[index].byteRange.lowerBound);
    assertEqual(name, `lines[${index}].byteRange.upperBound`, expected.lines[index].byteRange.upperBound, actual.lines[index].byteRange.upperBound);
    assertEqual(name, `lines[${index}].start.segmentIndex`, expected.lines[index].start.segmentIndex, actual.lines[index].start.segmentIndex);
    assertEqual(name, `lines[${index}].start.graphemeIndex`, expected.lines[index].start.graphemeIndex, actual.lines[index].start.graphemeIndex);
    assertEqual(name, `lines[${index}].end.segmentIndex`, expected.lines[index].end.segmentIndex, actual.lines[index].end.segmentIndex);
    assertEqual(name, `lines[${index}].end.graphemeIndex`, expected.lines[index].end.graphemeIndex, actual.lines[index].end.graphemeIndex);
  }
}

function assertMirrorMatches(name, fixture) {
  const mirrorFile = join(mirrorFixturesDir.pathname, name);
  const mirror = JSON.parse(readFileSync(mirrorFile, "utf8"));
  if (JSON.stringify(mirror) !== JSON.stringify(fixture)) {
    throw new Error(`${name} differs between Swift resources and Tools/pretext-golden/fixtures`);
  }
}

function assertArrayLength(name, field, expected, actual) {
  if (!Array.isArray(expected)) {
    throw new Error(`${name}.${field} is missing from the fixture; run node src/index.js --update`);
  }
  if (expected.length !== actual.length) {
    throw new Error(`${name}.${field} expected ${expected.length} entries, got ${actual.length}`);
  }
}

function assertClose(name, field, expected, actual, fieldTolerance) {
  if (Math.abs(expected - actual) > fieldTolerance) {
    throw new Error(`${name}.${field} expected ${expected}, got ${actual}`);
  }
}

function assertEqual(name, field, expected, actual) {
  if (expected !== actual) {
    throw new Error(`${name}.${field} expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function segmentByteOffsets(segments) {
  const offsets = [0];
  for (const segment of segments) {
    offsets.push(offsets[offsets.length - 1] + byteLength(segment));
  }
  return offsets;
}

function cursorByteOffset(segments, offsets, cursor) {
  if (cursor.segmentIndex >= segments.length) {
    return offsets[offsets.length - 1];
  }

  const segment = segments[cursor.segmentIndex] ?? "";
  const graphemes = Array.from(segmenter.segment(segment), entry => entry.segment);
  const prefix = graphemes.slice(0, cursor.graphemeIndex).join("");
  return offsets[cursor.segmentIndex] + byteLength(prefix);
}

function byteLength(text) {
  return Buffer.byteLength(text, "utf8");
}

function round(value) {
  return Math.round(value * 100) / 100;
}

main();
