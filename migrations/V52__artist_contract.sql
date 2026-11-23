CREATE TABLE artist_contract (
    id_contract UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_artist UUID NOT NULL,

    contract_version INT NOT NULL,
    contract_text TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_artist_contract_artist
        FOREIGN KEY (id_artist)
        REFERENCES artist(id_artist)
        ON DELETE CASCADE,

    CONSTRAINT uq_artist_contract_version
        UNIQUE (id_artist, contract_version)
);