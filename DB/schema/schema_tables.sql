create schema if not exists rezyapova_food;
set search_path to rezyapova_food, exts;

-- создание enum'ов
create type restaurant_status as enum ('активен', 'неактивен');
create type product_status as enum ('доступно', 'нет_в_наличии', 'архив');
create type courier_status as enum ('свободен', 'занят', 'на_доставке', 'уволен');
create type order_status as enum ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');
create type order_pay_status as enum ('ожидает', 'оплачен', 'ошибка');
create type payment_status as enum ('успех', 'ошибка', 'в_обработке');
create type payment_type as enum ('карта', 'наличные', 'безнал');
create type review_entity_type as enum ('блюдо', 'ресторан', 'заказ');

create table address (
    address_id uuid primary key default exts.uuid_generate_v4(),
    street varchar(100) not null,
    house_number varchar(20) not null,
    apartment_office varchar(20) null 
);

create table client (
    client_id uuid primary key default exts.uuid_generate_v4(),
    login varchar(50) not null unique,
    password char(32) not null check (password ~ '^[0-9a-f]{32}$'),
    phone_number char(12) not null unique
);

create table client_address (
    client_id uuid not null references client(client_id),
    address_id uuid not null references address(address_id),
    primary key (client_id, address_id)
);

create table restaurant (
    restaurant_id uuid primary key default exts.uuid_generate_v4(),
    restaurant_name varchar(100) not null,
    address_id uuid not null unique references address(address_id),
    description text not null,
    company_details text not null,
    work_start time not null,
    work_end time not null,
    rating numeric(3, 2) check (rating between 0 and 5),
    status restaurant_status not null, check (work_end > work_start)
);

create table product_category (
    product_category_id uuid primary key default exts.uuid_generate_v4(),
    product_category_name varchar(100) not null
);

create table product (
    product_id uuid primary key default exts.uuid_generate_v4(),
    product_name varchar(100) not null,
    product_category_id uuid not null references product_category(product_category_id),
    restaurant_id uuid not null references restaurant(restaurant_id),
    price numeric(10, 2) not null check (price >= 0),
    description text not null,
    photo_url text null,
    rating numeric(3, 2) check (rating between 0 and 5),
    status product_status not null
);

create table courier (
    courier_id uuid primary key default exts.uuid_generate_v4(),
    fio varchar(150) not null,
    phone_number varchar(12) not null,
    status courier_status not null,
    hire_date date not null,
    dismissal_date date null,
    coefficient numeric(2, 1) not null default 0.1 check (coefficient between 0.1 and 0.5),
    check ((status =  'уволен' and dismissal_date is not null) or (status <> 'уволен' and dismissal_date is null)), 
    check (dismissal_date >= hire_date)
);

create table courier_pay (
    courier_id uuid not null references courier(courier_id),
    year integer not null,
    month integer not null check (month between 1 and 12),    
    amount numeric(12, 2) not null check (amount >= 0),
    coefficient_used numeric(2, 1)  not null check (coefficient_used between 0.1 and 0.5),
    primary key (year, month, courier_id)
);

create table "order" (
    order_id uuid primary key default exts.uuid_generate_v4(),
    client_id uuid not null references client(client_id),
    restaurant_id uuid not null references restaurant(restaurant_id),
    courier_id uuid not null references courier(courier_id),
    address_id uuid not null references address(address_id),
    order_timestamp timestamp not null default localtimestamp,
    delivery_timestamp timestamp null,
    order_amount numeric(10, 2) not null check (order_amount >= 0),
    commission numeric(10, 2) generated always as (round(order_amount * 0.10, 2)) stored,
    total_amount numeric(10, 2) generated always as (order_amount + round(order_amount * 0.10, 2)) stored,
    status order_status not null,
    pay_status order_pay_status not null,
    description text not null, check (total_amount >= 1000), 
    check (delivery_timestamp >= order_timestamp),
    check (status <> 'доставлен' or delivery_timestamp is not null),
    foreign key (client_id, address_id) references client_address(client_id, address_id),
    unique (order_id, client_id)
);

create table order_structure (
    order_id uuid not null references "order"(order_id),
    product_id uuid not null references product(product_id),
    quantity numeric(8, 3) not null check (quantity > 0),
    primary key (order_id, product_id)
);

create table payment (
    payment_id uuid primary key default exts.uuid_generate_v4(),
    order_id uuid not null references "order"(order_id),
    payment_type payment_type not null,
    amount numeric(10, 2) not null,
    transaction_number varchar(100) not null unique,
    transaction_timestamp timestamp not null default localtimestamp,
    status payment_status not null
);

create table review (
    review_id uuid primary key default exts.uuid_generate_v4(),
    client_id uuid not null references client(client_id),
    order_id uuid not null,
    entity_type review_entity_type not null,
    entity_id uuid not null,
    description text not null,
    photo_url text null,
    rating numeric(2,1) not null check (rating between 1 and 5),
    review_timestamp timestamp not null default localtimestamp,
    foreign key (order_id, client_id) references "order"(order_id, client_id), unique (order_id, entity_type, entity_id)
);

-- Индексы
create unique index payment_one_success_uidx on payment(order_id) where status = 'успех';
create index review_entity_idx on review(entity_type, entity_id);
create index order_courier_idx on "order"(courier_id, order_timestamp);
create index order_structure_prod_idx on order_structure(product_id);
create index payment_order_idx on payment(order_id);

