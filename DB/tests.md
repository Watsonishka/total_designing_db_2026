# Протокол самопроверки — схема `rezyapova_food`

## Окружение

| Параметр | Значение |
|---|---|
| PostgreSQL version | 18.4 |
| Дата проверки | 13.11.2026 |
| Схема | rezyapova_food |
| Роль-аудитор | inspector |

## A. Подготовка

### A.1. Восстановление бэкапа

Создание новой базы данных `restore_test` и восстановление `foodexpress_rezyapova.backup` через функционал DBeaver, после запуск скрипта `grants.sql`

```sql
create database restore_test;
create schema exts;
create extension "uuid-ossp" schema exts;
```
Ожидается: без ошибок.
Факт: бэкап `foodexpress_rezyapova.backup` восстановлен в пустую БД (со схемой `exts` и `uuid-ossp`) без ошибок; `grants.sql` выполнен без ошибок.
Вердикт: OK

### A.2. Переключение на inspector

```sql
SET ROLE inspector;
SET search_path TO rezyapova_food, exts;
SELECT current_user;
```

Ожидается: `inspector`.
Факт: `inspector`.
Вердикт: OK

---

## B. FOOD-101: Структура схемы

### B.1. Схема существует

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_food';
```

Ожидается: `rezyapova_food`.
Факт: `rezyapova_food`.
Вердикт: OK

### B.2. Схема `exts` с `uuid-ossp`

```sql
SELECT extname, extnamespace::regnamespace AS schema
FROM pg_extension WHERE extname = 'uuid-ossp';
```

Ожидается: `uuid-ossp`, схема `exts`.
Факт: `uuid-ossp | exts`.
Вердикт: OK

### B.3. Все 12 исходных таблиц + N после нормализации

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'rezyapova_food'
ORDER BY table_name;
```

Ожидается: `address`, `client`, `client_address`, `courier`, `courier_pay`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review` (12 + N штук).
Факт: `address, client, client_address, courier, courier_pay, order, order_structure, payment, product, product_category, restaurant, review` — 12 таблиц (N = 0) + представление `how_much_money` (`information_schema.tables` показывает и представления).
Вердикт: OK

### B.4. Все PK — `uuid`

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'rezyapova_food'
  AND column_name LIKE '%_id'
  AND data_type != 'uuid';
```

Ожидается: пусто.
Факт: пусто (0 строк).
Вердикт: OK

### B.5. Enum-типы

```sql
SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'rezyapova_food'
GROUP BY t.typname
ORDER BY t.typname;
```

Ожидается: 8 типов со значениями из constraints.md.
Факт: 8 типов: `courier_status` {свободен, занят, на_доставке, уволен}; `order_pay_status` {ожидает, оплачен, ошибка}; `order_status` {создан, готовится, в_доставке, доставлен, отменён}; `payment_status` {успех, ошибка, в_обработке}; `payment_type` {карта, наличные, безнал}; `product_status` {доступно, нет_в_наличии, архив}; `restaurant_status` {активен, неактивен}; `review_entity_type` {блюдо, ресторан, заказ} — совпадает с constraints.md.
Вердикт: OK

### B.6. FK-ограничения

```sql
SELECT conname, conrelid::regclass AS tbl, confrelid::regclass AS ref
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'rezyapova_food'::regnamespace
ORDER BY tbl, conname;
```

Ожидается: не менее 15 FK, все из erd.md.
Факт: 16 FK: `client_address` → `client`, `address`; `courier_pay` → `courier`; `order` → `client`, `restaurant`, `courier`, `address`, `client_address` (составной `client_id, address_id`); `order_structure` → `order`, `product`; `payment` → `order`; `product` → `product_category`, `restaurant`; `restaurant` → `address`; `review` → `client`, `order` (составной `order_id, client_id`). Все связи ERD реализованы.
Вердикт: OK

### B.7. Пароль — MD5

```sql
SELECT length(password) AS len, password
FROM client LIMIT 5;
```

Ожидается: `len = 32`, hex-строка.
Факт: на только что восстановленной схеме таблица пуста (0 строк); после C.2 — 5 строк, у всех `len = 32`, hex-строки (например, `fc3cc8891390d628b61570a88f2b7610`).
Вердикт: OK

