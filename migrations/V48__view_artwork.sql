CREATE OR REPLACE VIEW public_artwork AS
SELECT
    a.id_artwork,
    a.id_user,
    a.title,
    a.slug,
    a.description,
    a.price,
    a.product_type,
    a.height_cm,
    a.width_cm,
    a.depth_cm,
    a.weight_kg,
    a.materials,
    a.published_at,
    ai.image_url AS primary_image
FROM artwork a
LEFT JOIN artwork_image ai
    ON ai.id_artwork = a.id_artwork
    AND ai.is_primary = TRUE
WHERE
    a.curation_status = 'approved'
    AND a.visibility = 'public'
    AND a.artwork_status = 'available'
    AND a.published_at IS NOT NULL
ORDER BY a.published_at DESC;