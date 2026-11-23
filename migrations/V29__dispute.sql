CREATE TABLE dispute (
    id_dispute BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_order BIGINT NOT NULL,
    id_user UUID NOT NULL,

    reason TEXT NOT NULL
    CHECK (LENGTH(TRIM(reason)) > 0),

    status dispute_status_enum NOT NULL DEFAULT 'open',

    resolution_note TEXT
    CHECK (LENGTH(TRIM(resolution_note)) > 0),

    resolved_by UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,

    created_by UUID NOT NULL,

    CONSTRAINT fk_dispute_created_by
    FOREIGN KEY (created_by)
    REFERENCES user_account(id_user)
    ON DELETE RESTRICT,

    CONSTRAINT fk_dispute_order
    FOREIGN KEY (id_order)
    REFERENCES customer_order(id_order)
    ON DELETE RESTRICT,

    CONSTRAINT fk_dispute_user
    FOREIGN KEY (id_user)
    REFERENCES user_account(id_user)
    ON DELETE RESTRICT,

    CONSTRAINT chk_dispute_dates
        CHECK (
            resolved_at IS NULL OR resolved_at >= created_at
        ),
    
    CONSTRAINT fk_dispute_resolved_by
    FOREIGN KEY (resolved_by)
    REFERENCES user_account(id_user)
    ON DELETE RESTRICT);

    -- Permite apenas uma disputa ativa por usuário e pedido
    CREATE UNIQUE INDEX uq_dispute_active_user_order
    ON dispute(id_order, id_user)
    WHERE status IN ('open', 'in_review');
     
     
-- Índices
CREATE INDEX idx_dispute_order ON dispute(id_order);
CREATE INDEX idx_dispute_user ON dispute(id_user);
CREATE INDEX idx_dispute_status ON dispute(status);
CREATE INDEX idx_dispute_created_at ON dispute(created_at);



-- Atualiza automaticamente a data de modificação
CREATE TRIGGER trg_dispute_updated_at
BEFORE UPDATE ON dispute
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

-- Valida a participação do usuário no pedido
CREATE OR REPLACE FUNCTION validate_dispute_user()
RETURNS TRIGGER AS $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM customer_order
        WHERE id_order = NEW.id_order
          AND id_buyer = NEW.id_user
    )
    AND NOT EXISTS (
        SELECT 1
        FROM customer_order_item
        WHERE id_order = NEW.id_order
          AND id_seller = NEW.id_user
    ) THEN

        RAISE EXCEPTION
            'O usuário não possui vínculo com o pedido informado';

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_dispute_user
BEFORE INSERT OR UPDATE OF id_order, id_user ON dispute
FOR EACH ROW
EXECUTE FUNCTION validate_dispute_user();

-- Valida quem pode registrar a disputa
CREATE OR REPLACE FUNCTION validate_dispute_creator()
RETURNS TRIGGER AS $$
BEGIN

    IF NEW.created_by = NEW.id_user THEN
        RETURN NEW;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM user_role ur
        INNER JOIN role r
            ON r.id_role = ur.id_role
        WHERE ur.id_user = NEW.created_by
          AND r.role_name IN ('ADMIN', 'SUPPORT')
    ) THEN

        RAISE EXCEPTION
            'O usuário não possui permissão para registrar esta disputa';

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_dispute_creator
BEFORE INSERT OR UPDATE OF created_by, id_user ON dispute
FOR EACH ROW
EXECUTE FUNCTION validate_dispute_creator();

-- Define as transições permitidas de disputa
CREATE TABLE dispute_status_transition (
    old_status dispute_status_enum NOT NULL,
    new_status dispute_status_enum NOT NULL,

    PRIMARY KEY (old_status, new_status),

    CONSTRAINT chk_dispute_status_transition
        CHECK (old_status <> new_status)
);

INSERT INTO dispute_status_transition (old_status, new_status)
VALUES
    ('open', 'in_review'),
    ('open', 'canceled'),
    ('in_review', 'resolved'),
    ('in_review', 'rejected'),
    ('in_review', 'canceled');


