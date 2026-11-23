CREATE TABLE artwork_stock (
    id_stock BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_artwork UUID NOT NULL UNIQUE,

    total_units INT NOT NULL DEFAULT 1 CHECK (total_units > 0),
    reserved_units INT NOT NULL DEFAULT 0 CHECK (reserved_units >= 0),
    sold_units INT NOT NULL DEFAULT 0 CHECK (sold_units >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_stock_artwork
        FOREIGN KEY (id_artwork)
        REFERENCES artwork(id_artwork)
        ON DELETE CASCADE,

    CONSTRAINT chk_stock_consistency
    CHECK (
        sold_units + reserved_units <= total_units
));

-- Atualiza automaticamente a data de modificação do estoque
CREATE TRIGGER trg_artwork_stock_updated_at
BEFORE UPDATE ON artwork_stock
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();
