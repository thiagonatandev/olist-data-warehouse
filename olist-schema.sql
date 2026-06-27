-- -------------------------------------------------------
-- Dimensões
-- -------------------------------------------------------

CREATE TABLE dim_date (
    date_sk          SERIAL       PRIMARY KEY,
    full_date        DATE         NOT NULL UNIQUE,
    day_of_month     SMALLINT     NOT NULL,
    day_of_week      SMALLINT     NOT NULL,
    day_name         VARCHAR(15)  NOT NULL,
    week_of_year     SMALLINT     NOT NULL,
    month_number     SMALLINT     NOT NULL,
    month_name       VARCHAR(15)  NOT NULL,
    quarter          SMALLINT     NOT NULL,
    year             SMALLINT     NOT NULL,
    is_weekend       BOOLEAN      NOT NULL DEFAULT FALSE,
    semester         SMALLINT     NOT NULL
);

CREATE TABLE dim_customer (
    customer_sk        SERIAL       PRIMARY KEY,
    customer_id        VARCHAR(50)  NOT NULL UNIQUE,
    customer_unique_id VARCHAR(50)  NOT NULL,
    zip_code_prefix    VARCHAR(10),
    city               VARCHAR(100),
    state              CHAR(2)
);

CREATE TABLE dim_seller (
    seller_sk       SERIAL       PRIMARY KEY,
    seller_id       VARCHAR(50)  NOT NULL UNIQUE,
    zip_code_prefix VARCHAR(10),
    city            VARCHAR(100),
    state           CHAR(2)
);

CREATE TABLE dim_product (
    product_sk               SERIAL        PRIMARY KEY,
    product_id               VARCHAR(50)   NOT NULL UNIQUE,
    category_name_portuguese VARCHAR(100),
    category_name_english    VARCHAR(100),
    name_length              SMALLINT,
    description_length       INTEGER,
    photos_qty               SMALLINT,
    weight_g                 INTEGER,
    length_cm                SMALLINT,
    height_cm                SMALLINT,
    width_cm                 SMALLINT
);

CREATE TABLE dim_geolocation (
    geolocation_sk  SERIAL        PRIMARY KEY,
    zip_code_prefix VARCHAR(10)   NOT NULL UNIQUE,
    city            VARCHAR(100),
    state           CHAR(2),
    region          VARCHAR(20),
    lat             NUMERIC(10,6),
    lng             NUMERIC(10,6)
);

CREATE TABLE dim_payment_type (
    payment_type_sk    SERIAL      PRIMARY KEY,
    payment_type_code  VARCHAR(30) NOT NULL UNIQUE,
    payment_type_label VARCHAR(50) NOT NULL
);

CREATE TABLE dim_order_status (
    order_status_sk SERIAL      PRIMARY KEY,
    status_code     VARCHAR(20) NOT NULL UNIQUE,
    status_label    VARCHAR(50) NOT NULL,
    is_final_state  BOOLEAN     NOT NULL DEFAULT FALSE
);


-- -------------------------------------------------------
-- Seeds
-- -------------------------------------------------------

INSERT INTO dim_payment_type (payment_type_sk, payment_type_code, payment_type_label) VALUES
    (1, 'credit_card', 'Cartão de Crédito'),
    (2, 'boleto',      'Boleto Bancário'),
    (3, 'voucher',     'Voucher'),
    (4, 'debit_card',  'Cartão de Débito'),
    (5, 'not_defined', 'Não Definido');

INSERT INTO dim_order_status (order_status_sk, status_code, status_label, is_final_state) VALUES
    (1, 'created',     'Criado',           FALSE),
    (2, 'approved',    'Aprovado',         FALSE),
    (3, 'invoiced',    'Faturado',         FALSE),
    (4, 'processing',  'Em Processamento', FALSE),
    (5, 'shipped',     'Enviado',          FALSE),
    (6, 'delivered',   'Entregue',         TRUE),
    (7, 'canceled',    'Cancelado',        TRUE),
    (8, 'unavailable', 'Indisponível',     TRUE);


-- -------------------------------------------------------
-- Fato principal
-- Granularidade: 1 linha = 1 item de pedido
-- -------------------------------------------------------

