WITH 
-- Update SBC part numbers to match what is in ASC item ID
SBCINV AS (
	SELECT *
			,CASE 
				WHEN part_number LIKE 'BPSA-%' THEN 'PSA-' + RIGHT(part_number,LEN(part_number)-5) 
				WHEN part_number LIKE 'BPST-%' THEN 'PST-' + RIGHT(part_number,LEN(part_number)-5) 
				WHEN part_number LIKE '%-1414DSC' THEN LEFT(part_number,LEN(part_number)-3)
				ELSE part_number
				END AS asc_part_number
	FROM [SBC_Historical].[dbo].[SBC_INV_ComponentsInventory] --Using components only inventory table for transfers, no kits should be transferring between buildings
),

-- Add daily sales calculation. Assuming 25 days a month except for the last month.
DAILYSALES AS (
	SELECT *
			,CASE 
				WHEN [store1_sold_lastYear]+[store1_sold_thisYear]<=0 THEN 0
				ELSE ROUND(([store1_sold_lastYear]+[store1_sold_thisYear])/(300+(25*(MONTH(GETDATE())-1))+DAY(GETDATE())),2) 
			 END AS [Bedford Daily Sales]
			,CASE
				WHEN [store2_sold_lastYear]+[store2_sold_thisYear]<=0 THEN 0
				ELSE ROUND(([store2_sold_lastYear]+[store2_sold_thisYear])/(300+(25*(MONTH(GETDATE())-1))+DAY(GETDATE())),2) 
			 END AS [Hodgkins Daily Sales]
	FROM SBCINV
),

-- Adding days on hand using daily sales and inventory qty on hand. Committed not considered available qty on hand. 
DAYSONHAND AS (
	SELECT *
			,CASE	
				WHEN [Bedford Daily Sales] <= 0 THEN 999999
				ELSE round([store1_quantity]/[Bedford Daily Sales],2)
			 END AS [Bedford Days On Hand]
			 ,CASE	
				WHEN [Hodgkins Daily Sales] <= 0 THEN 999999
				ELSE round([store2_quantity]/[Hodgkins Daily Sales],2)
			 END AS [Hodgkins Days On Hand]
	FROM DAILYSALES
), 

