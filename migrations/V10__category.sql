CREATE TABLE category (
    id_category INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    category_name VARCHAR(255) NOT NULL UNIQUE
    CHECK (LENGTH(TRIM(category_name)) > 0),

    slug VARCHAR(255) NOT NULL UNIQUE
    CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),

    description TEXT
    CHECK (description IS NULL OR LENGTH(TRIM(description)) > 0),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

--Atualiza automaticamente o campo updated_at sempre que um registro é alterado.
--Evita que o desenvolvedor precise lembrar de atualizar manualmente esse timestamp, garantindo consistência.
CREATE TRIGGER trg_category_updated_at
BEFORE UPDATE ON category
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();