-- Valida as transições de status da disputa
CREATE OR REPLACE FUNCTION validate_dispute_status_transition()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        IF NEW.status IS DISTINCT FROM 'open' THEN
            RAISE EXCEPTION
                'O status inicial da disputa deve ser open';
        END IF;

        RETURN NEW;

    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN

        IF NOT EXISTS (
            SELECT 1
            FROM dispute_status_transition
            WHERE old_status = OLD.status
              AND new_status = NEW.status
        ) THEN
            RAISE EXCEPTION
                'Transição de status de disputa inválida: % -> %',
                OLD.status,
                NEW.status;
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_dispute_status_transition
BEFORE INSERT OR UPDATE OF status ON dispute
FOR EACH ROW
EXECUTE FUNCTION validate_dispute_status_transition();


-- Controla a data de encerramento da disputa
CREATE OR REPLACE FUNCTION manage_dispute_resolved_at()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN
        NEW.resolved_at := NULL;

    ELSIF OLD.resolved_at IS NOT NULL THEN
        NEW.resolved_at := OLD.resolved_at;

    ELSIF NEW.status IN ('resolved', 'rejected', 'canceled') THEN
        NEW.resolved_at := NOW();

    ELSE
        NEW.resolved_at := NULL;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_manage_dispute_resolved_at
BEFORE INSERT OR UPDATE ON dispute
FOR EACH ROW
EXECUTE FUNCTION manage_dispute_resolved_at();

-- Protege os dados originais da disputa
CREATE OR REPLACE FUNCTION protect_dispute_data()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION
            'Não é permitido excluir registros de disputa';
    END IF;

    IF NEW.id_dispute IS DISTINCT FROM OLD.id_dispute
       OR NEW.id_order IS DISTINCT FROM OLD.id_order
       OR NEW.id_user IS DISTINCT FROM OLD.id_user
       OR NEW.reason IS DISTINCT FROM OLD.reason
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar os dados originais da disputa';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_dispute_data
BEFORE UPDATE OR DELETE ON dispute
FOR EACH ROW
EXECUTE FUNCTION protect_dispute_data();

-- Valida os dados de encerramento da disputa
CREATE OR REPLACE FUNCTION validate_dispute_resolution()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'UPDATE' THEN

        IF OLD.status IN ('resolved', 'rejected', 'canceled') THEN

            IF NEW.resolution_note IS DISTINCT FROM OLD.resolution_note
               OR NEW.resolved_by IS DISTINCT FROM OLD.resolved_by
            THEN
                RAISE EXCEPTION
                    'Não é permitido alterar a decisão de uma disputa encerrada';
            END IF;

            RETURN NEW;

        END IF;

    END IF;

    IF NEW.status IN ('resolved', 'rejected', 'canceled') THEN

        IF NEW.resolution_note IS NULL
           OR NEW.resolved_by IS NULL
        THEN
            RAISE EXCEPTION
                'O encerramento exige justificativa e responsável';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM user_role ur
            INNER JOIN role r
                ON r.id_role = ur.id_role
            WHERE ur.id_user = NEW.resolved_by
              AND r.role_name IN ('ADMIN', 'SUPPORT')
        ) THEN
            RAISE EXCEPTION
                'O usuário informado não possui permissão para encerrar disputas';
        END IF;

    ELSE

        IF NEW.resolution_note IS NOT NULL
           OR NEW.resolved_by IS NOT NULL
        THEN
            RAISE EXCEPTION
                'Os dados de encerramento exigem um status definitivo';
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_dispute_resolution
BEFORE INSERT OR UPDATE ON dispute
FOR EACH ROW
EXECUTE FUNCTION validate_dispute_resolution();

-- Índice para consultas por responsável pelo encerramento
CREATE INDEX idx_dispute_resolved_by
ON dispute(resolved_by)
WHERE resolved_by IS NOT NULL;

-- Índice para consultas por data de encerramento
CREATE INDEX idx_dispute_resolved_at
ON dispute(resolved_at)
WHERE resolved_at IS NOT NULL;