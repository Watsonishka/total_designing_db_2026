# Обоснование ограничений rezyapova_food

Таблица заказов названа `"order"` в двойных кавычках — имя из ERD сохранено (BR-13.1). Все ID — `uuid` через `exts.uuid_generate_v4()` (BR-11.1), схема `exts` не пересоздаётся (BR-13.3). Все статусы — `enum` (BR-11.5), даты и время — без часового пояса (BR-11.2).

## Enum-типы

| Тип | Значения | BR |
|---|---|---|
| restaurant_status | 'активен', 'неактивен' | BR-4.3 |
| product_status | 'доступно', 'нет_в_наличии', 'архив' | BR-5.5 |
| courier_status | 'свободен', 'занят', 'на_доставке', 'уволен' | BR-6.2 |
| order_status | 'создан', 'готовится', 'в_доставке', 'доставлен', 'отменён' | BR-7.7 |
| order_pay_status | 'ожидает', 'оплачен', 'ошибка' | BR-7.9 |
| payment_status | 'успех', 'ошибка', 'в_обработке' | BR-8.2 |
| payment_type | 'карта', 'наличные', 'безнал' | BR-8.2 |
| review_entity_type | 'блюдо', 'ресторан', 'заказ' | BR-9.1 |

Значения совпадают с BR. Статус оплаты заказа и статус попытки оплаты — разные типы, потому что у них разные наборы значений (BR-7.9 и BR-8.2).

## Ловушки и принятые решения

### Ловушка 1. Платёж

В `payment` добавлены тип оплаты, сумма, внешний уникальный `transaction_number`, время и статус каждой попытки (BR-8.2, BR-8.3). Тип оплаты хранится в попытке, а не в заказе: один заказ можно пытаться оплатить разными способами (BR-8.6). Частичный уникальный индекс `payment_one_success_uidx` разрешает не больше одной успешной попытки на заказ (BR-8.1). Триггер `payment_amount_check` проверяет, что сумма попытки равна `total_amount` заказа (BR-8.4), а `payment_sync_pay_status` пересчитывает `order.pay_status` по попыткам (BR-8.7).

### Ловушка 2. Адрес заказа

Составной FK `order(client_id, address_id) → client_address(client_id, address_id)` гарантирует, что адрес доставки выбран из адресов этого клиента (BR-7.4). Отдельные FK на `client` и `address` сохраняют связи из ERD.

### Ловушка 3. Блюда заказа

`order_structure` хранит только `(order_id, product_id, quantity)` с составным PK, поэтому одно блюдо не повторяется в заказе (BR-7.16). Триггер `order_structure_restaurant_check` проверяет, что ресторан блюда совпадает с рестораном заказа (BR-7.3). Ещё два триггера не дают обойти правило задним числом: нельзя сменить ресторан у заказа с блюдами и перенести заказанное блюдо в другой ресторан. `restaurant_id` в позиции не дублируется, транзитивной зависимости нет.

### Ловушка 4. Отзыв и полиморфная ссылка

`review.entity_id` вместе с `entity_type` остаётся полиморфной ссылкой, как в ERD: обычный FK на три разные таблицы выразить нельзя. Составной FK `(order_id, client_id) → order` фиксирует, что отзыв оставляет клиент этого заказа (BR-9.2). Триггер `review_target_check` проверяет сам объект: отзыв на заказ ссылается на свой `order_id`, ресторан совпадает с рестораном заказа, блюдо входит в `order_structure` этого заказа (BR-9.1, BR-9.2). Уникальность `(order_id, entity_type, entity_id)` реализует BR-9.5.

## CHECK-ограничения