-- Adding locations that has need for item based on agreed upon criteria
INV_LOCATION AS (
	SELECT   [DATE]
			,[part_number]
			,CASE	
				WHEN category IN ('BRG','PLX') THEN 'BEDFORD PARK'
				WHEN category IN ('NXT','SCR') THEN 'HODGKINS'
				WHEN [store2_sold_lastYear]+[store2_sold_thisYear]+[store1_sold_lastYear]+[store1_sold_thisYear] = 0 AND [store2_quantity]<[store1_quantity] THEN 'HODGKINS'
				WHEN [store2_sold_lastYear]+[store2_sold_thisYear]+[store1_sold_lastYear]+[store1_sold_thisYear] = 0 AND [store2_quantity]>=[store1_quantity] THEN 'BEDFORD PARK'
				WHEN [Bedford Days On Hand]<[Hodgkins Days On Hand] THEN 'BEDFORD PARK'
				WHEN [Hodgkins Days On Hand]<[Bedford Days On Hand] THEN 'HODGKINS'
				WHEN [Hodgkins Days On Hand]=[Bedford Days On Hand] AND [Bedford Daily Sales]<[Hodgkins Daily Sales] THEN 'HODGKINS'
				WHEN [Hodgkins Days On Hand]=[Bedford Days On Hand] AND [Bedford Daily Sales]>[Hodgkins Daily Sales] THEN 'BEDFORD PARK'
				WHEN [Hodgkins Days On Hand]=[Bedford Days On Hand] AND [Bedford Daily Sales]=[Hodgkins Daily Sales] AND [store2_quantity]<=[store1_quantity] THEN 'HODGKINS'
				WHEN [Hodgkins Days On Hand]=[Bedford Days On Hand] AND [Bedford Daily Sales]=[Hodgkins Daily Sales] AND [store2_quantity]>[store1_quantity] THEN 'BEDFORD PARK'
				ELSE 'ERROR'
			 END AS [CONTAINER LOCATION]
			,CASE	
				WHEN [store1_quantity] <= 0 AND [store2_quantity] <=0 THEN 'NO TRANSFER NEEDED'
				WHEN [Bedford Daily Sales] >= 1 AND [Hodgkins Daily Sales] >= 1 AND [Bedford Days On Hand] >= 60 AND [Hodgkins Days On Hand] >= 60 THEN 'NO TRANSFER NEEDED'
				WHEN category IN ('SPS','BRG','PLX','PDS') AND [store2_quantity] <=0 THEN 'NO TRANSFER NEEDED'
				WHEN category IN ('SPS','BRG','PLX','PDS') THEN 'BEDFORD PARK'
				WHEN category IN ('SCR') AND [store1_quantity] <=0 THEN 'NO TRANSFER NEEDED'
				WHEN category IN ('SCR') THEN 'HODGKINS'
				WHEN part_status IN ('NEW','NOO','NEWSTK') THEN
					CASE 
						WHEN [store2_quantity] < 0 AND [store2_committed_quantity] > 0 AND [store1_quantity] > 0 THEN 'HODGKINS'
						WHEN [store1_quantity] < 0 AND [store1_committed_quantity] > 0 AND [store2_quantity] > 0 THEN 'BEDFORD PARK'
						WHEN [store1_quantity] <=10 AND [store2_quantity] <= 10 THEN 'NO TRANSFER NEEDED'
						WHEN ABS([store2_quantity]-[store1_quantity])/(([store2_quantity]+[store1_quantity])/2.0) <= 1.0 THEN 'NO TRANSFER NEEDED'
						WHEN [store1_quantity] >= 30 AND [store2_quantity] >= 30 THEN 'NO TRANSFER NEEDED'
						WHEN [store1_quantity] < [store2_quantity] THEN 'BEDFORD PARK'
						WHEN [store2_quantity] < [store1_quantity] THEN 'HODGKINS'
						ELSE 'ERROR'
					END
				WHEN [Bedford Daily Sales] <= 0 AND [Hodgkins Daily Sales] <= 0 THEN 
					CASE 
						WHEN [store2_quantity] < 0 AND [store2_committed_quantity] > 0 AND [store1_quantity] > 0 THEN 'HODGKINS'
						WHEN [store1_quantity] < 0 AND [store1_committed_quantity] > 0 AND [store2_quantity] > 0 THEN 'BEDFORD PARK'
						WHEN [store1_quantity] <=10 AND [store2_quantity] <= 10 THEN 'NO TRANSFER NEEDED'
						WHEN ABS([store2_quantity]-[store1_quantity])/(([store2_quantity]+[store1_quantity])/2.0) <= 1.0 THEN 'NO TRANSFER NEEDED'
						WHEN [store1_quantity] >= 30 AND [store2_quantity] >= 30 THEN 'NO TRANSFER NEEDED'
						WHEN [store1_quantity] < [store2_quantity] THEN 'BEDFORD PARK'
						WHEN [store2_quantity] < [store1_quantity] THEN 'HODGKINS'
						ELSE 'ERROR'
					END
				WHEN [Bedford Daily Sales] <= 0 AND [Hodgkins Daily Sales] > 0 THEN 
					CASE	
						WHEN [store1_quantity] <= 0 THEN 'NO TRANSFER NEEDED'
						WHEN [Hodgkins Days On Hand] <= 10 AND [store1_quantity] > 0 THEN 'HODGKINS'
						WHEN [Hodgkins Days On Hand] > 10 AND [store2_quantity] < 60 THEN 'HODGKINS'
						WHEN [Hodgkins Days On Hand] > 10 AND [store2_quantity] >= 60 THEN 'NO TRANSFER NEEDED'
						ELSE 'ERROR'
					END
				WHEN [Hodgkins Daily Sales] <= 0 AND [Bedford Daily Sales] > 0 THEN 
					CASE	
						WHEN [store2_quantity] <= 0 THEN 'NO TRANSFER NEEDED'
						WHEN [Bedford Days On Hand] <= 10 AND [store2_quantity] > 0 THEN 'BEDFORD PARK'
						WHEN [Bedford Days On Hand] > 10 AND [store1_quantity] < 30 THEN 'BEDFORD PARK'
						WHEN [Bedford Days On Hand] > 10 AND [store1_quantity] >= 30 THEN 'NO TRANSFER NEEDED'
						ELSE 'ERROR'
					END
				WHEN [store1_quantity] >= 6 AND [Hodgkins Days On Hand] = [Bedford Days On Hand] THEN 'NO TRANSFER NEEDED'
				WHEN [store1_quantity] >= 10 AND ([Hodgkins Days On Hand]+[Bedford Days On Hand]) > 0 AND ABS([Hodgkins Days On Hand]-[Bedford Days On Hand])/(([Hodgkins Days On Hand]+[Bedford Days On Hand])/2.0) between 0.0 and 1.0 THEN 'NO TRANSFER NEEDED'
				WHEN [store1_quantity] <= 10 AND [store2_quantity] <= 10 THEN 'NO TRANSFER NEEDED'
				WHEN [store1_quantity] < 6 AND [store2_quantity] > 0 THEN 'BEDFORD PARK'
				WHEN [store2_quantity] <= 0 AND [store2_committed_quantity] > 0 AND [store1_quantity] > 10 THEN 'HODGKINS'
				WHEN [Hodgkins Days On Hand] < [Bedford Days On Hand] THEN 'HODGKINS'
				WHEN [Bedford Days On Hand] < [Hodgkins Days On Hand] THEN 'BEDFORD PARK'
				ELSE 'ERROR'
			 END AS [TRANSFER TO]
			,'' AS MIN_TRANSFER
			,'' AS MAX_TRANSFER
			,'' AS LEFTOVER
			,'' AS TRANSFER_QTY
			,'' AS TRANSFER_NOTES
			,[manufacturer]
			,[category]
			,[part_status]
			,[kit_flag]
			,[store1_quantity]
			,[store2_quantity]
			,[store1_committed_quantity]
			,[store2_committed_quantity]
			,[Bedford Daily Sales]
			,[Hodgkins Daily Sales]
			,[Bedford Days On Hand]
			,[Hodgkins Days On Hand]
			,[store1_sold_thisYear]
			,[store1_sold_lastYear]
			,[store2_sold_thisYear]
			,[store2_sold_lastYear]
			,[store1_lastSale_date]
			,[store2_lastSale_date]
			,[store1_lostSales]
			,[store2_lostSales]
			-- Add store/item locations 
	FROM DAYSONHAND
)

SELECT *
FROM INV_LOCATION