---

## C. FOOD-102: `insert_test_data(value)`

### C.1. Чистая схема

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: без ошибок.
Вердикт: OK

### C.2. Первый запуск

```sql
CALL insert_test_data(10);
```

Ожидается: без ошибок.
Факт: без ошибок.
Вердикт: OK

### C.3. Распределение строк (BR-11.7)

```sql
SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
ORDER BY tbl;
```

Ожидается: address 50, client 10, courier 10, order 50, payment 50, product 50, product_category 10, restaurant 10, review 50.
Факт: address 50, client 10, courier 10, order 50, payment 50, product 50, product_category 10, restaurant 10, review 50.
Вердикт: OK

### C.4. Адреса ресторанов vs клиентов (BR-11.7)

```sql
SELECT 'restaurant addresses' AS cat, count(*) FROM restaurant WHERE address_id IS NOT NULL
UNION ALL
SELECT 'total addresses', count(*) FROM address;
```

Ожидается: restaurant addresses 10, total addresses 50 
Факт: restaurant addresses 10, total addresses 50 
Вердикт: OK

### C.5. Нет пустых строк (BR-11.3)

```sql
SELECT (SELECT count(*) FROM client WHERE login = '' OR password = '' OR phone_number = '')
     + (SELECT count(*) FROM address WHERE street = '' OR house_number = '' OR apartment_office = '')
     + (SELECT count(*) FROM restaurant WHERE restaurant_name = '' OR description = '' OR company_details = '')
     + (SELECT count(*) FROM product WHERE product_name = '' OR description = '' OR photo_url = '')
     + (SELECT count(*) FROM product_category WHERE product_category_name = '')
     + (SELECT count(*) FROM courier WHERE fio = '' OR phone_number = '')
     + (SELECT count(*) FROM "order" WHERE description = '')
     + (SELECT count(*) FROM payment WHERE transaction_number = '')
     + (SELECT count(*) FROM review WHERE description = '' OR photo_url = '') AS empty_strings;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### C.6. Нет NULL там, где запрещено (BR-11.3)

```sql
SELECT count(*) FROM "order" WHERE client_id IS NULL OR restaurant_id IS NULL
  OR courier_id IS NULL OR address_id IS NULL OR total_amount IS NULL
  OR order_timestamp IS NULL OR status IS NULL OR pay_status IS NULL OR description IS NULL
  OR (status = 'доставлен' AND delivery_timestamp IS NULL);
```

Остальные таблицы NULL в обязательных полях не допускают на уровне схемы (`NOT NULL`).

Ожидается: 0.
Факт: 0.
Вердикт: OK

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(*) FROM courier WHERE status != 'уволен';
```

Ожидается: `>= 1`.
Факт: 9.
Вердикт: OK

### C.8. `courier_pay` консистентен с правилами (BR-10.2)

```sql
SELECT cp.year, cp.month, cp.courier_id, cp.amount, cp.coefficient_used,
       round(coalesce((
           SELECT sum(o.commission)
           FROM "order" o
           WHERE o.courier_id = cp.courier_id
             AND o.status = 'доставлен'
             AND extract(year  from o.order_timestamp) = cp.year
             AND extract(month from o.order_timestamp) = cp.month
       ), 0) * cp.coefficient_used, 2) AS expected_amount
FROM courier_pay cp
LIMIT 20;

SELECT count(*) AS rows_checked, count(*) FILTER (WHERE amount <> expected_amount) AS mismatches
FROM (SELECT cp.amount,
             round(coalesce((SELECT sum(o.commission) FROM "order" o
                             WHERE o.courier_id = cp.courier_id AND o.status = 'доставлен'
                               AND extract(year from o.order_timestamp) = cp.year
                               AND extract(month from o.order_timestamp) = cp.month), 0)
                   * cp.coefficient_used, 2) AS expected_amount
      FROM courier_pay cp) t;
```

Ожидается: `amount = expected_amount` в каждой строке.
Факт: в первых 20 строках amount = expected_amount; проверка всех строк: rows_checked = 57, mismatches = 0.
Вердикт: OK

### C.9. Повторный вызов не ломает

```sql
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        CALL insert_test_data(10);
    END LOOP;
END $$;
```

