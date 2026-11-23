CREATE TABLE wishlist (
    id_wishlist BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID NOT NULL,
    id_artwork UUID NOT NULL,

    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_wishlist_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE,

    CONSTRAINT fk_wishlist_artwork
    FOREIGN KEY (id_artwork)
    REFERENCES artwork(id_artwork)
    ON DELETE CASCADE,

    CONSTRAINT unq_user_artwork
    UNIQUE (id_user, id_artwork)
);

CREATE INDEX idx_wishlist_artwork ON wishlist(id_artwork);