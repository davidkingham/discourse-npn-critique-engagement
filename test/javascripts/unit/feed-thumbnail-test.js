import { module, test } from "qunit";
import {
  aspectFor,
  clampAspect,
  FALLBACK_ASPECT,
  thumbnailFor,
} from "discourse/plugins/discourse-npn-critique-engagement/discourse/lib/feed-thumbnail";

// The box a lane reserves is derived entirely from these three functions. If
// they get the shape wrong the page reflows as images load, and if the clamp
// is wrong a member's photo gets cropped — the one thing NPN won't do.
function topicWith(thumbnails) {
  return { thumbnails };
}

const ORIGINAL = {
  max_width: null,
  max_height: null,
  width: 3000,
  height: 2000,
  url: "/o.jpg",
};

module("Unit | NPN Critique Engagement | feed thumbnails", function () {
  test("takes the aspect ratio from the original, not a rounded thumbnail", function (assert) {
    const topic = topicWith([
      {
        max_width: 400,
        max_height: 400,
        width: 400,
        height: 267,
        url: "/s.jpg",
      },
      ORIGINAL,
    ]);

    assert.strictEqual(aspectFor(topic), 1.5);
  });

  test("falls back to a sane shape when the topic has no thumbnails", function (assert) {
    assert.strictEqual(aspectFor(topicWith([])), FALLBACK_ASPECT);
    assert.strictEqual(aspectFor({}), FALLBACK_ASPECT);
  });

  test("falls back when dimensions are missing, rather than reserving nothing", function (assert) {
    const topic = topicWith([
      { max_width: null, max_height: null, url: "/o.jpg" },
    ]);

    assert.strictEqual(aspectFor(topic), FALLBACK_ASPECT);
  });

  test("picks the smallest thumbnail that still covers the box at 2x", function (assert) {
    const topic = topicWith([
      {
        max_width: 400,
        max_height: 400,
        width: 400,
        height: 267,
        url: "/400.jpg",
      },
      {
        max_width: 800,
        max_height: 800,
        width: 800,
        height: 533,
        url: "/800.jpg",
      },
      {
        max_width: 1200,
        max_height: 1200,
        width: 1200,
        height: 800,
        url: "/1200.jpg",
      },
      ORIGINAL,
    ]);

    assert.strictEqual(thumbnailFor(topic, 300).url, "/800.jpg");
    assert.strictEqual(thumbnailFor(topic, 500).url, "/1200.jpg");
  });

  test("uses the largest available when nothing is big enough", function (assert) {
    const topic = topicWith([
      {
        max_width: 400,
        max_height: 400,
        width: 400,
        height: 267,
        url: "/400.jpg",
      },
    ]);

    assert.strictEqual(thumbnailFor(topic, 2000).url, "/400.jpg");
  });

  test("returns nothing when a topic carries no image at all", function (assert) {
    assert.strictEqual(thumbnailFor(topicWith([]), 400), null);
  });

  test("clamps a panorama and a tall portrait, leaving ordinary frames alone", function (assert) {
    // Past the clamp the image is letterboxed inside the clamped box. That
    // is contained, never cropped.
    assert.strictEqual(clampAspect(4, 0.55, 3), 3, "panorama clamped");
    assert.strictEqual(clampAspect(0.4, 0.55, 3), 0.55, "portrait clamped");
    assert.strictEqual(clampAspect(1.5, 0.55, 3), 1.5, "3:2 untouched");
  });
});
