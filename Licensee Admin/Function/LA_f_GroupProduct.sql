/*<info serverAlias="DBCUST-bodb_Licensee,DBLIC-bodb_Licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
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
*/

RETURN
	WITH SB_mapping AS
	(
			SELECT		ProductId, 
						ProductName, 
						ProductPrefix						AS ProductCode, 
						CONVERT(INT, 0)						AS GroupProductId,
						CONVERT(VARCHAR(50), 'Sportsbook')	AS GroupProductName,
						CONVERT(VARCHAR(20), 'SB')			AS GroupProductCode,
						CASE WHEN ProductID = 63 THEN 
						     CASE WHEN ISNULL(@Todate,'9999-12-31') > '2021-11-30' THEN CASE WHEN  ISNULL(@FromDate,'1900-01-01') <= '2021-11-30' THEN '2021-12-01' ELSE  ISNULL(@FromDate,'1900-01-01') END  END
						ELSE  ISNULL(@FromDate,'1900-01-01') END Fromdate,

						CASE WHEN ProductID = 63 THEN 
						     CASE WHEN ISNULL(@Todate,'9999-12-31') > '2021-11-30' THEN ISNULL(@Todate,'9999-12-31') ELSE NULL END 
						ELSE ISNULL(@Todate,'9999-12-31') END Todate
			FROM	bodb_Licensee.dbo.LA_f_Products3rd('SB,BTC,SLT') -- SB and BTC are always at the same group

	), ProductInput AS
	(
			SELECT		ProductId, 
						ProductName, 
						ProductPrefix	AS ProductCode, 
						ProductId		AS GroupProductId,
						ProductName		AS GroupProductName,
						ProductPrefix	AS GroupProductCode,
						CASE WHEN ProductID = 63 THEN CASE WHEN  ISNULL(@FromDate,'1900-01-01') <= '2021-11-30' THEN  ISNULL(@FromDate,'1900-01-01') ELSE NULL END
						ELSE  ISNULL(@FromDate,'1900-01-01') END FromDate,
						CASE WHEN ProductID = 63 THEN  CASE WHEN ISNULL(@Todate,'9999-12-31') > '2021-11-30' THEN '2021-11-30' ELSE ISNULL(@Todate,'9999-12-31') END
						ELSE ISNULL(@Todate,'9999-12-31') END Todate
			FROM	bodb_Licensee.dbo.LA_f_Products3rd(@ProductCode)
			WHERE	ProductId NOT IN (0, 69)
	), cte AS
	(
	SELECT	ProductId,ProductName,ProductCode,GroupProductId,GroupProductName,GroupProductCode, FromDate, ToDate 
	FROM	SB_mapping
	WHERE FromDate IS NOT NULL AND ToDate IS NOT NULL
	UNION ALL
	SELECT	ProductId,ProductName,ProductCode,GroupProductId,GroupProductName,GroupProductCode, FromDate, ToDate 
	FROM	ProductInput
	WHERE FromDate IS NOT NULL AND ToDate IS NOT NULL
	) SELECT ProductId,ProductName,ProductCode,GroupProductId,GroupProductName,GroupProductCode, FromDate, ToDate  
	FROM cte
	WHERE ( GroupProductCode IN (SELECT val FROM strSplit(@ProductCode,',')) OR @ProductCode = '')