Ожидается: без ошибок, данные добавляются 
Факт: без ошибок; данные добавляются (после 11 вызовов — 550 заказов).
Вердикт: OK

---

## D. Проверки бизнес-правил на сгенерированных данных

### D.1. Все FK валидны (нет orphans)

```sql
SELECT 'order_structure → order' AS fk, count(*) AS orphans
FROM order_structure os
LEFT JOIN "order" o ON os.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_structure → product', count(*)
FROM order_structure os
LEFT JOIN product p ON os.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'payment → order', count(*)
FROM payment pmt
LEFT JOIN "order" o ON pmt.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'review → order', count(*)
FROM review r
LEFT JOIN "order" o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'courier_pay → courier', count(*)
FROM courier_pay cp
LEFT JOIN courier c ON cp.courier_id = c.courier_id
WHERE c.courier_id IS NULL
UNION ALL
SELECT 'client_address → client', count(*)
FROM client_address ca
LEFT JOIN client c ON ca.client_id = c.client_id
WHERE c.client_id IS NULL
UNION ALL
SELECT 'client_address → address', count(*)
FROM client_address ca
LEFT JOIN address a ON ca.address_id = a.address_id
WHERE a.address_id IS NULL;
```

Ожидается: все 0.
Факт: все 7 проверок — 0.
Вердикт: OK

### D.2. Минимальная сумма заказа (BR-1.8)

```sql
SELECT count(*) FROM "order" WHERE total_amount < 1000;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(*) FROM "order" WHERE round(order_amount * 0.10, 2) != commission;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.4. `total_amount = order_amount + commission`

```sql
SELECT count(*) FROM "order"
WHERE round(order_amount + commission, 2) != total_amount;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.5. Дата доставки не раньше создания (BR-7.13)

```sql
SELECT count(*) FROM "order"
WHERE delivery_timestamp IS NOT NULL AND delivery_timestamp < order_timestamp;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) FROM "order" o
LEFT JOIN client_address ca
  ON ca.client_id = o.client_id AND ca.address_id = o.address_id
WHERE ca.client_id IS NULL;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.7. Все блюда в заказе из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id)
FROM order_structure os
JOIN "order" o ON os.order_id = o.order_id
JOIN product p ON os.product_id = p.product_id
WHERE p.restaurant_id != o.restaurant_id;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT order_id, count(*) AS cnt
FROM payment
WHERE status = 'успех'
GROUP BY order_id
HAVING count(*) != 1;
```

Ожидается: пусто.
Факт: пусто (0 строк).
Вердикт: OK

### D.9. Сумма оплаты = `total_amount` заказа (BR-8.4)

```sql
SELECT count(*) FROM payment p
JOIN "order" o ON p.order_id = o.order_id
WHERE p.amount != o.total_amount;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.10. Нет дубликатов в `client_address` (BR-2.5)

```sql
SELECT client_id, address_id, count(*)
FROM client_address
GROUP BY client_id, address_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: пусто (0 строк).
Вердикт: OK

### D.11. Нет дубликатов в `order_structure` (BR-7.16)

```sql
SELECT order_id, product_id, count(*)
FROM order_structure
GROUP BY order_id, product_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: пусто (0 строк).
Вердикт: OK

### D.12. `work_end > work_start` (BR-4.4)

```sql
SELECT count(*) FROM restaurant WHERE work_end <= work_start;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.13. `dismissal_date >= hire_date` (BR-6.3)

```sql
SELECT count(*) FROM courier
WHERE dismissal_date IS NOT NULL AND dismissal_date < hire_date;
```

Ожидается: 0.
Факт: 0.
Вердикт: OK

### D.14. Рейтинг блюд/ресторанов соответствует отзывам (BR-9.6)

```sql
SELECT p.product_id, p.rating,
       (SELECT round(avg(r.rating), 2) FROM review r
        WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id) AS expected
FROM product p
WHERE p.rating IS NOT NULL
LIMIT 20;
```

Ожидается: `rating = expected`.
Факт: 20 строк, `rating = expected` во всех; проверка всех блюд и ресторанов — 0 расхождений.
Вердикт: OK

---

## E. Функции и процедуры

