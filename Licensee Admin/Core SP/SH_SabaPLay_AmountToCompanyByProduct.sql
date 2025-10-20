/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="1"></info>*/
CREATE PROCEDURE [dbo].[SH_SabaPLay_AmountToCompanyByProduct]
	@PartyIds				VARCHAR(MAX)
	,@ProductIDs			VARCHAR(MAX)
	,@FromDate				DATETIME
	,@ToDate				DATETIME
	,@BaseCurrencyName		VARCHAR(10) = 'EUR'
	,@Environment			VARCHAR(50) = 'LOCAL'
AS

/*
	Created: 20250417@Danny
	DB: DBLIC-bodb_Licensee
	Task: Core SP -  AmountToCompany By Product

	Revisions:
		- 20250417@Danny: Initialize SP [RedmineID: #224104]
		- 20250507@Eddie: Support Billing for SabaPlay [#221987]
		- 20251017@Danny: rebate on licensee winloss [#241642]

	Param's Explanation:

	EXEC SH_SabaPLay_AmountToCompanyByProduct
			@PartyIds				= '9095,9099,9104'
			,@ProductIDs			= '3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20'
			,@FromDate				= '2025-03-01'
			,@ToDate				= '2025-03-31'
			,@BaseCurrencyName		= 'USD'
			,@Environment			= 'LOCAL'
		
*/

