CREATE TABLE artwork (
    id_artwork UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_user UUID NOT NULL,
    id_category INT NOT NULL,
    id_subcategory INT,

    title VARCHAR(255) NOT NULL
    CHECK (LENGTH(TRIM(title)) > 0),

    slug VARCHAR(255) NOT NULL UNIQUE
    CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),

    description TEXT
    CHECK (description IS NULL OR LENGTH(TRIM(description)) > 0),

    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),

    product_type product_type_enum NOT NULL,

    height_cm NUMERIC(10,2) CHECK (height_cm > 0),
    width_cm NUMERIC(10,2) CHECK (width_cm > 0),
    depth_cm NUMERIC(10,2) CHECK (depth_cm > 0),
    weight_kg NUMERIC(10,2) CHECK (weight_kg > 0),

    materials VARCHAR(255)
    CHECK (materials IS NULL OR LENGTH(TRIM(materials)) > 0),

    curation_status curation_status_enum NOT NULL DEFAULT 'pending',
    visibility artwork_visibility_enum NOT NULL DEFAULT 'private',
    artwork_status artwork_status_enum NOT NULL DEFAULT 'available',
    
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_artwork_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE RESTRICT,

    CONSTRAINT fk_artwork_category
        FOREIGN KEY (id_category)
        REFERENCES category(id_category)
        ON DELETE RESTRICT,

    CONSTRAINT fk_artwork_subcategory
    FOREIGN KEY (id_category, id_subcategory)
    REFERENCES subcategory(id_category, id_subcategory)
    ON DELETE RESTRICT
);


CREATE INDEX idx_artwork_user ON artwork(id_user);
CREATE INDEX idx_artwork_visibility ON artwork(visibility);
CREATE INDEX idx_artwork_curation ON artwork(curation_status);
CREATE INDEX idx_artwork_category ON artwork(id_category);
CREATE INDEX idx_artwork_subcategory ON artwork(id_subcategory);
CREATE INDEX idx_artwork_created_at ON artwork(created_at);
CREATE INDEX idx_artwork_public_listing ON artwork(curation_status, visibility, artwork_status, published_at);
CREATE INDEX idx_artwork_public_available
ON artwork(published_at)
WHERE 
    curation_status = 'approved'
    AND visibility = 'public'
    AND artwork_status = 'available'
    AND published_at IS NOT NULL;


-- Função responsável por gerar automaticamente o slug da obra.
-- O slug é criado a partir do título, normalizando para formato de URL
-- (minúsculo e com hífens) e adicionando um sufixo aleatório baseado em UUID
-- para garantir unicidade entre registros.
-- A função só gera o slug caso ele não tenha sido informado no INSERT.
CREATE OR REPLACE FUNCTION generate_slug()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.slug IS NULL OR NEW.slug = '' THEN
        NEW.slug :=
            trim(BOTH '-' FROM
             regexp_replace(
             lower(unaccent(LEFT(NEW.title, 200))),
            '[^a-z0-9]+',
             '-',
            'g'
             ))
            || '-' ||
            substr(gen_random_uuid()::text, 1, 8);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger que executa antes da inserção de uma obra na tabela artwork
-- Sua função é chamar a função generate_slug() para garantir que toda obra
-- possua um slug válido e único no momento da criação.
CREATE TRIGGER trg_artwork_slug
BEFORE INSERT ON artwork
FOR EACH ROW
EXECUTE FUNCTION generate_slug();


-- Atualiza automaticamente a data de modificação da obra
CREATE TRIGGER trg_artwork_updated_at
BEFORE UPDATE ON artwork
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();