CREATE TABLE fact_orders (
    order_item_sk           BIGSERIAL      PRIMARY KEY,

    customer_sk             INT            NOT NULL REFERENCES dim_customer(customer_sk),
    seller_sk               INT            NOT NULL REFERENCES dim_seller(seller_sk),
    product_sk              INT            NOT NULL REFERENCES dim_product(product_sk),
    order_purchase_date_sk  INT            NOT NULL REFERENCES dim_date(date_sk),
    order_delivered_date_sk INT                     REFERENCES dim_date(date_sk),
    order_estimated_date_sk INT                     REFERENCES dim_date(date_sk),
    payment_type_sk         INT                     REFERENCES dim_payment_type(payment_type_sk),
    order_status_sk         INT                     REFERENCES dim_order_status(order_status_sk),
    customer_geo_sk         INT                     REFERENCES dim_geolocation(geolocation_sk),
    seller_geo_sk           INT                     REFERENCES dim_geolocation(geolocation_sk),

    order_id                VARCHAR(50)    NOT NULL,
    order_item_id           SMALLINT       NOT NULL,

    price                   NUMERIC(10,2)  NOT NULL,
    freight_value           NUMERIC(10,2)  NOT NULL,
    total_item_value        NUMERIC(10,2)  GENERATED ALWAYS AS (price + freight_value) STORED,

    payment_installments    SMALLINT,
    payment_value           NUMERIC(10,2),
    review_score            SMALLINT,
    days_to_deliver         SMALLINT,

    etl_loaded_at           TIMESTAMP      NOT NULL DEFAULT NOW()
);


-- -------------------------------------------------------
-- Índices
-- -------------------------------------------------------

CREATE INDEX idx_fact_customer       ON fact_orders (customer_sk);
CREATE INDEX idx_fact_seller         ON fact_orders (seller_sk);
CREATE INDEX idx_fact_product        ON fact_orders (product_sk);
CREATE INDEX idx_fact_purchase_date  ON fact_orders (order_purchase_date_sk);
CREATE INDEX idx_fact_delivered_date ON fact_orders (order_delivered_date_sk);
CREATE INDEX idx_fact_payment_type   ON fact_orders (payment_type_sk);
CREATE INDEX idx_fact_status         ON fact_orders (order_status_sk);
CREATE INDEX idx_fact_order_id       ON fact_orders (order_id);
CREATE INDEX idx_fact_customer_geo   ON fact_orders (customer_geo_sk);
CREATE INDEX idx_fact_seller_geo     ON fact_orders (seller_geo_sk);

CREATE INDEX idx_dim_customer_unique ON dim_customer (customer_unique_id);
CREATE INDEX idx_dim_customer_zip    ON dim_customer (zip_code_prefix);
CREATE INDEX idx_dim_seller_zip      ON dim_seller (zip_code_prefix);
CREATE INDEX idx_dim_product_cat_en  ON dim_product (category_name_english);
CREATE INDEX idx_dim_product_cat_pt  ON dim_product (category_name_portuguese);
CREATE INDEX idx_dim_geo_state       ON dim_geolocation (state);
CREATE INDEX idx_dim_geo_region      ON dim_geolocation (region);
CREATE INDEX idx_dim_date_year_month ON dim_date (year, month_number);
CREATE INDEX idx_dim_date_full_date  ON dim_date (full_date);


-- -------------------------------------------------------
-- Views
-- -------------------------------------------------------

-- Visão geral de vendas agrupada — dataset principal para o Preset
CREATE OR REPLACE VIEW vw_sales_overview AS
SELECT
    dd.year,
    dd.month_number,
    dd.month_name,
    dd.quarter,
    dd.semester,
    dp.category_name_english             AS product_category,
    dp.category_name_portuguese          AS product_category_pt,
    dg_c.state                           AS customer_state,
    dg_c.region                          AS customer_region,
    dg_c.city                            AS customer_city,
    dg_s.state                           AS seller_state,
    dg_s.region                          AS seller_region,
    dpt.payment_type_label               AS payment_type,
    dos.status_label                     AS order_status,
    dos.is_final_state,
    COUNT(DISTINCT fo.order_id)          AS total_orders,
    COUNT(*)                             AS total_items,
    SUM(fo.price)                        AS revenue,
    SUM(fo.freight_value)                AS freight_revenue,
    SUM(fo.total_item_value)             AS gmv,
    AVG(fo.price)                        AS avg_item_price,
    AVG(fo.review_score)                 AS avg_review_score,
    AVG(fo.payment_installments)         AS avg_installments,
    AVG(fo.days_to_deliver)              AS avg_days_to_deliver
FROM fact_orders fo
JOIN dim_date           dd    ON fo.order_purchase_date_sk  = dd.date_sk
JOIN dim_customer       dc    ON fo.customer_sk             = dc.customer_sk
JOIN dim_seller         ds    ON fo.seller_sk               = ds.seller_sk
JOIN dim_product        dp    ON fo.product_sk              = dp.product_sk
LEFT JOIN dim_geolocation dg_c ON fo.customer_geo_sk        = dg_c.geolocation_sk
LEFT JOIN dim_geolocation dg_s ON fo.seller_geo_sk          = dg_s.geolocation_sk
LEFT JOIN dim_payment_type dpt ON fo.payment_type_sk        = dpt.payment_type_sk
LEFT JOIN dim_order_status dos ON fo.order_status_sk        = dos.order_status_sk
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15;


