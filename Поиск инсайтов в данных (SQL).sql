Задание: найти интересные инсайты 

Данные:
orders:
Id - id заказа
created_at - timestamp создания заказа на сайте
delivery_window_id - id слота доставки
item_total - Сумма всех товаров в корзине (средний чек)
promo_total - Сумма промо-кода на товары в корзине
cost - Изначальная стоимость доставки
total_cost - Финальная стоимость доставки (отличается, если был применен промо-код на доставку. Если промокода не было, то cost=total_cost)
ship_address_id - id адреса доставки (ключ к addresses.id)
shipped_at - timestamp доставки заказа
state - состояние доставки (shipped, canceled и тд)
store_id - id магазина
total_quantity - Количество единиц товара
user_id - id пользователя

delivery_windows:
id - id слота доставки (ключ к orders.delivery_window_id)
starts_at - timestamp начала слота доставки
ends_at - timestamp конца слота доставки
store_id - ID магазина 

stores:
id - ID магазина
city - ID города
retailer_id - ID ритейлера

replacements:
item_id - id товара, который был заменен
order_id - id заказа, в котором была замена
state - статус (замена)

cancellations
item_id - id товара, который был отменен
order_id - id заказа, в котором была отмена
state - статус (отмена)

Этапы решения и выводы:


    retailer_id,
    store_id,
    user_id,
    id,
    item_total,
    created_at,
    shipped_at,
    delivery_window_id,
    cost,
    total_cost,
    state,
    total_quantity,
    total_weight,
    (total_cost - cost) as promo_delivery,
    promo_total,
    product_cancel,
    product_replaced,
    case 
        when product_cancel > 0 then 1
        when product_replaced > 0 then 1
        else 0
    end as replace_or_not
from 
    (
    select 
        ext_orders.city as city,
        ext_orders.retailer_id as retailer_id,
        ext_orders.store_id as store_id,
        ext_orders.user_id as user_id,
        ext_orders.id as id,
        ext_orders.item_total as item_total,
        ext_orders.created_at as created_at,
        ext_orders.cost as cost,
        ext_orders.delivery_window_id as delivery_window_id,
        ext_orders.total_cost as total_cost,
        ext_orders.promo_total as promo_total,
        ext_orders.shipped_at as shipped_at,
        ext_orders.state as state,
        ext_orders.total_quantity as total_quantity,
        ext_orders.total_weight as total_weight,
        (ext_orders.total_cost - ext_orders.cost) as promo_delivery,
        replace_and_cancel.product_cancel as product_cancel,
        replace_and_cancel.product_replaced as product_replaced 			
    from
        (
        select 
            orders.id as id,
            orders.created_at as created_at,
            orders.delivery_window_id as delivery_window_id,
            orders.item_total as item_total,
            orders.promo_total as promo_total,
            orders.cost as cost,
            orders.total_cost as total_cost,
            orders.ship_address_id as ship_address_id,
            orders.shipped_at as shipped_at,
            orders.state as state,
            orders.store_id as store_id,
            orders.total_quantity as total_quantity,
            orders.total_weight as total_weight,
            orders.user_id as user_id,
            stores.city as city,
            stores.retailer_id as retailer_id
        from orders
        left join stores
        ON 
            orders.store_id=stores.id
        ) as ext_orders
    left join 
        (
        select 
            cancellations_pr.order_id as order_id,
            cancellations_pr.product_cancel as product_cancel,
            replacements_pr.product_replaced as product_replaced
        from
            (
            select 
                order_id,
                count(distinct item_id) as product_cancel
            from cancellations
            group by order_id
            ) as cancellations_pr
        full join 
            (
            select 
                order_id,
                count(distinct item_id) as product_replaced
            from replacements
            group by order_id
            ) as replacements_pr
        on cancellations_pr.order_id = replacements_pr.order_id
        ) as replace_and_cancel
    on ext_orders.id=replace_and_cancel.order_id
) as orders_with_cancels_goods
)

2) Формирование таблицы с показателями в разрезе города и ритейлера

