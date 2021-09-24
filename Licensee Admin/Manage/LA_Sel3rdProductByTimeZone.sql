/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Sel3rdProductByTimeZone] 
	 @ProductCodes		VARCHAR(4000)		= '',
	 @Timezone			INT = 1,
	 @isShowDetail		INT = 0
AS
/*
 * Created by : [20210915@Danny]
 * Task  : Get 3rd products ByTimeZone
 * Revisions
	- 20210306@Danny: Init SP
 * Param's Explanation:
 *				@Timezone:  = 0  GMT 0 
							= 1: GMT-4
						    = 2: GMT+8	
 * Example 
				EXEC LA_Sel3rdProductByTimeZone @Timezone = 1
				EXEC LA_Sel3rdProductByTimeZone @Timezone = 2
				EXEC LA_Sel3rdProductByTimeZone @Timezone = 0

				EXEC LA_Sel3rdProductByTimeZone @Timezone = 0, @ProductCodes = 'PP,PPL', @isShowDetail = 1
*/
SET NOCOUNT ON

BEGIN
	DECLARE @tbl_All3rdProducts TABLE 
	(
		ProductID						INT
		,ProductCode					VARCHAR(10)
		,ProductName					VARCHAR(50)
		,isKeepNegativeFee				BIT 
		,isKeepNegativePayToSupplier	BIT 
		,isRptBettingSource				TINYINT
		,isRptBettingBySportSource		TINYINT
		,isSupportGMT8					BIT
		,isSupportGMT0					BIT
	)
	INSERT INTO @tbl_All3rdProducts(ProductID, ProductCode,  ProductName,  isKeepNegativeFee, isKeepNegativePayToSupplier, isRptBettingSource, isRptBettingBySportSource, isSupportGMT8, isSupportGMT0) 
	SELECT	ProductID, 
			ProductPrefix,
			ProductName,
			CASE WHEN ProductID IN (2, 31, 21, 25) OR ProductPrefix = 'SB'  THEN 1 ELSE 0 END isKeepNegativeFee , 
			CASE WHEN ProductID IN (2, 8, 10, 23, 49, 28, 31, 32, 34, 36, 40, 45, 46, 47, 50, 51, 52, 55, 56, 57, 59, 60, 61, 62, 65, 67, 68, 69, 36, 39, 21, 25) OR ProductPrefix IN ('SB','SB_38') THEN 1 ELSE 0 END isKeepNegativePayToSupplier,
			CASE WHEN ProductID IN (22,23,34) OR ProductPrefix = 'SB_38' THEN 1 ELSE 0 END isRptBettingSource,
			CASE WHEN ProductPrefix = 'SB' THEN 1 ELSE 0 END isRptBettingBySportSource,
			CASE WHEN ProductID IN (21, 24, 36, 39, 45, 51, 56, 62) THEN 1 ELSE 0 END isSupportGMT8,
			CASE WHEN ProductID IN (32, 65) THEN 1 ELSE 0 END isSupportGMT0
	FROM (
			SELECT x.ProductPrefix, x.ProductID, x.ProductName FROM dbo.Product3rd x WITH(NOLOCK)
			UNION ALL
			SELECT 'SB' AS ProductPrefix, 0, 'Muay Thai' AS ProductID
			UNION ALL 
			SELECT 'SB_38' AS ProductPrefix, 0, 'BetBuilder' AS ProductID
	) x
	WHERE x.ProductPrefix IN ('CO','SB','SB_38','NG','VS','KN','AGC','CB','AB','VB','NG2','FW','CO','VS2','LT','BX','PP','CC','SG','SAG','TG','SXG','IBCLC','BBIN','VS3','RNGW','WM','ION','PGS','JK','BGG','GDG','MXG','HB','CG','PPL','AP','APM','BTC')
	
	IF @isShowDetail = 1
	BEGIN

		SELECT ProductID, ProductCode, ProductName , isKeepNegativeFee, isKeepNegativePayToSupplier, isRptBettingSource, isRptBettingBySportSource, isSupportGMT8, isSupportGMT0
		FROM @tbl_All3rdProducts
		WHERE ( ProductCode IN (SELECT val FROM strSplit(@ProductCodes, ',')) OR @ProductCodes = '') 
			AND (
					 (isSupportGMT8 = CASE WHEN @Timezone = 2 THEN 1 ELSE 0 END AND isSupportGMT0 = CASE WHEN @Timezone = 0 THEN 1 ELSE 0 END)
					 OR @Timezone = 1
				)
	END
	ELSE
	BEGIN
		SELECT ProductCode, ProductName
		FROM @tbl_All3rdProducts
		WHERE ( ProductCode IN (SELECT val FROM strSplit(@ProductCodes, ',')) OR @ProductCodes = '') 
			AND (
					 (isSupportGMT8 = CASE WHEN @Timezone = 2 THEN 1 ELSE 0 END AND isSupportGMT0 = CASE WHEN @Timezone = 0 THEN 1 ELSE 0 END)
					 OR @Timezone = 1
				)
		ORDER BY ProductID, ProductName
	END
	
	

END
GO