export const alignPhotosToSegments = (photos, segments) => {
  return photos.map((photo) => {
    const match = segments.find(
      (seg) => photo.taken_at_offset_seconds >= seg.start_time_seconds && photo.taken_at_offset_seconds < seg.end_time_seconds
    );
    return {
      ...photo,
      transcript_segment: match || null
    };
  });
};