create view retailers_analysis as (
select 
	city,
	retailer_id,
	percentile_disc(0.5) within group (order by del_interval) as median_del_interval,
	round(avg(del_interval)::numeric,2) as avg_del_interval,
	round((avg(del_interval)-2.58*stddev(del_interval)/sqrt(count(del_interval)))::numeric,2) as l_conf_interval,
	round((avg(del_interval)+2.58*stddev(del_interval)/sqrt(count(del_interval)))::numeric,2) as up_conf_interval,
	sum(replace_or_not) as count_orders_with_canc,
	count(id) as  count_orders,
	round(1.00*sum(replace_or_not)/count(id)*100.00::numeric,2) as perc_cancel_ord,
	round(sum(item_total)) as revenue,
	round(avg(item_total)) as avg_check,
	round(avg(cost)) as avg_delivery_value,
	round(sum(total_quantity)) as avg_quantity,
	round(avg(promo_delivery)) as avg_promo_delivery,
	round(avg(promo_total)) as avg_promo_total,
	round(avg(promo_total)/avg(item_total)*-100.00) as perc_promo_total,
	round(avg(promo_delivery)/avg(cost)*-100.00) as perc_promo_delivery
from orders_base
where state != 'canceled' and retailer_id = '1'
group by 
	city,
	retailer_id
order by retailer_id asc, city asc
)

    • наибольшее количество заказов в разрезе города - №1, ритейлера - № 1
    • у всех ритейлеров большой процент заказов с фактов возврата/замены товара. Больше, чем в половине заказов был факт замены/возврата товара
    • у ритейлера № 1 в городе № 1 самый высокий показатель среднего чека и количества заказов (выручка, соответственно), однако показатель средней суммы примененных промокодов (на товары и на доставку, в табл. perc_promo_total, avg_promo_total, perc_promo_delivery, avg_promo_delivery) на заказ не отличается или ниже, чем у  других ритейлеров, что может негативно сказаться на потребительском спросе (при учете высокого процента заменты товаров в заказах)
    • показатели медианы (median_del_interval) и среднего интервала времени от момента создания заказа до момента доставки (avg_del_interval) резко различаются, в связи с чем можно сделать вывод о наличии аномалий.

3) Анализ временного интервала (del_interval) от момента создания заказа до момента доставки
 
select 
    city,
    retailer_id,
    group_interval,
    count_users,
    count_orders,
    round(1.00*count_orders/retail_all_orders*100.00::numeric,2) as perc_orders,
    count_orders_with_canc,
    perc_cancel_ord,
    avg_check,
    avg_promo_delivery,
    avg_promo_total,
    retail_all_orders,
    retail_perc,
    retail_avg_check,
    retail_promo_delivery,
    retail_promo_total,
    (avg_check-retail_avg_check)/retail_avg_check*100.00 as diff_avg_check,
    (perc_cancel_ord-retail_perc) as diff_perc_cancel,
    (avg_promo_total-retail_promo_total)/retail_promo_total*100.00 as diff_promo_total,
    (avg_promo_delivery-retail_promo_delivery)/retail_promo_delivery*100.00 as diff_promo_delivery
from 
    (
    select 
    interval_analysis.city as city,
    interval_analysis.retailer_id as retailer_id,
    interval_analysis.group_interval as group_interval,
    interval_analysis.count_users as count_users,
    interval_analysis.count_orders as count_orders,
    interval_analysis.count_orders_with_canc as count_orders_with_canc,
    interval_analysis.perc_cancel_ord as perc_cancel_ord,
    interval_analysis.avg_check as avg_check,
    interval_analysis.avg_promo_delivery as avg_promo_delivery,
    interval_analysis.avg_promo_total as avg_promo_total,
    retailers_analysis.count_orders as retail_all_orders,
    retailers_analysis.perc_cancel_ord as retail_perc,
    retailers_analysis.avg_check as retail_avg_check,
    retailers_analysis.avg_promo_delivery as retail_promo_delivery,
    retailers_analysis.avg_promo_total as retail_promo_total
    from 
        (
        select 
            city,
            retailer_id,
            group_interval,
            count(distinct user_id) as count_users,
            count(id) as count_orders,
            sum(replace_or_not) as count_orders_with_canc,
            round(1.00*sum(replace_or_not)/count(id)*100.00::numeric,2) as perc_cancel_ord,
            round(avg(item_total)) as avg_check,
            round(avg(promo_delivery)) as avg_promo_delivery,
            round(avg(promo_total)) as avg_promo_total
        from 
            (
            select 
                city,
                retailer_id,
                store_id,
                user_id,
                id,
                cost,
                item_total,
                total_cost,
                total_quantity,
                promo_total,
                promo_delivery,
                product_cancel,
                product_replaced,
                replace_or_not,
                del_interval,
                case 
                    when del_interval >= 0 and del_interval <= 5 then '1 [0-5 days]'
                    when del_interval > 5 and del_interval <= 50 then '2 [5-50 days]'
                    when del_interval > 50 and del_interval <= 100 then '3 [50-100 days]'
                    when del_interval > 100 and del_interval <= 200 then '4 [100-200 days]'
                    when del_interval > 200 and del_interval <= 300 then '5 [200-300 days]'
                    when del_interval > 300 and del_interval <= 400 then '6 [300-400 days]'
                    when del_interval > 400 then '7 [400 days and more]'
                    else '8[other]'
                end as group_interval
            from orders_base
            where state != 'canceled'
            ) as range_table
        where group_interval != '8[other]'
        group by 
            city,
            retailer_id,
            group_interval
        order by
            city asc,
            retailer_id asc,
            group_interval asc
        ) as interval_analysis
left join 
    retailers_analysis
on interval_analysis.city=retailers_analysis.city 
    and interval_analysis.retailer_id=retailers_analysis.retailer_id
    ) as table1
