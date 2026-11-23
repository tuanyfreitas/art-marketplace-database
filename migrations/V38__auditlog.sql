-- registra tudo que acontece nas tabelas importantes. registra toda alteração feita nos dados importantes do sistema.

CREATE TABLE audit_log (
    id_audit BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    table_name TEXT NOT NULL,

    operation audit_operation_enum NOT NULL,

    record_id UUID,

    old_data JSONB,
    new_data JSONB,

    changed_at TIMESTAMPTZ DEFAULT NOW(),

    changed_by UUID,

    ip_origin INET
);

CREATE INDEX idx_audit_table ON audit_log(table_name);
CREATE INDEX idx_audit_record ON audit_log(record_id);
CREATE INDEX idx_audit_changed_at ON audit_log(changed_at DESC);
CREATE INDEX idx_audit_user ON audit_log(changed_by);

-- Função genérica de auditoria responsável por registrar automaticamente
-- operações de INSERT, UPDATE e DELETE em tabelas monitoradas.
-- Armazena o nome da tabela, tipo da operação, snapshot dos dados antigos
-- e novos em formato JSONB, timestamp da alteração e IP de origem da conexão.
CREATE OR REPLACE FUNCTION audit_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_user UUID;
    v_record UUID;
BEGIN

    -- evita log inútil
    IF TG_OP = 'UPDATE' AND OLD IS NOT DISTINCT FROM NEW THEN
        RETURN NEW;
    END IF;

    -- usuário da sessão
    v_user := NULLIF(current_setting('app.user_id', true), '')::UUID;

    -- captura ID dinamicamente
    v_record := COALESCE(
        (to_jsonb(NEW)->>'id_user')::UUID,
        (to_jsonb(OLD)->>'id_user')::UUID
    );

    INSERT INTO audit_log (
        table_name,
        operation,
        record_id,
        old_data,
        new_data,
        changed_at,
        changed_by,
        ip_origin
    )
    VALUES (
        TG_TABLE_NAME,
        LOWER(TG_OP)::audit_operation_enum,
        v_record,
        to_jsonb(OLD),
        to_jsonb(NEW),
        NOW(),
        v_user,
        inet_client_addr()
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

--
CREATE TRIGGER trg_audit_user_account
AFTER INSERT OR UPDATE OR DELETE ON user_account
FOR EACH ROW
EXECUTE FUNCTION audit_trigger();

--
CREATE TRIGGER trg_audit_artwork
AFTER INSERT OR UPDATE OR DELETE ON artwork
FOR EACH ROW
EXECUTE FUNCTION audit_trigger();

--
CREATE TRIGGER trg_audit_artist
AFTER INSERT OR UPDATE OR DELETE ON artist
FOR EACH ROW
EXECUTE FUNCTION audit_trigger();
