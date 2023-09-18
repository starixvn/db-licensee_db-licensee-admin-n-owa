/*<info serverAlias="DBCUST-CustDB"></info>*/
/*
	Created: 20230918@Danny
	DB: DBCUST-CustDB
	Task: Change Allbet PlayCurrency Setting
*/
USE CustDB
GO

-- Get old data

/*

SELECT s.* 
INTO #data_old
FROM dbo.playcurrencysetting s WITH(NOLOCK) 
WHERE SiteID IN (SELECT x.SiteID FROM Site x WITH(NOLOCK) where x.SiteLabel = '789y')
	AND SportType=211
	AND FromDate <= GETDATE() AND Todate >= GETDATE()
	AND MemberCurrency IN (3,16,35,64) -- $US, US$, YEN, UT

-- Update Todate (Close old setting)
UPDATE s
SET	   s.ToDate = '2023-09-20'
FROM   dbo.playcurrencysetting s WITH(ROWLOCK, UPDLOCK) 
--INNER JOIN #data_old d ON s.FromDate = d.ID


-- Insert new setting
INSERT INTO playcurrencysetting ([SiteId],[SiteName] ,[SportType],[MemberCurrency],[PlayCurrency] ,[FromDate] ,[ToDate])
SELECT [SiteId],[SiteName] ,[SportType],[MemberCurrency], 51 AS PlayCurrency, '2023-09-21' AS FromDate, '2050-01-01' AS ToDate
FROM #data_old

DROP TABLE #data_old


*/

UPDATE s
SET	   s.FromDate = '2023-09-21'
FROM   dbo.playcurrencysetting s WITH(ROWLOCK, UPDLOCK) 
WHERE PlayCurrency = 51