where count_orders > 10
order by  
    group_interval asc, 
       retailer_id asc, 
       city asc
       
       
В результате анализа временного интервала (del_interval) от момента создания заказа до момента доставки было выявлено:
    • в трех заказах отрицательная величина del_interval, что в реальности невозможно (баг?):

select *
from orders_base
where del_interval < 0


    • от 85% до 98% заказов (в зависимости от ритейлера) были доставлены в срок до 5 дней.
    • проблема аномально долгой доставки актуальна для ритейлера № 1 во всех городах (баг в ПО ритейлера?, баг в данных?), для ритейлера № 15 проблема актуальна в разрезе городов 1 и 2
    • наблюдается зависимость коэффициента отношения количества заказов с фактом замены/возврата товара к общему количеству заказов (perc_cancel_ord) и срока доставки: коэффициент увеличивается в     3) В результате анализа временного интервала (del_interval) от момента создания заказа до момента доставки было выявлено (Script3-intervals, таблица table3-intervals):
    • в трех заказах (980548, 980564, 980590) отрицательная величина del_interval, что в реальности невозможно (баг?):
select *
from orders_base
where del_interval < 0
    • от 85% до 98% заказов (в зависимости от ритейлера) были доставлены в срок до 5 дней.
    • проблема аномально долгой доставки актуальна для ритейлера № 1 во всех городах (баг в ПО ритейлера?, баг в данных?), для ритейлера № 15 проблема актуальна в разрезе городов 1 и 2
    • наблюдается зависимость коэффициента отношения количества заказов с фактом замены/возврата товара к общему количеству заказов (perc_cancel_ord) и срока доставки: коэффициент увеличивается в интервалах с аномально долгой доставкой и уменьшается в тех заказах, где доставка осуществлена в интервал 0-5 дней. 
    • показатели промокодов на доставку и товары в корзине также варьируются разрезе интервалов по сравнению с средней суммой промокодов по ритейлеру:
0-50 дней - незначительно меньше используются промокоды
50-100 дней - больше используются промокоды на товары и меньше на доставку
100 -300 дней  - больше используются промокоды на товары и доставку
от 300 дней - меньше промокоды на товары

4) Формирование списка клиентов, у которых в заказах наибольшее количество замененных/возвращенных товаров (топ-30 недовольных клиентов: 

select 
    city,
    array_agg(distinct retailer_id) as retailer_id,
    array_agg(distinct store_id) as store_id,
    user_id,
    count(id) as count_orders,
    round(sum(item_total)) as revenue,
    round(avg(item_total)) as avg_check,
    sum(promo_delivery) as promo_delivery,
    sum(promo_total) as promo_total,
    sum(product_cancel) as sum_product_cancel,
    sum(product_replaced) as sum_product_replaced
from 
    orders_base
where 
    product_replaced > 0
    or product_cancel > 0
group by 
    city,
    user_id
order by
    sum_product_cancel desc,
    sum_product_replaced desc
limit 30

Хочется отметить, что при большом количестве заказов и крупных суммах выручки по каждому клиенту, суммы промокодов остаются незначительными (возможно необходимо поощрить недовольных клиентов). Также, в таблице видно, что пользователи совершают заказы (с возвратами) в основном у ритейлера № 1 и № 15, магазины: 11,12,21.

5) Формирование сводной таблицы в разрезе магазинов:

select 
	array_agg(distinct retailer_id) as retailer_id,
	store_id,
	count(distinct user_id) as count_users,
	count(id) as count_orders,
	round(1.00*count(id)/count(distinct user_id)::numeric,2) as perc_orders,
	round(sum(item_total)) as revenue,
	round(avg(item_total)) as avg_check,
	sum(replace_or_not) as replace_or_not,
	round(1.00*sum(replace_or_not)/count(id)*100.00::numeric,2) as perc_cancel_ord,
	sum(product_cancel) as sum_product_cancel,
	sum(product_replaced) as sum_product_replaced
from 
	orders_base
group by 
	store_id
order by perc_cancel_ord desc

список отобран по убыванию процента заказов с возвратами в общей доле заказов. Самый большой коэффициент у ритейлера № 15. В колонке perc_orders отражается среднее количество покупок на каждого пользователя. Видна зависимость: чем больше процент возвратных заказов, тем меньше показатель perc_orders, чем меньше процент возвратных заказов, тем чаще клиент возвращается в продукт.

