CREATE TYPE curation_status_enum AS ENUM ('pending','approved','rejected');

CREATE TYPE artwork_visibility_enum AS ENUM ('private','public');

CREATE TYPE account_status_enum AS ENUM ('pending','active','suspended','closed');

CREATE TYPE logistic_status_enum AS ENUM ('new','processing','shipped','delivered','cancelled');

CREATE TYPE payment_status_enum AS ENUM ('expired','pending','processing','paid','refused','refunded','chargeback');

CREATE TYPE token_type_enum AS ENUM ('auth','refresh','password_reset','email_confirm');

CREATE TYPE settlement_status_enum AS ENUM ('pending','processing','completed','failed');

CREATE TYPE product_type_enum AS ENUM ('physical','digital');

CREATE TYPE address_type_enum AS ENUM ('billing','shipping');

CREATE TYPE shipment_status_enum AS ENUM ('pending','shipped','in_transit','delivered','lost','returned');

CREATE TYPE ledger_type_enum AS ENUM ('order_payment','marketplace_fee','seller_payout','refund','chargeback');

CREATE TYPE fraud_risk_level_enum AS ENUM ('very_low','low','medium','high','critical');

CREATE TYPE artist_status_enum AS ENUM ('pending','under_review','approved','rejected','suspended','inactive');

CREATE TYPE order_status_enum AS ENUM ('created','awaiting_payment','confirmed','processing','completed','cancelled');

CREATE TYPE artwork_status_enum AS ENUM ('available','reserved','sold');

CREATE TYPE refund_status_enum AS ENUM ('pending','processing','approved','failed','canceled');

CREATE TYPE dispute_status_enum AS ENUM ('open','in_review','resolved','rejected','canceled');

CREATE TYPE ledger_direction_enum AS ENUM ('debit','credit');

CREATE TYPE ledger_reference_enum AS ENUM ('payment','refund','payout','adjustment');

CREATE TYPE fraud_decision_enum AS ENUM ('approve','review','block');

CREATE TYPE login_action_enum AS ENUM ('login','logout','failed','reset_success','reset_request');

CREATE TYPE security_event_enum AS ENUM ('login_attempt','password_change','account_locked','permission_change','suspicious_activity');

CREATE TYPE donation_status_enum AS ENUM ('pending','paid','failed','refunded');

CREATE TYPE notification_type_enum AS ENUM ('system', 'order_update', 'payment_confirmed', 'security_alert', 'promotion');

CREATE TYPE audit_operation_enum AS ENUM ('insert','update','delete'); 

CREATE TYPE discount_type_enum AS ENUM ('percentage','fixed');