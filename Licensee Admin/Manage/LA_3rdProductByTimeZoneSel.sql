/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_3rdProductByTimeZoneSel] 
	 @ProductCodes		VARCHAR(4000)		= '',
	 @Timezone			INT = 1,
	 @isShowDetail		INT = 0
AS
/*
 * Created by : [20210915@Danny]
 * Task  : Get 3rd products ByTimeZone
 * Revisions
	- 20210306@Danny: Init SP [#155402]
	- 20220405@Danny: Intergrate Guaranteed Gaming [#167626]
	- 20221123@Danny: Intergrate MG-RNG [#176986]
 * Param's Explanation:
 *				@Timezone:  = 0  GMT 0 
							= 1: GMT-4
						    = 2: GMT+8	
 * Example 
				-- Dropdown
				EXEC LA_3rdProductByTimeZoneSel @Timezone = 1
				EXEC LA_3rdProductByTimeZoneSel @Timezone = 2
				EXEC LA_3rdProductByTimeZoneSel @Timezone = 0

				-- 
				EXEC [LA_3rdProductByTimeZoneSel] @Timezone = 0, @ProductCodes = 'PP,PPL', @isShowDetail = 1
*/
SET NOCOUNT ON

BEGIN
	DECLARE @tbl_All3rdProducts TABLE 
	(
		ProductID						INT
		,ProductCode					VARCHAR(50)
		,ProductName					VARCHAR(50)
		,isKeepNegativeFee				BIT 
		,isKeepNegativePayToSupplier	BIT 
		,isRptBettingSource				TINYINT
		,isRptBettingBySportSource		TINYINT
		,isSupportGMT8					BIT
		,isSupportGMT0					BIT
		,isRptLicCashoutSummarySource	BIT
	)
	INSERT INTO @tbl_All3rdProducts(ProductID, ProductCode,  ProductName,  isKeepNegativeFee, isKeepNegativePayToSupplier, isRptBettingSource, isRptBettingBySportSource, isSupportGMT8, isSupportGMT0, isRptLicCashoutSummarySource) 
	SELECT	ProductID, 
			ProductPrefix,
			ProductName,
			CASE WHEN ProductID IN (2, 31, 21, 25, 15) OR ProductPrefix = 'SB_MuayThai'  THEN 1 ELSE 0 END isKeepNegativeFee , 
			CASE WHEN ProductID IN (2, 8, 10, 23, 49, 28, 31, 32, 34, 36, 40, 45, 46, 47, 50, 51, 52, 55, 56, 57, 59, 60, 61, 62, 65, 67, 68, 69, 36, 39, 21, 25, 15, 24, 27, 22, 70, 73) OR ProductPrefix IN ('SB_MuayThai','SB_BetBuilder') THEN 1 ELSE 0 END isKeepNegativePayToSupplier,
			CASE WHEN ProductID IN (2, 22,23,34) OR ProductPrefix = 'SB_BetBuilder' THEN 1 ELSE 0 END isRptBettingSource,
			CASE WHEN ProductPrefix = 'SB_MuayThai' THEN 1 ELSE 0 END isRptBettingBySportSource,
			CASE WHEN ProductID IN (21, 24, 36, 39, 45, 51, 56, 62, 70) THEN 1 ELSE 0 END isSupportGMT8,
			CASE WHEN ProductID IN (32, 65, 73) THEN 1 ELSE 0 END isSupportGMT0,
			CASE WHEN ProductID = 25 THEN 1 ELSE 0 END
	FROM (
			SELECT x.ProductPrefix, x.ProductID, x.ProductName FROM dbo.Product3rd x WITH(NOLOCK)
			UNION ALL
			SELECT 'SB_MuayThai' AS ProductPrefix, 0, 'Muay Thai' AS ProductID
			UNION ALL 
			SELECT 'SB_BetBuilder' AS ProductPrefix, 0, 'BetBuilder' AS ProductID
	) x
	WHERE x.ProductPrefix IN ('CO','SB_BetBuilder','SB_MuayThai','NG','VS','KN','AGC','CB','AB','VB','NG2','FW','CO','VS2','LT','BX','PP','CC','SG','SAG','TG','SXG','IBCLC','BBIN','VS3','RNGW','WM','ION','PGS','JK','BGG','GDG','MXG','HB','CG','PPL','AP','APM','BTC','FGGL','MGRNG')
	
	IF @isShowDetail = 1
	BEGIN

		SELECT ProductID, ProductCode, ProductName , isKeepNegativeFee, isKeepNegativePayToSupplier, isRptBettingSource, isRptBettingBySportSource, isSupportGMT8, isSupportGMT0, isRptLicCashoutSummarySource
		FROM @tbl_All3rdProducts
		WHERE ( ProductCode IN (SELECT val FROM strSplit(@ProductCodes, ',')) OR @ProductCodes = '') 
			AND (
					 (isSupportGMT8 = CASE WHEN @Timezone = 2 THEN 1 ELSE 0 END AND isSupportGMT0 = CASE WHEN @Timezone = 0 THEN 1 ELSE 0 END)
					 OR @Timezone = 1
				)
			AND @Timezone IN (0,1,2)
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
			AND @Timezone IN (0,1,2)
		ORDER BY ProductID, ProductName
	END
	
END
GO