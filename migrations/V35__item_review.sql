CREATE TABLE item_review (
    id_item BIGINT PRIMARY KEY
        REFERENCES customer_order_item(id_item)
        ON DELETE CASCADE,

    reviewer_id UUID NOT NULL
        REFERENCES user_account(id_user),

    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),

    comment TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);


CREATE INDEX idx_item_review_reviewer ON item_review(reviewer_id);
CREATE INDEX idx_item_review_rating ON item_review(rating);