-- Performance logística — base para análise de atrasos
CREATE OR REPLACE VIEW vw_delivery_performance AS
SELECT
    fo.order_id,
    fo.order_item_id,
    dg_c.state                                           AS customer_state,
    dg_c.region                                          AS customer_region,
    dg_c.city                                            AS customer_city,
    dg_s.state                                           AS seller_state,
    dg_s.region                                          AS seller_region,
    dp.category_name_english                             AS product_category,
    d_purchase.full_date                                 AS purchase_date,
    d_delivered.full_date                                AS delivered_date,
    d_estimated.full_date                                AS estimated_date,
    fo.days_to_deliver,
    (d_delivered.full_date - d_estimated.full_date)      AS delay_days,
    CASE
        WHEN d_delivered.full_date > d_estimated.full_date THEN TRUE
        ELSE FALSE
    END                                                  AS is_late,
    fo.review_score,
    fo.freight_value,
    fo.price
FROM fact_orders fo
JOIN  dim_date        d_purchase  ON fo.order_purchase_date_sk  = d_purchase.date_sk
LEFT JOIN dim_date    d_delivered ON fo.order_delivered_date_sk = d_delivered.date_sk
LEFT JOIN dim_date    d_estimated ON fo.order_estimated_date_sk = d_estimated.date_sk
LEFT JOIN dim_geolocation dg_c   ON fo.customer_geo_sk          = dg_c.geolocation_sk
LEFT JOIN dim_geolocation dg_s   ON fo.seller_geo_sk            = dg_s.geolocation_sk
JOIN  dim_product     dp          ON fo.product_sk              = dp.product_sk;


-- Performance por vendedor
CREATE OR REPLACE VIEW vw_seller_performance AS
SELECT
    ds.seller_id,
    ds.city                              AS seller_city,
    ds.state                             AS seller_state,
    dg_s.region                          AS seller_region,
    COUNT(DISTINCT fo.order_id)          AS total_orders,
    COUNT(*)                             AS total_items,
    SUM(fo.price)                        AS total_revenue,
    SUM(fo.freight_value)                AS total_freight,
    AVG(fo.price)                        AS avg_item_price,
    AVG(fo.review_score)                 AS avg_review_score,
    AVG(fo.days_to_deliver)              AS avg_days_to_deliver,
    COUNT(CASE WHEN d_del.full_date > d_est.full_date THEN 1 END) AS late_deliveries,
    COUNT(CASE WHEN fo.order_delivered_date_sk IS NOT NULL THEN 1 END) AS delivered_items
FROM fact_orders fo
JOIN dim_seller        ds    ON fo.seller_sk              = ds.seller_sk
LEFT JOIN dim_geolocation dg_s ON fo.seller_geo_sk        = dg_s.geolocation_sk
LEFT JOIN dim_date     d_del  ON fo.order_delivered_date_sk = d_del.date_sk
LEFT JOIN dim_date     d_est  ON fo.order_estimated_date_sk = d_est.date_sk
GROUP BY 1,2,3,4;


-- Receita e volume por categoria de produto
CREATE OR REPLACE VIEW vw_category_performance AS
SELECT
    dp.category_name_english             AS category,
    dp.category_name_portuguese          AS category_pt,
    COUNT(DISTINCT fo.order_id)          AS total_orders,
    COUNT(*)                             AS total_items,
    SUM(fo.price)                        AS total_revenue,
    AVG(fo.price)                        AS avg_price,
    AVG(fo.review_score)                 AS avg_review_score,
    AVG(dp.weight_g)                     AS avg_weight_g,
    AVG(fo.freight_value)                AS avg_freight
FROM fact_orders fo
JOIN dim_product dp ON fo.product_sk = dp.product_sk
GROUP BY 1,2;


-- Comportamento de pagamento
CREATE OR REPLACE VIEW vw_payment_behavior AS
SELECT
    dpt.payment_type_label               AS payment_type,
    dd.year,
    dd.month_number,
    dd.month_name,
    COUNT(DISTINCT fo.order_id)          AS total_orders,
    SUM(fo.payment_value)                AS total_paid,
    AVG(fo.payment_value)                AS avg_order_value,
    AVG(fo.payment_installments)         AS avg_installments,
    MAX(fo.payment_installments)         AS max_installments
FROM fact_orders fo
JOIN dim_date          dd  ON fo.order_purchase_date_sk = dd.date_sk
LEFT JOIN dim_payment_type dpt ON fo.payment_type_sk   = dpt.payment_type_sk
GROUP BY 1,2,3,4;
