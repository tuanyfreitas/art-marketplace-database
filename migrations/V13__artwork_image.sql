CREATE TABLE artwork_image (
    id_image BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_artwork UUID NOT NULL,

    image_url TEXT NOT NULL
    CHECK (LENGTH(TRIM(image_url)) > 0),

    is_primary BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_artwork_image
        FOREIGN KEY (id_artwork)
        REFERENCES artwork(id_artwork)
        ON DELETE CASCADE
);

CREATE INDEX idx_artwork_image_artwork ON artwork_image(id_artwork);
CREATE UNIQUE INDEX idx_artwork_image_primary 
ON artwork_image(id_artwork)
WHERE is_primary = TRUE; -- impede criar várias imagens principais