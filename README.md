# Cloud Analytics com Olist

Repositorio do projeto Cloud Analytics desenvolvido com o dataset publico da Olist. O objetivo e construir uma arquitetura moderna de dados na nuvem, cobrindo modelagem dimensional, pipeline de ETL e visualizacao em BI.

**Stack:** PostgreSQL (Supabase) / Apache Hop / Preset.io (Apache Superset)

---

## Estrutura do repositorio

```
/
├── etapa1-modelagem/
│   ├── README_etapa1.md
│   ├── ddl_star_schema.sql
│   ├── schema_completo.sql
│   ├── inserts_completo.sql
│   └── modelagem_dimensional_olist.xlsx
├── etapa2-etl/
│   └── (pipelines .hpl e .hwf do Apache Hop)
├── etapa3-bi/
│   └── (relatorio PDF e prints do dashboard)
└── README.md
```

---

## Etapa 1 - Modelagem Dimensional

### Escopo

O DW cobre o ciclo de pedidos da Olist: da compra ate a entrega e avaliacao pelo cliente. Dados de marketing, captacao de sellers e operacoes internas ficam fora do escopo.

**Dataset:** [github.com/olist/work-at-olist-data](https://github.com/olist/work-at-olist-data)

---

### Modelo relacional (origem)

O dataset original e composto por 8 tabelas relacionais transacionais:

```
olist_customers_dataset
olist_sellers_dataset
olist_products_dataset
olist_geolocation_dataset
olist_orders_dataset
olist_order_items_dataset
olist_order_payments_dataset
olist_order_reviews_dataset
product_category_name_translation
```

**Diagrama conceitual do modelo relacional (origem):**

```
customers ──────────────────── orders
                                  |
                         order_items ──── products
                                  |
                              sellers
                                  |
                           geolocation

orders ──── order_payments
orders ──── order_reviews
```

**Diagrama fisico do modelo relacional (origem):**

```
customers                    orders
├── customer_id (PK)         ├── order_id (PK)
├── customer_unique_id       ├── customer_id (FK)
├── zip_code_prefix          ├── order_status
├── city                     ├── order_purchase_timestamp
└── state                    ├── order_approved_at
                             ├── order_delivered_carrier_date
                             ├── order_delivered_customer_date
                             └── order_estimated_delivery_date

order_items                  products
├── order_id (PK, FK)        ├── product_id (PK)
├── order_item_id (PK)       ├── product_category_name
├── product_id (FK)          ├── product_name_lenght
├── seller_id (FK)           ├── product_description_lenght
├── shipping_limit_date      ├── product_photos_qty
├── price                    ├── product_weight_g
└── freight_value            ├── product_length_cm
                             ├── product_height_cm
                             └── product_width_cm

sellers                      order_payments
├── seller_id (PK)           ├── order_id (FK)
├── seller_zip_code_prefix   ├── payment_sequential
├── seller_city              ├── payment_type
└── seller_state             ├── payment_installments
                             └── payment_value

geolocation                  order_reviews
├── zip_code_prefix          ├── review_id (PK)
├── geolocation_lat          ├── order_id (FK)
├── geolocation_lng          ├── review_score
├── geolocation_city         ├── review_comment_title
└── geolocation_state        └── review_comment_message

product_category_name_translation
├── product_category_name
└── product_category_name_english
```

---

### Modelo dimensional (DW)

#### Granularidade

**1 linha = 1 item dentro de 1 pedido.**

Um pedido pode ter varios produtos, entao um `order_id` pode gerar multiplas linhas na fato. Metricas de pagamento e review existem no nivel do pedido e sao repetidas em cada item de forma intencional para simplificar as agregacoes no BI.

#### Diagrama conceitual do Star Schema

```
                        dim_date
                      (x3 papeis)
                           |
                     purchase_date_sk
                     delivered_date_sk
                     estimated_date_sk
                           |
dim_customer ──── customer_sk ──── fact_orders ──── seller_sk ──── dim_seller
                                       |
                               product_sk ──── dim_product
                                       |
                              payment_type_sk ──── dim_payment_type
                                       |
                             order_status_sk ──── dim_order_status
                                       |
                    customer_geo_sk ───┤
                    seller_geo_sk ─────┘
                           |
                     dim_geolocation
                      (x2 papeis)
```

> `dim_date` e `dim_geolocation` sao role-playing dimensions: a mesma tabela aparece com papeis distintos na fato.

#### Diagrama fisico do Star Schema (DER)

```
fact_orders
├── order_item_sk (PK)
├── customer_sk (FK -> dim_customer)
├── seller_sk (FK -> dim_seller)
├── product_sk (FK -> dim_product)
├── order_purchase_date_sk (FK -> dim_date)
├── order_delivered_date_sk (FK -> dim_date)
├── order_estimated_date_sk (FK -> dim_date)
├── payment_type_sk (FK -> dim_payment_type)
├── order_status_sk (FK -> dim_order_status)
├── customer_geo_sk (FK -> dim_geolocation)
├── seller_geo_sk (FK -> dim_geolocation)
├── order_id
├── order_item_id
├── price
├── freight_value
├── total_item_value [calculado]
├── payment_installments
├── payment_value
├── review_score
├── days_to_deliver
└── etl_loaded_at

dim_date                         dim_customer
├── date_sk (PK)                 ├── customer_sk (PK)
├── full_date                    ├── customer_id
├── day_of_month                 ├── customer_unique_id
├── day_of_week                  ├── zip_code_prefix
├── day_name                     ├── city
├── week_of_year                 └── state
├── month_number
├── month_name                   dim_seller
├── quarter                      ├── seller_sk (PK)
├── year                         ├── seller_id
├── is_weekend                   ├── zip_code_prefix
└── semester                     ├── city
                                 └── state

dim_product                      dim_geolocation
├── product_sk (PK)              ├── geolocation_sk (PK)
├── product_id                   ├── zip_code_prefix
├── category_name_portuguese     ├── city
├── category_name_english        ├── state
├── name_length                  ├── region
├── description_length           ├── lat
├── photos_qty                   └── lng
├── weight_g
├── length_cm                    dim_payment_type
├── height_cm                    ├── payment_type_sk (PK)
└── width_cm                     ├── payment_type_code
                                 └── payment_type_label

dim_order_status
├── order_status_sk (PK)
├── status_code
├── status_label
└── is_final_state
```

#### Tabelas e volumes estimados

| Tabela | Tipo | Linhas | Fonte |
|---|---|---|---|
| fact_orders | Fato | 112.650 | order_items + orders + payments + reviews |
| dim_date | Dimensao | 720 | Gerada no Hop |
| dim_customer | Dimensao | 99.441 | olist_customers_dataset.csv |
| dim_seller | Dimensao | 3.095 | olist_sellers_dataset.csv |
| dim_product | Dimensao | 32.951 | olist_products_dataset.csv + translation |
| dim_geolocation | Dimensao | 19.015 | olist_geolocation_dataset.csv (dedupado por CEP) |
| dim_payment_type | Dimensao | 5 | Seed manual |
| dim_order_status | Dimensao | 8 | Seed manual |

#### SCD por dimensao

| Dimensao | Tipo SCD | Motivo |
|---|---|---|
| dim_date | Tipo 0 | Datas nao mudam |
| dim_geolocation | Tipo 0 | Coordenadas geograficas estaticas |
| dim_payment_type | Tipo 0 | Catalogo fixo |
| dim_order_status | Tipo 0 | Catalogo fixo |
| dim_customer | Tipo 1 | Sobrescreve sem historico |
| dim_seller | Tipo 1 | Sobrescreve sem historico |
| dim_product | Tipo 1 | Sobrescreve sem historico |

---
## Modelos

### Modelo Relacional Conceitual 
<img width="548" height="400" alt="image" src="https://github.com/user-attachments/assets/da46f7d5-f49b-4219-ba98-d03527cfced6" />


### Modelo Relacional Fisico
<img width="5697" height="3143" alt="diagram_mermaid" src="https://github.com/user-attachments/assets/77ef3b33-bf69-491d-9ffe-a12f16a73df0" />


---

### Artefatos da Etapa 1

| Arquivo | Descricao |
|---|---|
| `olist-schema.sql` | DDL do zero: cria todas as tabelas, indices, seeds e views |
| `modelagem_dimensional_olist.xlsx` | Documentacao de atributos, tipos, amostras e SCD por tabela |

---

## Etapa 2 - ETL com Apache Hop

### Configuracao da conexao JDBC

As credenciais ficam em `Supabase > Project Settings > Database > Connection String`.

```
Driver:   org.postgresql.Driver
URL:      jdbc:postgresql://<HOST>:5432/postgres?sslmode=require
User:     postgres
Password: <senha do projeto>
```

O parametro `sslmode=require` e obrigatorio. Usar **commit size de 500 linhas** no componente Table Output para evitar lentidao na carga em nuvem.

### Ordem de carga dos pipelines

```
1. dim_date
2. dim_payment_type  (seed ja no DDL, pode pular)
3. dim_order_status  (seed ja no DDL, pode pular)
4. dim_geolocation   (deduplicar por zip_code_prefix antes de inserir)
5. dim_product       (JOIN com translation.csv para trazer category_name_english)
6. dim_customer
7. dim_seller
8. fact_orders       (lookup das SKs nas dimensoes + join com payments e reviews)
```

### Estrutura dos artefatos Hop

```
etapa2-etl/
├── ddl/
│   └── schema_completo.sql
├── pipelines/
│   ├── dim_date.hpl
│   ├── dim_geolocation.hpl
│   ├── dim_customer.hpl
│   ├── dim_seller.hpl
│   ├── dim_product.hpl
│   ├── dim_payment_type.hpl
│   ├── dim_order_status.hpl
│   └── fact_orders.hpl
└── workflows/
    ├── wf_dimensoes.hwf
    ├── wf_fato.hwf
    └── wf_completo.hwf
```

---

## Etapa 3 - BI no Preset.io

### Conexao com o Supabase

No Preset, adicionar um novo Database selecionando PostgreSQL e inserir as credenciais do Supabase. Pode ser necessario desativar o modo SSL strict dependendo da versao do Preset.

### Views disponíveis para uso como Dataset

| View | Uso |
|---|---|
| `vw_sales_overview` | Receita, GMV e volume de pedidos por periodo, categoria e regiao |
| `vw_delivery_performance` | Atrasos, tempo de entrega e review por pedido |
| `vw_seller_performance` | Ranking de vendedores com receita e taxa de atraso |
| `vw_category_performance` | Receita e volume por categoria de produto |
| `vw_payment_behavior` | Distribuicao de formas de pagamento e ticket medio |

### Perguntas de negocio do dashboard

1. Como o GMV evoluiu mês a mês?
2. Quais categorias de produto vendem mais? E quais tem as piores avaliações?
3. Quais estados compram mais? E quais tem mais atrasos nas entregas?
4. Em quais períodos do ano ocorrem mais atrasos?
5. Quais os 10 vendedores que geraram mais receita e como é a performance de entrega deles?
