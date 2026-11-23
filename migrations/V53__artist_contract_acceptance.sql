CREATE TABLE artist_contract_acceptance (
    id_acceptance UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_artist UUID NOT NULL,
    id_contract UUID NOT NULL,

    accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_origin INET NOT NULL,

    CONSTRAINT fk_acceptance_artist
        FOREIGN KEY (id_artist)
        REFERENCES artist(id_artist)
        ON DELETE CASCADE,

    CONSTRAINT fk_acceptance_contract
        FOREIGN KEY (id_contract)
        REFERENCES artist_contract(id_contract)
        ON DELETE CASCADE
);