| Таблица | Столбец | Условие | BR | Обоснование |
|---|---|---|---|---|
| client | password | password ~ '^[0-9a-f]{32}$' | BR-2.3 | Пароль хранится как MD5-хэш — ровно 32 шестнадцатеричных символа, не в открытом виде |
| restaurant | rating | rating between 0 and 5 | BR-4.2 | Рейтинг ресторана — число от 0 до 5 |
| restaurant | work_start, work_end | work_end > work_start | BR-4.4 | Время закрытия позже времени открытия |
| product | price | price >= 0 | BR-5.3 | Цена блюда неотрицательна |
| product | rating | rating between 0 and 5 | BR-5.4 | Рейтинг блюда — от 0 до 5 |
| courier | coefficient | coefficient between 0.1 and 0.5 | BR-6.4 | Коэффициент курьера — от 0.1 до 0.5 включительно |
| courier | status, dismissal_date | (status = 'уволен' and dismissal_date is not null) or (status <> 'уволен' and dismissal_date is null) | BR-6.3, BR-11.3 | У уволенного курьера есть дата увольнения, у работающего её нет |
| courier | hire_date, dismissal_date | dismissal_date >= hire_date | BR-6.1, BR-6.3 | Дата увольнения не может быть раньше даты найма |
| courier_pay | month | month between 1 and 12 | BR-10.2, BR-10.3 | Выплата считается за календарный месяц |
| courier_pay | amount | amount >= 0 | BR-10.4 | Зарплата неотрицательна |
| courier_pay | coefficient_used | coefficient_used between 0.1 and 0.5 | BR-6.4, BR-10.2 | Применяется только допустимый коэффициент |
| order | order_amount | order_amount >= 0 | BR-7.10, BR-5.3 | Сумма без комиссии — стоимость блюд, она не может быть отрицательной |
| order | total_amount | total_amount >= 1000 | BR-1.8, BR-7.11 | Общая сумма заказа не менее 1000 ₽ |
| order | order_timestamp, delivery_timestamp | delivery_timestamp >= order_timestamp | BR-7.13 | Доставка не может закончиться раньше создания заказа |
| order | status, delivery_timestamp | status <> 'доставлен' or delivery_timestamp is not null | BR-7.12 | У доставленного заказа время доставки заполнено |
| order_structure | quantity | quantity > 0 | BR-7.15 | Количество — положительное число (может быть дробным) |
| review | rating | rating between 1 and 5 | BR-9.4 | Оценка отзыва — от 1 до 5 |


| Триггер | Таблица | BR | Что делает |
|---|---|---|---|
| order_structure_restaurant_check | order_structure | BR-7.3 | Блюдо из ресторана заказа |
| order_consistency_protect | order | BR-7.3, BR-8.4 | Нельзя сменить ресторан заказа с блюдами и сумму заказа с оплатами |
| product_restaurant_protect | product | BR-7.3 | Нельзя перенести заказанное блюдо в другой ресторан |
| payment_amount_check | payment | BR-8.4 | Сумма попытки = общая сумма заказа |
| review_target_check | review | BR-9.1, BR-9.2 | Отзыв только на сам заказ, его ресторан или блюдо из него |
| payment_sync_pay_status | payment → order | BR-8.7 | Пересчёт pay_status по попыткам оплаты |
| review_rating_change | review → product, restaurant | BR-9.6, BR-9.7 | Пересчёт рейтинга (FOOD-105) |

## UNIQUE-ограничения

| Таблица | Столбцы | BR | Обоснование |
|---|---|---|---|
| client | login | BR-2.2 | Логин уникален |
| client | phone_number | BR-2.2 | Телефон уникален |
| client_address | client_id, address_id (PK) | BR-2.5 | Один адрес нельзя привязать к клиенту дважды |
| restaurant | address_id | BR-3.3, BR-3.4 | Два ресторана не могут находиться по одному адресу |
| courier_pay | year, month, courier_id (PK) | BR-10.3 | Одна запись о зарплате на курьера за месяц |
| order | order_id, client_id | BR-9.2 | Нужен как цель составного FK из review (PostgreSQL требует UNIQUE на целевых столбцах); order_id и так уникален |
| order_structure | order_id, product_id (PK) | BR-7.16 | Одно блюдо не повторяется в заказе |
| payment | transaction_number | BR-8.3 | ID финансовой транзакции уникален |
| payment | order_id WHERE status = 'успех' (частичный уникальный индекс) | BR-8.1 | Не больше одной успешной попытки на заказ |
| review | order_id, entity_type, entity_id | BR-9.5 | Один отзыв на один объект в рамках заказа |

## FK-ограничения

| Таблица | Столбцы | → Таблица | BR | Обоснование |
|---|---|---|---|---|
| client_address | client_id | client | BR-2.4 | Привязка адреса к клиенту |
| client_address | address_id | address | BR-2.4 | Привязка к существующему адресу |
| restaurant | address_id | address | BR-3.3 | У ресторана ровно один адрес |
| product | product_category_id | product_category | BR-5.1 | Блюдо в одной категории |
| product | restaurant_id | restaurant | BR-5.1 | Блюдо принадлежит одному ресторану |
| courier_pay | courier_id | courier | BR-10.2 | Выплата существующему курьеру |
| order | client_id | client | BR-7.1, BR-7.2 | Заказ оформляет один клиент |
| order | restaurant_id | restaurant | BR-7.2 | Заказ из одного ресторана |
| order | courier_id | courier | BR-7.5 | Доставку выполняет один курьер |
| order | address_id | address | BR-7.4 | Адрес доставки существует |
| order | client_id, address_id | client_address | BR-7.4 | Адрес доставки — один из адресов этого клиента (ловушка 2) |
| order_structure | order_id | order | BR-7.14 | Позиция относится к заказу |
| order_structure | product_id | product | BR-7.14 | Позиция — существующее блюдо (ресторан блюда проверяет триггер, ловушка 3) |
| payment | order_id | order | BR-8.1 | Попытка оплаты относится к заказу (сумму проверяет триггер, ловушка 1) |
| review | client_id | client | BR-9.1 | Отзыв оставляет клиент |
| review | order_id, client_id | order | BR-9.2 | Отзыв на заказ этого клиента (ловушка 4) |


