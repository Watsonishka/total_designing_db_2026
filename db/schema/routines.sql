set search_path to rezyapova_food, exts;

create or replace procedure add_product(
    p_product_name varchar,
    p_product_category_id uuid,
    p_restaurant_id uuid,
    p_price numeric,
    p_description text,
    p_status product_status,
    p_photo_url text default null,
    p_rating numeric default null
)
language plpgsql
set search_path = rezyapova_food, exts
as $$
begin
    insert into product(product_name, product_category_id, restaurant_id, price, description, photo_url, rating, status)
    values (p_product_name, p_product_category_id, p_restaurant_id, p_price, p_description, p_photo_url, p_rating, p_status);
end;
$$;

create or replace function get_statistic() returns table (
    restaurant_name   varchar,
    best_product_name varchar,
    total_amount      numeric,
    avg_amount        numeric,
    best_user         varchar
)
language sql 
volatile 
set search_path = rezyapova_food, exts
as $$
    with delivered as materialized (
        select order_id, restaurant_id, client_id, total_amount
        from "order"
        where status = 'доставлен'
    ),
    totals as (
        select restaurant_id,
               sum(total_amount)           as sum_total,
               round(avg(total_amount), 2) as avg_total
        from delivered
        group by restaurant_id
    ),
    product_sales as (
        select d.restaurant_id, os.product_id, sum(os.quantity) as qty
        from delivered d
        join order_structure os on os.order_id = d.order_id
        group by d.restaurant_id, os.product_id
    ),
    top_products as (
        select s.restaurant_id, array_agg(s.product_id) as candidates
        from product_sales s
        join (select restaurant_id, max(qty) as qty
              from product_sales
              group by restaurant_id) leaders using (restaurant_id, qty)
        group by s.restaurant_id
    ),
    best_product as materialized (
        select restaurant_id,
               candidates[1 + floor(random() * cardinality(candidates))::int] as product_id
        from top_products
    ),
    client_orders as (
        select restaurant_id, client_id, count(*) as cnt
        from delivered
        group by restaurant_id, client_id
    ),
    top_clients as (
        select s.restaurant_id, array_agg(s.client_id) as candidates
        from client_orders s
        join (select restaurant_id, max(cnt) as cnt
              from client_orders
              group by restaurant_id) leaders using (restaurant_id, cnt)
        group by s.restaurant_id
    ),
    best_client as materialized (
        select restaurant_id,
               candidates[1 + floor(random() * cardinality(candidates))::int] as client_id
        from top_clients
    )
    select r.restaurant_name,
           p.product_name,
           coalesce(t.sum_total, 0),
           coalesce(t.avg_total, 0),
           c.login 
    from restaurant r
    left join totals t  on t.restaurant_id  = r.restaurant_id
    left join best_product bp on bp.restaurant_id = r.restaurant_id
    left join product p on p.product_id = bp.product_id
    left join best_client bc on bc.restaurant_id = r.restaurant_id
    left join client c on c.client_id = bc.client_id
    order by r.restaurant_name;
$$;

create or replace procedure courier_salary()
language plpgsql
set search_path = rezyapova_food, exts
as $$
declare
    v_month timestamp:= date_trunc('month', localtimestamp);
begin
    perform 1 from courier order by courier_id for update;
    with month_totals as materialized (
        select c.courier_id,
               coalesce(cp.coefficient_used, c.coefficient) as used,
               count(o.order_id) as deliveries,
               coalesce(sum(o.commission), 0) as commissions
        from courier c
        left join courier_pay cp
               on cp.courier_id = c.courier_id
              and cp.year  = extract(year  from v_month)
              and cp.month = extract(month from v_month)
        left join "order" o
               on o.courier_id = c.courier_id
              and o.status = 'доставлен'
              and o.order_timestamp >= v_month
              and o.order_timestamp <  v_month + interval '1 month'
        group by c.courier_id, c.coefficient, cp.coefficient_used
    ),
    paid as (
        insert into courier_pay(year, month, courier_id, amount, coefficient_used)
        select extract(year from v_month)::int, extract(month from v_month)::int,
               courier_id, round(commissions * used, 2), used
        from month_totals
        on conflict (year, month, courier_id) do update set amount = excluded.amount
        returning courier_id
    )
    update courier c
    set coefficient = case when x.deliveries > 500 then 0.5
                           when x.deliveries > 250 then 0.3
                           when x.deliveries > 150 then 0.2
                           else 0.1 end
    from month_totals x
    join paid p using (courier_id)
    where c.courier_id = x.courier_id
      and c.status <> 'уволен';
end;
$$;

create or replace view how_much_money as
with recursive delivered as materialized (
    select date_trunc('month', order_timestamp)::date as month_start,
           sum(order_amount) as no_commission,
           sum(total_amount) as with_commission
    from "order"
    where status = 'доставлен'
    group by date_trunc('month', order_timestamp)::date
),
bounds as (
    select min(month_start) as first_month, max(month_start) as last_month
    from delivered
),
months (month_start) as (
    select first_month from bounds where first_month is not null
    union all
    select (m.month_start + interval '1 month')::date
    from months m
    cross join bounds b
    where m.month_start < b.last_month
),
salaries as (
    select make_date(year, month, 1) as month_start, sum(amount) as salary
    from courier_pay
    group by year, month
),
amounts as (
    select m.month_start,
           coalesce(d.no_commission, 0) as no_commission,
           coalesce(d.with_commission, 0) as with_commission,
           coalesce(d.with_commission - d.no_commission, 0) as commission,
           coalesce(s.salary, 0) as salary
    from months m
    left join delivered d using (month_start)
    left join salaries  s using (month_start)
),
comparison as (
    select *, lag(commission) over (order by month_start) as prev_commission
    from amounts
)
select to_char(month_start, 'YYYY-MM')::text as year_month,
       no_commission::numeric as sum_no_commission,
       with_commission::numeric as sum_with_commission,
       commission::numeric as commission,
       prev_commission::numeric as prev_commission,
       (commission - prev_commission)::numeric as commission_diff,
       salary::numeric as courier_pay,
       (commission - salary)::numeric as net_profit
from comparison
order by month_start;