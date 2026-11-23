CREATE OR REPLACE VIEW admin_artwork_listing AS
SELECT
    a.id_artwork,
    a.title,
    a.slug,
    a.price,
    a.product_type,
    a.artwork_status,
    a.curation_status,
    a.visibility,
    a.published_at,
    a.created_at,
    a.updated_at,
    (a.published_at IS NOT NULL) AS is_published,
    u.id_user,
    u.name,
    u.surname,
    (u.name || ' ' || u.surname) AS author_full_name,
    u.email AS author_email
FROM artwork a
JOIN user_account u
    ON u.id_user = a.id_user;