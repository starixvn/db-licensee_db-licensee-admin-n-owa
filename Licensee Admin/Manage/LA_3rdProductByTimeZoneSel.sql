/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
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
	- 20230224@Danny: Intergrate Jili [#183766]
	- 20230222@Danny: Remove hard-code bettype And ProductID [#183739]
	- 20240301@Danny: Merge virtual sports product [RemineID: #199478]
	- 20240918@Danny: Integrate VS5 [RedmineID: #209929]
	- 20250415@Winston: Integrate VS7 [RemineID: #218989]
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
			CASE WHEN ProductID IN (2, 31, 21, 25, 15, 27, 49, 77, 83, 88, 106) OR ProductPrefix = 'SB_MuayThai'  THEN 1 ELSE 0 END isKeepNegativeFee , 
			CASE WHEN ProductID = 5 THEN 0 ELSE 1 END isKeepNegativePayToSupplier,
			CASE WHEN ProductID IN (2, 22,23,34) OR ProductPrefix = 'SB_BetBuilder' THEN 1 ELSE 0 END isRptBettingSource,
			CASE WHEN ProductPrefix = 'SB_MuayThai' THEN 1 ELSE 0 END isRptBettingBySportSource,
			CASE WHEN TimezoneIDs LIKE '%2%' THEN 1 ELSE 0 END isSupportGMT8,
			CASE WHEN TimezoneIDs LIKE '%0%' THEN 1 ELSE 0 END isSupportGMT0,
			CASE WHEN ProductID = 25 THEN 1 ELSE 0 END isRptLicCashoutSummarySource
	FROM (
			SELECT	CASE WHEN z.ProductID = 1000 THEN 'SB_BetBuilder'
						WHEN z.ProductID = 1001 THEN 'SB_MuayThai'
						ELSE x.ProductPrefix END ProductPrefix, 
					CASE WHEN z.ProductID IN (1000, 1001) THEN 0 ELSE z.ProductID END ProductID, 
					CASE WHEN z.ProductID = 1000 THEN 'BetBuilder' 
						 WHEN z.ProductID = 1001 THEN 'Muay Thai' ELSE x.ProductName END ProductName , 
					z.TimezoneIDs 
			FROM LA_VendorPaymentSetting z WITH(NOLOCK) 
			LEFT  JOIN dbo.Product3rd x WITH(NOLOCK) ON x.Productid = z.ProductId
			WHERE  z.IsActive = 1
			UNION ALL
			SELECT ProductPrefix, ProductID, ProductName, '1' FROM dbo.Product3rd x WITH(NOLOCK) WHERE Productid = 23 --NG2
	) x
	
	IF @isShowDetail = 1
	BEGIN

		SELECT ProductID, ProductCode, ProductName , isKeepNegativeFee, isKeepNegativePayToSupplier, isRptBettingSource, isRptBettingBySportSource, isSupportGMT8, isSupportGMT0, isRptLicCashoutSummarySource
		FROM @tbl_All3rdProducts
		WHERE ( ProductCode IN (SELECT value FROM STRING_SPLIT(@ProductCodes, ',')) OR @ProductCodes = '') 
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
		WHERE ( ProductCode IN (SELECT value FROM STRING_SPLIT(@ProductCodes, ',')) OR @ProductCodes = '') 
			AND (
					 (isSupportGMT8 = CASE WHEN @Timezone = 2 THEN 1 ELSE 0 END AND isSupportGMT0 = CASE WHEN @Timezone = 0 THEN 1 ELSE 0 END)
					 OR @Timezone = 1
				)
			AND @Timezone IN (0,1,2)
		ORDER BY ProductID, ProductName
	END
	
END
GO