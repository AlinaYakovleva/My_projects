Задание 1
Имеется три таблицы: customers, transactions, merchants (клиенты, транзакции и магазины, соответственно). Необходимо написать запросы и предложить визуализацию (где основной пользователь - Менеджер) для:

1.1 Определения регионов, в которых клиенты потратили больше всего средств в текущем году.

SELECT 
	merchant_region,
	sum(transaction_sum) as transaction_sum
from
	(
	select 
		Transactions.transaction_id as transaction_id,
		Transactions.merchant_id as merchant_id,
		Transactions.transaction_sum as transaction_sum,
		Transactions.transaction_dttm as transaction_dttm,
		Transactions.customer_id as customer_id,
		Merchants.merchant_region as merchant_region
	from Transactions
	left join Merchants
	on Transactions.merchant_id=Merchants.merchant_id
	)
WHERE transaction_dttm > '2022-01-01'
group by merchant_region
ORDER by transaction_sum DESC 

1.2 Определения, в каких категориях магазинов самый высокий средний чек транзакции

SELECT 
	merchant_type_id,
	avg(transaction_sum) as avg_transaction_sum
from
	(
	select 
		Transactions.transaction_id as transaction_id,
		Transactions.merchant_id as merchant_id,
		Transactions.transaction_sum as transaction_sum,
		Transactions.transaction_dttm as transaction_dttm,
		Transactions.customer_id as customer_id,
		Merchants.merchant_type_id as merchant_type_id
	from Transactions
	left join Merchants
	on Transactions.merchant_id=Merchants.merchant_id
	)
group by merchant_type_id
ORDER by avg_transaction_sum DESC 
-- limit 3 (если необходимо составить ограниченный список, например, топ-3 категорий магазинов с высоким средним чеком)


1.3 Анализа характера и частоты транзакций клиентов, основываясь на их возрасте

SELECT
	STRFTIME('%Y', transaction_dttm) as transaction_dttm,
	category_age,
	merchant_type_id,
	count(transaction_id) as count_transactions,
	avg(transaction_sum) as avg_transaction_sum
from
	(
	select 
		Transactions.transaction_id as transaction_id,
		Transactions.merchant_id as merchant_id,
		Transactions.transaction_sum as transaction_sum,
		Transactions.transaction_dttm as transaction_dttm,
		Transactions.customer_id as customer_id,
		Merchants.merchant_type_id as merchant_type_id,
		Customers.customer_age as customer_age,
		case 
		when customer_age > 0 and customer_age < 20 then '0-20'
		when customer_age >= 20 and customer_age < 30 then '20-30'
		when customer_age >= 30 and customer_age < 40 then '30-40'
		when customer_age >= 40 and customer_age < 50 then '40-50'
		when customer_age >= 50 then '>50'
		else 'anomaly'
	end as category_age
	from Transactions
	left join Merchants
	on Transactions.merchant_id=Merchants.merchant_id
	left join Customers
	on Transactions.customer_id=Customers.customer_id
	)
group by 	
	STRFTIME('%Y', transaction_dttm),
	category_age,
	merchant_type_id
ORDER by transaction_dttm asc,
	category_age Asc, 
	count_transactions DESC 

Задание 1.1
необходимо подумать и предложить вычисления (метрики, показатели и тд), результаты которых будут нести какой-то смысл. Описать или приложить графиком пример визуализации этих данных для дашборда, который будет использовать менеджер, отвечающий за развитие бизнеса.

Из представленных данных, на мой взгляд Менеджеру будут интересны следующие показатели:
- Выручка за период (день/неделя/месяц),
- средний чек за период,
- количество покупок,
- LTV (выручка от новых пользователей/количество новых пользователей за период),
- ARPPU.
Также необходимо отслежить данные показатели не только по бизнесу в целом, но и в разрезе регионов, магазинов, типов продукта, кагорт пользователей.

В моем примере дашборда в верхней части представлены вышеуказанные метрики, далее представлен график с динамикой выручки по дням за мериод (месяц), затем расположены 4 барплота, демонстрирующие прибыльность (показатель выручки) и популярность (кол-во покупок) в разрезе магазинов и типа продукта. Графики, расположенные справа, демонстрируют прибыльность и популярность бизнеса у разных возрастных когорт пользователей (возможно, такой анализ окажется полезным для таргетинга).

Дашборд доступен по ссылке:
https://public.tableau.com/app/profile/alina5007/viz/Dashboardfortest/Dashboard1?publish=yes

Задание 2
2.1 Написать SQL-запрос для поиска задублированных в результате ошибки транзакций
Данные:
purchases:
○ transaction_id
○ datetime
○ amount
○ user_id

SELECT *
FROM 
	(
	SELECT 
		transaction_id,
		amount, 
		datetime, 
		user_id,
		row_number() over transactions as row_numbers
	from purchases 
	window transactions as 
		(
		partition by transaction_id 
		)
	) as duplicates
Where 
	row_numbers > 1
Order by 
	transaction_id asc


2.2 Написать SQL-запрос для построения воронки перехода из установки в оформление пробного периода и в покупку платной версии приложения в разрезе стран. На одного юзера возможна только одно оформление пробного периода и одна
покупка платной версии. Покупка возможна только после истечения срока пробного периода. На выходе должна получится таблица с колонками “country”, “installs”, “trials”, “purchases”, “conversion_rate_to_trial”, “conversion_rate_to_purchase”
Схема данных:
events:
○ transaction_id
○ datetime
○ event_type (значение может быть либо “instal”, либо “trial”, либо “purchase”)
○ user_id
○ country


SELECT 
	country,
	sum(installs) as installs,
	sum(trials) as trials,
	sum(purchaces) as purchaces,
	round(1.00*sum(trials)/sum(installs)*100.00) as conversion_rate_to_trial,          -- конверсия из установки в оформление пробного периода (в %)
	round(1.00*sum(purchaces)/sum(trials)*100.00) as conversion_rate_to_purchase       -- конверсия из оформления пробного периода в покупку (в %)
from
	(
	SELECT
	event_type,
	user_id,
	country,
	event_type = 'installs' as installs,
	event_type = 'trials' as trials,
	event_type = 'purchaces' as purchaces
	from events
	) as ttt
group by country


