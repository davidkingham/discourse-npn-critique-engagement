// Picking a thumbnail and, more importantly, knowing its shape before it
// loads. Core serializes real pixel width/height for every registered size
// (Topic#thumbnail_info), which is what lets a lane reserve the exact box up
// front instead of reflowing once the image arrives.

// Topics whose upload has no stored dimensions, or that exceed
// max_image_size_kb, serialize no thumbnails at all. Those still need a box,
// so they fall back to this rather than collapsing to zero height.
export const FALLBACK_ASPECT = 3 / 2;

export function aspectFor(topic) {
  const original = originalThumbnail(topic);
  if (!original?.width || !original?.height) {
    return FALLBACK_ASPECT;
  }
  return original.width / original.height;
}

// The smallest thumbnail wide enough for the box we're about to draw, at 2x
// for retina. Falls back to the largest available when nothing is big enough.
export function thumbnailFor(topic, targetWidth) {
  const sized = (topic?.thumbnails ?? []).filter(
    (thumb) => thumb.url && thumb.width
  );
  if (sized.length === 0) {
    return null;
  }

  const wanted = targetWidth * 2;
  const ascending = [...sized].sort((a, b) => a.width - b.width);
  return (
    ascending.find((thumb) => thumb.width >= wanted) ??
    ascending[ascending.length - 1]
  );
}

// A topic with no image gets no reserved box at all. An empty grey rectangle
// where a photo should be reads as a broken image, not as "this one is text".
export function hasImage(topic) {
  return (topic?.thumbnails ?? []).some((thumb) => thumb.url);
}

function originalThumbnail(topic) {
  // The original is serialized with null max_width/max_height, and it is the
  // only entry guaranteed to carry the true aspect ratio — optimized sizes
  // are rounded.
  return (topic?.thumbnails ?? []).find(
    (thumb) => thumb.max_width === null && thumb.max_height === null
  );
}

export function clampAspect(aspect, min, max) {
  return Math.min(Math.max(aspect, min), max);
}