### E.1. `add_product` — успешный вызов 

Адаптация: PostgreSQL не разрешает подзапросы в аргументах CALL, поэтому id ресторана и категории сначала берутся в переменные внутри DO-блока.

```sql
SELECT count(*) AS before FROM product;

DO $$
DECLARE
    v_rest uuid := (SELECT restaurant_id FROM restaurant LIMIT 1);
    v_cat  uuid := (SELECT product_category_id FROM product_category LIMIT 1);
BEGIN
    CALL add_product(
        p_restaurant_id       => v_rest,
        p_product_category_id => v_cat,
        p_name                => 'Тестовое блюдо',
        p_price               => 250,
        p_rating              => 4.5,
        p_status              => 'доступно',
        p_description         => 'Описание'
        -- p_photo_url необязателен (DEFAULT NULL)
    );
END $$;

SELECT count(*) AS after FROM product;
```

Ожидается: `after = before + 1`.
Факт: `before = 550`, `after = 551`.
Вердикт: OK

### E.2. `add_product` — падает на несуществующий ресторан

Адаптация: в шаблоне остальные аргументы не заполнены, без них вызов не пройдёт; категория берётся через переменную по той же причине, что в E.1.

```sql
DO $$
DECLARE
    v_cat uuid := (SELECT product_category_id FROM product_category LIMIT 1);
BEGIN
    CALL add_product(
        p_restaurant_id       => '00000000-0000-0000-0000-000000000000',
        p_product_category_id => v_cat,
        p_name                => 'x',
        p_price               => 250,
        p_rating              => 4.5,
        p_status              => 'доступно',
        p_description         => 'x'
    );
END $$;
```

Ожидается: ошибка с внятным сообщением.
Факт: ошибка `SQL Error [P0001]: ОШИБКА: add_product: ресторан с id 00000000-0000-0000-0000-000000000000 не существует`
Вердикт: OK

### E.3. `rating_change` — пересчитывает рейтинг **(адаптировано)**

Берётся блюдо из заказа, на которое в этом заказе ещё нет отзыва, и клиент этого заказа (BR-9.2, BR-9.5):

```sql
CREATE TEMP TABLE t_target AS
SELECT os.product_id, o.order_id, o.client_id
FROM order_structure os
JOIN "order" o USING (order_id)
WHERE NOT EXISTS (SELECT 1 FROM review r
                  WHERE r.order_id = o.order_id
                    AND r.entity_type = 'блюдо'
                    AND r.entity_id = os.product_id)
LIMIT 1;

SELECT product_id, rating AS before FROM product
WHERE product_id = (SELECT product_id FROM t_target);

INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type, order_id, description, rating)
SELECT exts.uuid_generate_v4(), client_id, localtimestamp, product_id, 'блюдо', order_id, 'Тестовый отзыв', 5
FROM t_target;

SELECT rating AS after_insert,
       (SELECT round(avg(r.rating), 2) FROM review r
        WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id) AS expected
FROM product p
WHERE product_id = (SELECT product_id FROM t_target);
```

Ожидается: `rating` пересчитан (`after_insert = expected`).
Факт: до вставки rating пустой (отзывов не было); после отзыва с оценкой 5 — after_insert = 5, expected = 5.
Вердикт: OK

Исходная вставка шаблона (случайный клиент и случайный заказ) отклоняется триггером `review_target_check` — так и должно быть по BR-9.2.

### E.4. `rating_change` — удаление отзыва

```sql
DELETE FROM review WHERE description = 'Тестовый отзыв';

SELECT rating AS after_delete,
       (SELECT round(avg(r.rating), 2) FROM review r
        WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id) AS expected
FROM product p
WHERE product_id = (SELECT product_id FROM t_target);
```

Ожидается: если других отзывов нет — rating IS NULL; иначе — пересчитан
Факт: after_delete = NULL, expected = NULL — других отзывов на блюдо нет, рейтинг сброшен.
Вердикт: OK

### E.5. `get_statistic()`

```sql
SELECT * FROM get_statistic();
```

Ожидается:
- Колонки: `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`.
- По одной строке на ресторан.
- `best_user` = `client.login` (не NULL при наличии заказов).

