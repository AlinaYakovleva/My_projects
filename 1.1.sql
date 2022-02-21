SELECT 
round(sum(round(sale_amount))/count(sale_amount))
FROM 
	orders
	
	