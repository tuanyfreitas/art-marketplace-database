CREATE TABLE subcategory (
    id_subcategory INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_category INT NOT NULL,

    subcategory_name VARCHAR(255) NOT NULL
    CHECK (LENGTH(TRIM(subcategory_name)) > 0),

    slug VARCHAR(255) NOT NULL
    CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),

    description TEXT
    CHECK (description IS NULL OR LENGTH(TRIM(description)) > 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_subcategory_category
        FOREIGN KEY (id_category)
        REFERENCES category(id_category)
        ON DELETE CASCADE,

    CONSTRAINT unq_category_subcategory
        UNIQUE (id_category, subcategory_name),

    CONSTRAINT unq_category_slug
        UNIQUE (id_category, slug),

    CONSTRAINT unq_category_subcategory_id
        UNIQUE (id_category, id_subcategory)
);

-- Função responsável por gerar automaticamente o slug da subcategoria.
-- O slug é criado a partir do nome da subcategoria, convertendo o texto
-- para formato de URL (minúsculo e separado por hífens).
-- A geração ocorre apenas quando o campo slug não é informado no INSERT ou UPDATE
CREATE OR REPLACE FUNCTION generate_subcategory_slug()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.slug IS NULL OR NEW.slug = '' THEN
        NEW.slug := trim(BOTH '-' FROM
        regexp_replace(
        lower(unaccent(NEW.subcategory_name)),
        '[^a-z0-9]+',
        '-',
        'g'
    )
);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Gera automaticamente o slug quando ele não é informado.
-- Se a subcategoria mudar de nome, o slug existente será preservado
-- para evitar alterações nos links já publicados.
CREATE TRIGGER trg_subcategory_slug
BEFORE INSERT OR UPDATE ON subcategory
FOR EACH ROW
EXECUTE FUNCTION generate_subcategory_slug();

-- Atualiza automaticamente a data de modificação da subcategoria
CREATE TRIGGER trg_subcategory_updated_at
BEFORE UPDATE ON subcategory
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();