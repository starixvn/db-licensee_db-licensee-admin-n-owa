/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240129@Danny
	DB: DBCUST.bodb_licensee
	Description: END setting VS3 Charge Rate:
*/

USE bodb_licensee
GO

-- DECLARE @VS3_PartyID INT, @VS3_ProductID INT

-- SELECT @VS3_ProductID = Productid FROM Product3rd WITH(NOLOCK) WHERE ProductPrefix = 'VS3'
-- SELECT @VS3_PartyID = PartyID FROM bodb_licensee.dbo.OAS_Party WITH(NOLOCK ) WHERE PartyName = 'VS3'


-- -- GET ALL Setting to Update 

-- SELECT ChargeID INTO #ChargeID FROM OAS_ChargeInfo WITH(NOLOCK) WHERE ProductID IN (@VS3_ProductID)
-- AND ToParty NOT IN (@VS3_PartyID)
-- AND FromDate <= '2024-02-29' AND ToDate >= '2024-02-29'


-- UPDATE t
-- SET t.ToDate  = '2024-02-29'
-- FROM OAS_ChargeInfo t  WITH(ROWLOCK)
-- INNER JOIN #ChargeID u ON t.ChargeID = u.ChargeID

-- DROP TABLE #ChargeID

-- Delete setting VS3(Old)
DECLARE @VS3_ProductID INT = 49

-- Remove Invoice setting of UnSupported products
-- 218 rows
DELETE from LA_InvoiceSetting with(rowlock) WHERE ProductId IN (@VS3_ProductID)