Факт: колонки `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`; 110 строк на 110 ресторанов; `best_user` — логин клиента (например, `Бистро №110 | Маргарита | 11836.71 | 3945.57 | 3b8_110`). У 3 ресторанов нет доставленных заказов — суммы 0, `best_product_name` и `best_user` пустые; у остальных не NULL.
Вердикт: OK

### E.6. `courier_salary()`

```sql
-- До
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;

CALL courier_salary();

-- После
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;
SELECT year, month, courier_id, amount, coefficient_used
FROM courier_pay
ORDER BY year DESC, month DESC, courier_id
LIMIT 20;
```

Ожидается:
- `courier.coefficient` пересчитан для работающих (по BR-10.2).
- У уволенных — не изменился.
- `courier_pay` содержит запись за текущий месяц.

Факт: до вызова у всех курьеров coefficient = 0.1, после вызова тоже 0.1. В текущем месяце ни у одного курьера нет больше 150 доставок, поэтому по BR-10.2 работающим снова ставится 0.1; у уволенных коэффициент не изменился. В courier_pay появились записи за 2026-11 с coefficient_used = 0.1; amount = комиссия за месяц × 0.1 (например, 37.31, 28.26, 92.94), у курьеров без доставок в этом месяце amount = 0.
Вердикт: OK

### E.7. `courier_salary()` — повторный вызов

```sql
CALL courier_salary();
SELECT count(*) FROM courier_pay
WHERE year = extract(year from current_date)
  AND month = extract(month from current_date);
```

Ожидается: количество не изменилось (idempotency / обновление).
Факт: 91 → 91, повторный вызов не создаёт новых строк, а обновляет существующие.
Вердикт: OK

---

## F. Представление `how_much_money`

### F.1. Колонки

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'rezyapova_food'
  AND table_name = 'how_much_money'
ORDER BY ordinal_position;
```

Ожидается: `year_month` (text), `sum_no_commission`, `sum_with_commission`, `commission`, `prev_commission`, `commission_diff`, `courier_pay`, `net_profit` (numeric).
Факт: `year_month` (text), `sum_no_commission`, `sum_with_commission`, `commission`, `prev_commission`, `commission_diff`, `courier_pay`, `net_profit` (numeric).
Вердикт: OK

### F.2. Месяцы покрыты

```sql
SELECT * FROM how_much_money ORDER BY year_month;
```

Ожидается: месяцы от первого доставленного заказа до последнего (не пропущено ни одного).
Факт: 6 месяцев подряд, 2026-06 … 2026-11, пропусков нет.
Вердикт: OK

### F.3. Месяцы без заказов присутствуют (BR-11.9)

```sql
SELECT year_month FROM how_much_money
WHERE sum_no_commission = 0 OR sum_no_commission IS NULL;
```

Ожидается: если в какие-то месяцы заказов не было — они есть в результате.
Факт: пусто (на сгенерированных данных доставленные заказы есть в каждом месяце).
Вердикт: OK

### F.4. Корректность сумм

```sql
SELECT year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission_diff,
       courier_pay,
       net_profit
FROM how_much_money
ORDER BY year_month
LIMIT 10;
```

Ожидается:
- `commission = sum_with_commission - sum_no_commission`.
- `commission_diff = commission - prev_commission` (NULL для первого месяца).
- `net_profit = commission - courier_pay`.

Факт: формулы выполняются во всех 6 строках; у первого месяца (2026-06) prev_commission и commission_diff — NULL.
Вердикт: OK

---

## G. Права `inspector`

### G.1. Права на схему

```sql
SELECT nspname AS schema_name,
       has_schema_privilege('inspector', nspname, 'USAGE')  AS usage,
       has_schema_privilege('inspector', nspname, 'CREATE') AS create
FROM pg_namespace
WHERE nspname = 'rezyapova_food';
```

Ожидается: `usage = true`, `create = true`.
Факт: `rezyapova_food | true | true`.
Вердикт: OK

### G.2. Права на таблицы

```sql
SELECT table_name, string_agg(privilege_type, ', ') AS privs
FROM information_schema.role_table_grants
WHERE grantee = 'inspector' AND table_schema = 'rezyapova_food'
GROUP BY table_name;
```

Ожидается: у каждой таблицы `SELECT, INSERT, UPDATE, DELETE` (или `ALL`).
Факт: у всех 12 таблиц и представления: `SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER` (= ALL).
Вердикт: OK

### G.3. `information_schema` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'rezyapova_food';
RESET ROLE;
```

