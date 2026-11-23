CREATE TABLE cart (
    id_cart BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID NOT NULL UNIQUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_cart_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE
);



CREATE TABLE cart_item (
    id_cart_item BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_cart BIGINT NOT NULL,
    id_artwork UUID NOT NULL,

    quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),

    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_cart_item_cart
        FOREIGN KEY (id_cart)
        REFERENCES cart(id_cart)
        ON DELETE CASCADE,

    CONSTRAINT fk_cartitem_artwork
        FOREIGN KEY (id_artwork)
        REFERENCES artwork(id_artwork)
        ON DELETE CASCADE,

    CONSTRAINT unq_cart_artwork
        UNIQUE (id_cart, id_artwork)
);

CREATE INDEX idx_cart_item_artwork
ON cart_item(id_artwork);

--trigger
CREATE TRIGGER trg_cart_updated_at
BEFORE UPDATE ON cart
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

-- Atualiza a data de modificação do carrinho quando seus itens são alterados
CREATE OR REPLACE FUNCTION update_cart_on_item_change()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN

        UPDATE cart
        SET updated_at = NOW()
        WHERE id_cart = OLD.id_cart;

    ELSIF TG_OP = 'INSERT' THEN

        UPDATE cart
        SET updated_at = NOW()
        WHERE id_cart = NEW.id_cart;

    ELSIF TG_OP = 'UPDATE' THEN

        UPDATE cart
        SET updated_at = NOW()
        WHERE id_cart IN (OLD.id_cart, NEW.id_cart);

    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Atualiza o carrinho automaticamente quando seus itens são modificados
CREATE TRIGGER trg_cart_item_updated
AFTER INSERT OR UPDATE OR DELETE ON cart_item
FOR EACH ROW
EXECUTE FUNCTION update_cart_on_item_change();

