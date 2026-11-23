CREATE TABLE artwork_view_log (
    id_view BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_artwork UUID NOT NULL,
    id_user UUID,
    session_id UUID,
    viewed_at TIMESTAMPTZ DEFAULT NOW(),
    ip_origin INET,
    user_agent TEXT,

    CONSTRAINT fk_view_artwork
        FOREIGN KEY (id_artwork)
        REFERENCES artwork(id_artwork)
        ON DELETE CASCADE,

    CONSTRAINT fk_view_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE SET NULL
);

-- principal: analytics por obra
CREATE INDEX idx_view_artwork_time ON artwork_view_log(id_artwork, viewed_at DESC);

-- usuário (histórico)
CREATE INDEX idx_view_user_time ON artwork_view_log(id_user, viewed_at DESC);

-- CORREÇÃO: Espaço adicionado entre o nome do índice e o ON
CREATE INDEX idx_view_session ON artwork_view_log(session_id);

-- filtro por tempo (dashboards)
CREATE INDEX idx_viewed_at ON artwork_view_log(viewed_at DESC);

-- spam
CREATE INDEX idx_view_dedup ON artwork_view_log(id_artwork, session_id, viewed_at);