Ожидается: 12 + N (количество таблиц).
Факт: 13 = 12 таблиц + представление `how_much_money`.
Вердикт: OK

### G.4. `pg_catalog` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM pg_catalog.pg_tables
WHERE schemaname = 'rezyapova_food';
RESET ROLE;
```

Ожидается: 12 + N.
Факт: 12.
Вердикт: OK

### G.5. Все процедуры/функции работают под `inspector`

```sql
SET ROLE inspector;
SET search_path TO rezyapova_food, exts;

CALL erase_test_data();
CALL insert_test_data(10);
CALL courier_salary();
SELECT * FROM get_statistic();
SELECT * FROM how_much_money LIMIT 5;

RESET ROLE;
```

Ожидается: без `permission denied`.
Факт: всё выполнено без `permission denied`
Вердикт: OK

---

## H. Оптимизация `get_statistic` (BR-11.8)

### H.1. `EXPLAIN ANALYZE` — паттерн «избыточные подзапросы»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS cnt,
       (SELECT coalesce(sum(commission), 0) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS commission_sum
FROM courier c;
```

Ожидается: два SubPlan, каждый — скан `"order"`. Время растёт линейно от числа курьеров.
Факт: Seq Scan on courier (10 строк), под ним SubPlan 1 (count) и SubPlan 2 (sum) — каждый выполняется 10 раз (loops=10, по разу на курьера) и каждый отдельно читает "order" через order_courier_idx. Итого "order" читается 20 раз. Execution Time: 0.228 ms.

### H.2. `EXPLAIN ANALYZE` — паттерн «один JOIN»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       count(o.order_id) AS cnt,
       coalesce(sum(o.commission), 0) AS commission_sum
FROM courier c
LEFT JOIN "order" o ON o.courier_id = c.courier_id AND o.status = 'доставлен'
GROUP BY c.courier_id;
```

Ожидается: один `Hash Right Join` / `Hash Left Join`, один скан `"order"`. Время меньше, чем в H.1.
Факт: SubPlan нет. "order" читается один раз (Seq Scan on "order", 33 доставленных заказа), courier — один раз. Соединение — Hash Right Join, сверху HashAggregate по courier_id. Execution Time: 0.186 ms (против 0.228 ms в H.1).
Вердикт: OK

### H.3. Применить к `get_statistic`

```sql
EXPLAIN ANALYZE SELECT * FROM get_statistic();
```

Ожидается: без `LATERAL`, без множественных подзапросов к одной таблице, без оконных функций там, где хватает агрегата.
Факт: EXPLAIN ANALYZE SELECT * FROM get_statistic() показывает только Function Scan on get_statistic (10 строк, Execution Time: 35.470 ms), план внутри функции не раскрывается.
По коду функции: "order" читается один раз — в CTE delivered (MATERIALIZED), дальше этот результат используется в трёх агрегатах (totals, best_product, best_client). Подзапросов на каждую строку, LATERAL и оконных функций нет; лучшее блюдо и клиент выбираются через DISTINCT ON, при равенстве — random(). Все справочники присоединяются через LEFT JOIN к restaurant, поэтому рестораны без заказов тоже попадают в результат.
Вердикт: OK

---

## I. Очистка и повторная генерация

### I.1. `erase_test_data` очищает всё

```sql
CALL erase_test_data();

SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'order_structure', count(*) FROM order_structure
UNION ALL SELECT 'client_address', count(*) FROM client_address
UNION ALL SELECT 'courier_pay', count(*) FROM courier_pay;
```

Ожидается: все 0.
Факт: все 12 таблиц — 0.
Вердикт: OK

### I.2. Повторный `erase_test_data` не падает

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: без ошибок.
Вердикт: OK

### I.3. После очистки `insert_test_data` снова работает

```sql
CALL insert_test_data(10);
SELECT count(*) FROM "order";
```

Ожидается: 50.
Факт: 50.
Вердикт: OK