BEGIN
	SET NOCOUNT ON
	-- Get Product List
	DROP TABLE IF EXISTS #Products
	CREATE TABLE #Products (ProductId INT, ProductName NVARCHAR(200))
	INSERT INTO #Products (ProductId, ProductName )
	SELECT ProductId, ProductName
	FROM bodb_LicenseeReport.dbo.SabaPlay_Products WITH(NOLOCK)
	WHERE ProductId IN (
		SELECT CAST(value AS INT) ProductId FROM STRING_SPLIT(@ProductIDs,',') x
	)

	-- Get Party List
	CREATE TABLE #PartyList (PartyId INT, OperatorID INT, BaseCurrencyId INT, IsSelected BIT)
	INSERT INTO #PartyList (PartyId)
	SELECT DISTINCT value FROM STRING_SPLIT (@PartyIds, ',')

	UPDATE pl
	SET pl.OperatorID = p.OldRefId, pl.BaseCurrencyId = ISNULL(bc.BaseCurrencyId, 6)
	FROM #PartyList pl
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON pl.PartyId = p.PartyId AND p.PartyType = 1 AND p.PlatformId = 2
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pl.PartyId = pd.PartyId
		OUTER APPLY (
			SELECT TOP 1 bc.BaseCurrencyId
			FROM dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK)
			WHERE bc.PartyId = pl.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
			ORDER BY bc.ToDate DESC
		) bc

	-- Get Exchange Rate
	CREATE TABLE #Exchange (ExchangeId INT, Rate FLOAT, CurrencyCode VARCHAR(65))
	INSERT INTO #Exchange (ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeId,  BaseCurrencyRate , Code
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@ToDate, @ToDate, @BaseCurrencyName)


	DECLARE @tmpRebateGroup TABLE
	(
		GroupId		SMALLINT
		,PartyId	INT
		,Remark		NVARCHAR(4000)
		,ProductId	INT
		,Rate		FLOAT DEFAULT (0)
	)
	INSERT INTO @tmpRebateGroup (GroupId, PartyId, Remark, ProductId, Rate)
	SELECT lgd.DiscountGroupId, lga.PartyID, lgd.Remark, lgp.ProductId, lgdt.Rate
	FROM LA_DiscountGroupHeader lgd WITH(NOLOCK)
	INNER JOIN LA_DiscountGroupProduct lgp WITH(NOLOCK) ON lgd.DiscountGroupId = lgp.DiscountGroupId
	INNER JOIN LA_DiscountGroupAssignment lga WITH(NOLOCK) ON lgd.DiscountGroupId = lga.DiscountGroupId
	INNER JOIN LA_DiscountGroupDetail lgdt WITH(NOLOCK) ON lgd.DiscountGroupId = lgdt.DiscountGroupId
	INNER JOIN #PartyList p ON p.PartyId = lga.PartyID
	WHERE DATEADD(MONTH, DATEDIFF(MONTH, 0, lgd.FromDate), 0) <= @ToDate AND lgd.ToDate >= @FromDate

	DECLARE @Result TABLE(
		PartyId			INT, 
		ProductId		INT, 
		LicensingFee	MONEY, 
		Discount		MONEY, 
		Rebate			MONEY,
		RebateRemark	NVARCHAR(4000),
		RebateRate		MONEY
		)

	
	INSERT INTO @Result(PartyId, ProductId, LicensingFee, Discount, Rebate, RebateRemark, RebateRate)
	SELECT  p.PartyID, 
			pd.ProductID,  
			SUM(ISNULL(sp.FinalLicensingFee,0) * ex.Rate) AS LicensingFee, 
			NULL AS Discount, 
			SUM(CASE WHEN sp.LicenseeWinLoss < 0 THEN 0 ELSE sp.LicenseeWinLoss * tg.Rate END) Rebate,
			tg.Remark,
			tg.Rate
	FROM bodb_LicenseeReport.dbo.SabaPlayPerformance sp WITH(NOLOCK)
	INNER JOIN #PartyList p ON sp.SiteID = p.OperatorID
	INNER JOIN #Products pd ON sp.ProductID = pd.ProductId
	INNER JOIN @tmpRebateGroup tg ON p.PartyId = tg.PartyId AND sp.ProductID = tg.ProductId
	CROSS APPLY
	(	
		SELECT TOP 1 e.CurrencyCode, e.Rate 
		FROM #Exchange e WHERE sp.CurrencyCode = e.CurrencyCode  
			AND e.ExchangeId = CASE WHEN sp.CurrencyCode = 'VND' THEN 51
									WHEN sp.CurrencyCode = 'INR' THEN 61
									WHEN sp.CurrencyCode = 'COP' THEN 84 
									WHEN sp.CurrencyCode = 'JPY' THEN 32 
									WHEN sp.CurrencyCode = 'LBP' THEN 217 
									WHEN sp.CurrencyCode = 'TZS' THEN 135 
									WHEN sp.CurrencyCode = 'KRW' THEN 45
									ELSE e.ExchangeId END
	) ex
	WHERE sp.DataType =2 AND sp.Environment = @Environment AND sp.RptDate = @ToDate
	GROUP BY p.PartyID,  pd.ProductID, tg.Remark, tg.Rate

	-- Adjust rebate
	IF EXISTS (SELECT TOP 1 1 FROM @Result WHERE Rebate > 0 AND LicensingFee > 0 AND Rebate > LicensingFee)
	BEGIN
		UPDATE r
		SET r.Rebate = r.LicensingFee
		FROM @Result r 
		WHERE  Rebate > 0 AND LicensingFee > 0 AND Rebate > LicensingFee

	END

	-- Get Follow Invoice Setting 
	DECLARE @LA_InvoiceSetting TABLE (FromPartyId INT, ToPartyId INT, ProductId TINYINT)
	
	INSERT INTO @LA_InvoiceSetting (FromPartyId, ToPartyId, ProductId)
	SELECT iv.FromPartyId, iv.ToPartyId, iv.ProductId
	FROM dbo.LA_InvoiceSetting iv WITH (NOLOCK)
		INNER JOIN #PartyList p ON p.PartyId = iv.FromPartyId
		INNER JOIN #Products ps ON ps.ProductId = iv.ProductId

	MERGE @Result r 
		USING @LA_InvoiceSetting iv
	ON (r.PartyId = iv.FromPartyId AND r.ProductId = iv.ProductId)
	WHEN NOT MATCHED BY TARGET
		THEN INSERT (PartyId, ProductId, LicensingFee, Discount, Rebate, RebateRemark, RebateRate)
			 VALUES (iv.FromPartyId, iv.ProductId, 0, 0, 0, NULL, NULL)
	WHEN NOT MATCHED BY SOURCE
		THEN DELETE;
	
	SELECT PartyId, ProductId, LicensingFee, Discount, Rebate, RebateRemark, RebateRate
	FROM @Result
END
GO
