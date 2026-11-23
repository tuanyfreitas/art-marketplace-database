CREATE TABLE curation (
    id_curation BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_curator UUID NOT NULL,
    id_artwork UUID NOT NULL,

    curation_status curation_status_enum NOT NULL,

    comment TEXT NOT NULL DEFAULT ''
    CHECK (comment = '' OR LENGTH(TRIM(comment)) > 0),

    reviewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_curation_curator
        FOREIGN KEY (id_curator)
        REFERENCES user_account(id_user)
        ON DELETE RESTRICT,

    CONSTRAINT fk_curation_artwork
        FOREIGN KEY (id_artwork)
        REFERENCES artwork(id_artwork)
        ON DELETE CASCADE
);

CREATE INDEX idx_curation_curator ON curation(id_curator);
CREATE INDEX idx_curation_status_reviewed_at ON curation(curation_status, reviewed_at DESC);
CREATE INDEX idx_curation_latest ON curation(id_artwork, reviewed_at DESC);