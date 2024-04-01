/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20240129@Danny
	DB: DBCUST.bodb_licensee
	Description: END setting VS2, LG Charge Rate:
*/

USE bodb_licensee
GO

/*
DECLARE @VS2_ProductID INT, @LG_ProductID INT
DECLARE @VS2_PartyID INT, @LG_PartyID INT

SELECT @VS2_ProductID = Productid FROM Product3rd WITH(NOLOCK) WHERE ProductPrefix = 'VS2'
SELECT @LG_ProductID = Productid FROM Product3rd WITH(NOLOCK) WHERE ProductPrefix = 'LG'

SELECT @VS2_PartyID = PartyID FROM bodb_licensee.dbo.OAS_Party WITH(NOLOCK ) WHERE PartyName = 'VS2'
SELECT @LG_PartyID = PartyID FROM bodb_licensee.dbo.OAS_Party WITH(NOLOCK ) WHERE PartyName = 'LG'

-- GET ALL Setting to Update 

SELECT ChargeID INTO #ChargeID FROM OAS_ChargeInfo WITH(NOLOCK) WHERE ProductID IN (@LG_ProductID, @VS2_ProductID)
AND ToParty NOT IN (@VS2_PartyID, @LG_PartyID)
AND FromDate <= '2024-02-29' AND ToDate >= '2024-02-29'


UPDATE t
SET t.ToDate  = '2024-02-29'
FROM OAS_ChargeInfo t  WITH(ROWLOCK)
INNER JOIN #ChargeID u ON t.ChargeID = u.ChargeID

DROP TABLE #ChargeID

-- Remove Invoice setting of UnSupported products
DELETE from LA_InvoiceSetting with(rowlock) WHERE ProductId IN (@VS2_ProductID, @LG_ProductID)
*/

--------------------------------------------

GO

-- Delete setting VS2, LG after 2024/03/01
-- 5 rows 
DELETE  FROM OAS_ChargeInfo  WITH(ROWLOCK) WHERE ChargeID IN (10569,10574,10585,10592,10596)
-- 5 rows
DELETE FROM LA_ChargeInfo_SystemMapping WITH(ROWLOCK) WHERE ChargeID IN (10569,10574,10585,10592,10596)

-- Delete setting VS3(Old)
DECLARE @VS3_ProductID INT = 49

-- Remove Invoice setting of UnSupported products
-- 218 rows
DELETE from LA_InvoiceSetting with(rowlock) WHERE ProductId IN (@VS3_ProductID)