## NOT NULL (бизнес-обязательные)

 `NOT NULL` — по общему правилу BR-11.3: всё обязательно, если BR не говорит обратного.

## NULL (осознанно разрешено)

| Таблица | Столбец | BR | Почему NULL |
|---|---|---|---|
| address | apartment_office | BR-3.2, BR-11.3 | Квартира/офис необязательны (частный дом) |
| product | photo_url | BR-5.6, BR-11.3 | Фотография блюда необязательна |
| product | rating | BR-9.7 | Если отзывов нет, рейтинг — NULL |
| restaurant | rating | BR-9.7 | Если отзывов нет, рейтинг — NULL |
| courier | dismissal_date | BR-6.3, BR-11.3 | У работающего курьера нет даты увольнения |
| order | delivery_timestamp | BR-7.12, BR-11.3 | Заполняется, когда заказ получает статус доставлен, до этого NULL|
| review | photo_url | BR-9.3, BR-11.3 | Фотография к отзыву необязательна |

## DEFAULT и GENERATED

| Таблица | Столбец | Что | BR | Обоснование |
|---|---|---|---|---|
| все | *_id | exts.uuid_generate_v4() | BR-11.1 | Все ID — UUID |
| courier | coefficient | 0.1 | BR-6.5 | Начальный коэффициент нового курьера — 0.1 |
| order | order_timestamp | localtimestamp | BR-7.1, BR-11.2 | Время создания заказа — время сервера |
| payment | transaction_timestamp | localtimestamp | BR-8.2, BR-11.2 | Время транзакции — время сервера |
| review | review_timestamp | localtimestamp | BR-9.3, BR-11.2 | Дата отзыва — время сервера |
| order | commission | round(order_amount * 0.10, 2) | BR-1.4, BR-7.10 | Комиссия — ровно 10% от суммы без комиссии |
| order | total_amount | order_amount + round(order_amount * 0.10, 2) | BR-1.5, BR-7.10 | Общая сумма = сумма без комиссии + комиссия |

Почему `GENERATED`, а не обычные столбцы с `CHECK`: проверка `commission = order_amount * 0.1` ломается на копейках (1234.55 × 0.1 = 123.455, а в `numeric(10,2)` хранится 123.46). Вычисляемый столбец считает значение сам, записать неверную сумму нельзя. `total_amount` повторяет формулу комиссии, потому что вычисляемый столбец не может ссылаться на другой вычисляемый столбец.

## Нормализация (3НФ)

Все таблицы в 3НФ. Атрибуты атомарны: адреса клиента, состав заказа и попытки оплаты вынесены в отдельные таблицы (1НФ). В таблицах с составным ключом каждый неключевой атрибут зависит от всего ключа: `quantity` — от пары «заказ + блюдо», `amount` и `coefficient_used` в `courier_pay` — от «год + месяц + курьер» (2НФ). Транзитивных зависимостей нет: каждый атрибут описывает только свою сущность, а ресторан позиции заказа не дублируется в `order_structure`, его определяет блюдо (3НФ).

Особые случаи:
- `commission` и `total_amount` вычисляются из `order_amount`, но сделаны `GENERATED`: изменить их вручную нельзя, поэтому расхождений и аномалий обновления нет.
- `product.rating` и `restaurant.rating` — осознанная денормализация ради скорости чтения: меню показывается постоянно, а считать среднее по отзывам каждый раз дорого. Актуальность поддерживает триггер `rating_change`.
- `order.pay_status` — агрегат по попыткам оплаты, его поддерживает триггер (BR-8.7).
- `entity_type` + `entity_id` в `review` описывают сам отзыв и 3НФ не нарушают; целостность обеспечена FK, UNIQUE и триггером (ловушка 4).

## Повторный вызов `insert_test_data`

Повторный вызов `insert_test_data(value)` добавляет новую порцию данных и не трогает существующие (решение для проверки C.9). Новые записи получают новые UUID, а уникальные поля (логины, телефоны, адреса, названия ресторанов, номера транзакций) строятся с учётом уже существующих строк, поэтому конфликтов не возникает. Чтобы начать с чистой базы, сначала вызывается `erase_test_data()`.
