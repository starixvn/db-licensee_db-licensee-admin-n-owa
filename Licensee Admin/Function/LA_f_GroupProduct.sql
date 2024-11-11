/*<info serverAlias="DBCUST-bodb_Licensee,DBLIC-bodb_Licensee" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO
ALTER FUNCTION [dbo].[LA_f_GroupProduct] (
	@ProductCode VARCHAR(4000) = '',
	@FromDate DATE = NULL, 
	@ToDate DATE = NULL
)
RETURNS TABLE
AS

/*
	Created: 20210812@Percy
	DB: DBCUST-bodb_Licensee,DBLIC-bodb_Licensee
	Task: Core function - Group Product

	Revisions:
		- 20210812@Percy: Initialize function [RedmineID: #159691]
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20220210@Percy: Return OfferSite, EndOfSupportDate [RedmineID: #163495]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20240301@Danny: Merge virtual sports product [RemineID: #199478]
		- 20240911@Danny: Integrate VS5 [RemineID: #209929]
		- 20241111@Danny: Integrate VS6 [RemineID: #212501]
*/

RETURN
	WITH group_Product_config AS
	(
		 SELECT 0 AS GroupProductId, 63 AS ProductID, '2021-12-01' FromDate, '9999-12-31' Todate, CONVERT(VARCHAR(50),'Sportsbook') AS GroupProductName, CONVERT(VARCHAR(20),'SB') AS GroupProductCode
		 UNION ALL SELECT 63 AS GroupProductId, 63 AS ProductID, '1900-01-01' FromDate, '2021-11-30' Todate, 'Sportsbook' GroupProductName, 'SB' AS GroupProductCode
		 UNION ALL SELECT 0 AS GroupProductId, 69 AS ProductID, '1900-01-01' FromDate, '9999-12-31' Todate, 'Sportsbook' GroupProductName, 'SB' AS GroupProductCode
		 UNION ALL SELECT 5 AS GroupProductId, 27 AS ProductID, '2024-03-01' FromDate, '9999-12-31' Todate, 'Virtual Sports' GroupProductName, 'VS' AS GroupProductCode
		 UNION ALL SELECT 27 AS GroupProductId, 27 AS ProductID, '1900-01-01' FromDate, '2024-02-29' Todate, 'Virtual Sports 2' GroupProductName, 'VS2' AS GroupProductCode
		 UNION ALL SELECT 5 AS GroupProductId, 77 AS ProductID, '2024-03-01' FromDate, '9999-12-31' Todate, 'Virtual Sports' GroupProductName, 'VS' AS GroupProductCode
		 UNION ALL SELECT 77 AS GroupProductId, 77 AS ProductID, '1900-01-01' FromDate, '2024-02-29' Todate, 'Virtual Sports 3' GroupProductName, 'LG' AS GroupProductCode
		 UNION ALL SELECT 5 AS GroupProductId, 83 AS ProductID, '2024-03-01' FromDate, '9999-12-31' Todate, 'Virtual Sports' GroupProductName, 'VS' AS GroupProductCode
		 UNION ALL SELECT 83 AS GroupProductId, 83 AS ProductID, '1900-01-01' FromDate, '2024-02-29' Todate, 'Virtual Sports 4' GroupProductName, 'VS4' AS GroupProductCode
		 UNION ALL SELECT 5 AS GroupProductId, 88 AS ProductID, '1900-01-01' FromDate, '9999-12-31' Todate, 'Virtual Sports' GroupProductName, 'VS' AS GroupProductCode
		  UNION ALL SELECT 5 AS GroupProductId, 71 AS ProductID, '1900-01-01' FromDate, '9999-12-31' Todate, 'Virtual Sports' GroupProductName, 'VS' AS GroupProductCode
	), ProductInput AS
	(
		SELECT		l.ProductId, 
					l.ProductName, 
					l.ProductPrefix	AS ProductCode, 
					ISNULL(gpc.GroupProductId ,l.ProductId)	AS GroupProductId,
					ISNULL(gpc.GroupProductName,l.ProductName) AS GroupProductName,
					ISNULL(gpc.GroupProductCode,l.ProductPrefix) AS GroupProductCode,
					ISNULL(gpc.FromDate,'1900-01-01') FromDate,
					ISNULL(gpc.Todate,'9999-12-31') ToDate,
					l.OfferSite,
					l.EndOfSupportDate
		FROM	dbo.LA_f_Products3rd('') l
		LEFT JOIN group_Product_config gpc ON  l.ProductID = gpc.ProductID
	)
	SELECT  ProductId,
			ProductName,
			ProductCode,
			GroupProductId,
			GroupProductName,
			GroupProductCode, 
			CASE WHEN ISNULL(@FromDate,'1900-01-01') BETWEEN FromDate AND Todate THEN ISNULL(@FromDate,'1900-01-01') ELSE FromDate END FromDate, 
			CASE WHEN ISNULL(@ToDate,'9999-12-31') BETWEEN FromDate AND Todate THEN ISNULL(@ToDate,'9999-12-31') ELSE ToDate END ToDate,
			OfferSite, 
			EndOfSupportDate 
	FROM   ProductInput 
	WHERE ( GroupProductCode IN (SELECT value FROM STRING_SPLIT(@ProductCode,',')) OR @ProductCode = '')
	AND FromDate <= ISNULL(@ToDate,'9999-12-31') AND ToDate >= ISNULL(@FromDate, '1900-01-01')