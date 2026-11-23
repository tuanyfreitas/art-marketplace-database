CREATE TABLE terms_of_use (
    id_terms BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    version VARCHAR(20) NOT NULL UNIQUE,

    content TEXT NOT NULL,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    active BOOLEAN DEFAULT TRUE
);

-- apenas 1 ativo
CREATE UNIQUE INDEX idx_terms_single_active
ON terms_of_use(active)
WHERE active = TRUE;




CREATE TABLE privacy_policy (
    id_policy BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    version VARCHAR(20) NOT NULL UNIQUE,

    content TEXT NOT NULL,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    active BOOLEAN DEFAULT TRUE
);

-- apenas 1 ativo
CREATE UNIQUE INDEX idx_policy_single_active
ON privacy_policy(active)
WHERE active = TRUE;




CREATE TABLE terms_acceptance (
    id_acceptance BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID NOT NULL,
    id_terms BIGINT NOT NULL,

    accepted_at TIMESTAMPTZ DEFAULT NOW(),

    ip_origin INET,
    user_agent TEXT,

    CONSTRAINT fk_terms_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE,

    CONSTRAINT fk_terms_terms
        FOREIGN KEY (id_terms)
        REFERENCES terms_of_use(id_terms)
        ON DELETE CASCADE,

    -- evita duplicidade
    CONSTRAINT uq_user_terms
        UNIQUE (id_user, id_terms)
);

CREATE INDEX idx_terms_acceptance_user ON terms_acceptance(id_user);







CREATE TABLE privacy_policy_acceptance (
    id_acceptance BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID NOT NULL,
    id_policy BIGINT NOT NULL,

    accepted_at TIMESTAMPTZ DEFAULT NOW(),

    ip_origin INET,
    user_agent TEXT,

    CONSTRAINT fk_privacy_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE,

    CONSTRAINT fk_privacy_policy
        FOREIGN KEY (id_policy)
        REFERENCES privacy_policy(id_policy)
        ON DELETE CASCADE,

    -- evita duplicidade
    CONSTRAINT uq_user_policy
        UNIQUE (id_user, id_policy)
);

CREATE INDEX idx_privacy_acceptance_user ON privacy_policy_acceptance(id_user);
